import { WebSocketServer, WebSocket } from 'ws';
import Anthropic from '@anthropic-ai/sdk';
import { getToolDefinitions } from './tools/index.js';
import { executeNodeTool, isNodeTool } from './tools/nodeRouter.js';

interface ChatMessage {
  type: 'chat';
  conversationId: string;
  content: string;
}

interface ToolResultMessage {
  type: 'tool_result';
  conversationId: string;
  toolUseId: string;
  toolName: string;
  toolResult: string;
}

interface SetApiKeyMessage {
  type: 'set_api_key';
  apiKey: string;
}

interface McpAuthMessage {
  type: 'mcp_auth';
  serverId: string;
  token: string;
}

type IncomingMessage = ChatMessage | ToolResultMessage | SetApiKeyMessage | McpAuthMessage;

interface AssistantMessage {
  type: 'assistant_message';
  conversationId: string;
  content: string;
}

interface ToolRequestMessage {
  type: 'tool_request';
  conversationId: string;
  toolUseId: string;
  toolName: string;
  input: Record<string, unknown>;
}

interface StreamChunkMessage {
  type: 'stream_chunk';
  conversationId: string;
  content: string;
}

type OutgoingMessage = AssistantMessage | ToolRequestMessage | StreamChunkMessage;

type MessageParam = Anthropic.MessageParam;
type ContentBlockParam = Anthropic.ContentBlockParam;

const conversationHistories = new Map<string, MessageParam[]>();
const pendingToolResults = new Map<string, (result: string) => void>();

// Guardrails: tool results like screenshots (base64) can be enormous.
// Keep tool results only long enough for the *next* model call, then redact them.
const MAX_HISTORY_MESSAGES = 40;
const MAX_RETAINED_TEXT_CHARS = 20_000;

let activeClient: WebSocket | null = null;
let anthropic: Anthropic | null = null;
let runtimeApiKey: string | null = null;

function getAnthropicClient(): Anthropic {
  if (!anthropic) {
    anthropic = new Anthropic(runtimeApiKey ? { apiKey: runtimeApiKey } : undefined);
  }
  return anthropic;
}

function trimHistory(history: MessageParam[]): void {
  if (history.length <= MAX_HISTORY_MESSAGES) return;
  history.splice(0, history.length - MAX_HISTORY_MESSAGES);
}

function redactLargeText(text: string): string {
  if (text.length <= MAX_RETAINED_TEXT_CHARS) return text;
  const head = text.slice(0, 2000);
  const tail = text.slice(-500);
  return `${head}\n\n[...redacted ${text.length - (head.length + tail.length)} chars...]\n\n${tail}`;
}

function sanitizeRetainedMessageContent(content: unknown): unknown {
  if (typeof content === 'string') {
    return redactLargeText(content);
  }

  if (Array.isArray(content)) {
    return content.map((block: any) => {
      if (block && typeof block === 'object' && block.type === 'tool_result' && typeof block.content === 'string') {
        // Tool results are the main source of memory blow-ups (screenshots/base64, big AX dumps).
        // Keep small non-image results (truncated), but aggressively redact likely screenshots.
        const text = block.content;
        const bytes = Buffer.byteLength(text, 'utf8');

        const looksLikeBase64Image =
          bytes > 50_000 &&
          (text.startsWith('iVBOR') || // PNG
            text.startsWith('/9j/') || // JPEG
            text.startsWith('R0lGOD') || // GIF
            text.startsWith('UklGR')); // WEBP (RIFF)

        return {
          ...block,
          content: looksLikeBase64Image
            ? `[tool_result redacted (image): tool_use_id=${block.tool_use_id ?? 'unknown'} bytes=${bytes}]`
            : redactLargeText(text),
        };
      }

      if (block && typeof block === 'object' && typeof block.text === 'string') {
        // Future-proofing: some SDK variants use { type: 'text', text: '...' } blocks.
        return { ...block, text: redactLargeText(block.text) };
      }

      return block;
    });
  }

  return content;
}

function redactOldToolResults(history: MessageParam[]): void {
  // Keep the most recent message as-is (it may be the just-produced tool_result the model still needs).
  const keepIndex = history.length - 1;
  for (let i = 0; i < history.length; i++) {
    if (i === keepIndex) continue;
    const msg: any = history[i];
    if (!msg || typeof msg !== 'object') continue;
    msg.content = sanitizeRetainedMessageContent(msg.content);
  }
}

function sendToClient(ws: WebSocket, message: OutgoingMessage): void {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(message));
  }
}

export function startBridge(port: number): void {
  const wss = new WebSocketServer({ port });

  console.log(`WebSocket server listening on port ${port}`);

  wss.on('connection', (ws) => {
    console.log('Swift app connected');
    activeClient = ws;

    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString()) as IncomingMessage;
        handleMessage(ws, message);
      } catch (error) {
        console.error('Failed to parse message:', error);
      }
    });

    ws.on('close', () => {
      console.log('Swift app disconnected');
      if (activeClient === ws) {
        activeClient = null;
      }

      // Free memory aggressively on disconnect; the Swift app can reconnect and rebuild context.
      conversationHistories.clear();
      pendingToolResults.clear();
    });

    ws.on('error', (error) => {
      console.error('WebSocket error:', error);
    });
  });
}

function handleMessage(ws: WebSocket, message: IncomingMessage): void {
  switch (message.type) {
    case 'chat':
      handleChat(ws, message);
      break;
    case 'tool_result':
      handleToolResult(ws, message);
      break;
    case 'set_api_key':
      runtimeApiKey = message.apiKey;
      anthropic = null; // reset so next call uses the new key
      console.log('API key updated from Swift app');
      break;
    case 'mcp_auth':
      handleMcpAuth(message);
      break;
    default:
      console.warn('Unknown message type:', (message as Record<string, unknown>).type);
  }
}

function handleMcpAuth(message: McpAuthMessage): void {
  // Token may be empty (clear). Persist in-memory for subsequent MCP tool calls.
  // We set it on the shared MCP manager instance that `getToolDefinitions()` returns.
  // Note: `getToolDefinitions()` creates/returns a stable manager instance.
  getToolDefinitions()
    .then(({ mcp }) => mcp.setAuthToken(message.serverId, message.token))
    .catch((err) => {
      console.error('Failed to apply MCP auth update:', err);
    });
}

async function handleChat(ws: WebSocket, message: ChatMessage): Promise<void> {
  const { conversationId, content } = message;
  console.log(`[${conversationId}] User: ${content}`);

  // Reject if no API key has been provided yet
  if (!runtimeApiKey) {
    sendToClient(ws, {
      type: 'assistant_message',
      conversationId,
      content: 'No Anthropic API key configured. Please set your API key in Settings.',
    });
    return;
  }

  // Get or create conversation history
  if (!conversationHistories.has(conversationId)) {
    conversationHistories.set(conversationId, []);
  }
  const history = conversationHistories.get(conversationId)!;

  // Add user message
  history.push({ role: 'user', content });
  trimHistory(history);

  try {
    await runConversationLoop(ws, conversationId, history);
  } catch (error) {
    console.error('Claude API error:', error);
    sendToClient(ws, {
      type: 'assistant_message',
      conversationId,
      content: `Error: ${error instanceof Error ? error.message : 'Unknown error'}`,
    });
  }
}

async function runConversationLoop(
  ws: WebSocket,
  conversationId: string,
  history: MessageParam[],
): Promise<void> {
  const client = getAnthropicClient();

  while (true) {
    const { tools, mcp, skills } = await getToolDefinitions();
    const linearSkill = skills.find((s) => s.id === 'linear' || s.name.toLowerCase() === 'linear');
    const linearHint = linearSkill?.defaultPrompt;

    // Redact old tool results before sending the next request to avoid unbounded growth
    // from screenshots/large AX dumps that are no longer needed for model context.
    redactOldToolResults(history);

    // Stream the response
    let fullText = '';
    const toolUseBlocks: Array<{ id: string; name: string; input: Record<string, unknown> }> = [];
    let currentToolUse: { id: string; name: string; inputJson: string } | null = null;

    const stream = client.messages.stream({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 4096,
      system: [
        'You are Flux, a macOS AI desktop copilot. You can see the user\'s screen, read window contents, and execute commands.',
        'Be concise and helpful.',
        'When the user asks about what\'s on their screen, use the read_ax_tree or capture_screen tools.',
        'Agent SDK skills reference: https://platform.claude.com/docs/en/agent-sdk/skills',
        mcp.hasServer('linear')
          ? [
              'For Linear work (issues/projects), use the linear__* tools.',
              linearHint ? `Skill hint: ${linearHint}` : '',
              'If Linear tools fail due to auth, call linear__setup and explain what to configure.',
            ]
              .filter(Boolean)
              .join(' ')
          : '',
      ]
        .filter(Boolean)
        .join(' '),
      messages: history,
      tools: tools as Anthropic.Tool[],
    });

    for await (const event of stream) {
      if (event.type === 'content_block_start') {
        if (event.content_block.type === 'tool_use') {
          currentToolUse = {
            id: event.content_block.id,
            name: event.content_block.name,
            inputJson: '',
          };
        }
      } else if (event.type === 'content_block_delta') {
        if (event.delta.type === 'text_delta') {
          fullText += event.delta.text;
          sendToClient(ws, {
            type: 'stream_chunk',
            conversationId,
            content: event.delta.text,
          });
        } else if (event.delta.type === 'input_json_delta' && currentToolUse) {
          currentToolUse.inputJson += event.delta.partial_json;
        }
      } else if (event.type === 'content_block_stop') {
        if (currentToolUse) {
          let input: Record<string, unknown> = {};
          try {
            input = JSON.parse(currentToolUse.inputJson || '{}');
          } catch {
            // empty input
          }
          toolUseBlocks.push({
            id: currentToolUse.id,
            name: currentToolUse.name,
            input,
          });
          currentToolUse = null;
        }
      }
    }

    const finalMessage = await stream.finalMessage();

    // Add assistant message to history
    history.push({ role: 'assistant', content: finalMessage.content });
    trimHistory(history);

    // If no tool use, we're done
    if (finalMessage.stop_reason !== 'tool_use' || toolUseBlocks.length === 0) {
      if (fullText) {
        // Full message already streamed via chunks
      }
      break;
    }

    // Handle tool use — request execution from Swift app
    const toolResults: ContentBlockParam[] = [];

    for (const toolUse of toolUseBlocks) {
      console.log(`[${conversationId}] Tool request: ${toolUse.name}`);

      const result = isNodeTool(toolUse.name, mcp)
        ? await executeNodeTool(toolUse.name, toolUse.input, mcp)
        : await requestToolFromSwift(ws, conversationId, toolUse);
      console.log(`[${conversationId}] Tool result for ${toolUse.name}: ${result.substring(0, 100)}...`);

      toolResults.push({
        type: 'tool_result',
        tool_use_id: toolUse.id,
        content: result,
      });
    }

    // Add tool results to history
    history.push({ role: 'user', content: toolResults });
    trimHistory(history);
  }
}

function requestToolFromSwift(
  ws: WebSocket,
  conversationId: string,
  toolUse: { id: string; name: string; input: Record<string, unknown> },
): Promise<string> {
  return new Promise((resolve) => {
    const key = `${conversationId}:${toolUse.id}`;
    pendingToolResults.set(key, resolve);

    sendToClient(ws, {
      type: 'tool_request',
      conversationId,
      toolUseId: toolUse.id,
      toolName: toolUse.name,
      input: toolUse.input,
    });

    // Timeout after 30 seconds
    setTimeout(() => {
      if (pendingToolResults.has(key)) {
        pendingToolResults.delete(key);
        resolve('Tool execution timed out');
      }
    }, 30000);
  });
}

function handleToolResult(_ws: WebSocket, message: ToolResultMessage): void {
  const key = `${message.conversationId}:${message.toolUseId}`;
  const resolve = pendingToolResults.get(key);

  if (resolve) {
    pendingToolResults.delete(key);
    resolve(message.toolResult);
  } else {
    console.warn(`No pending tool result for key: ${key}`);
  }
}
