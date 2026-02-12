import { WebSocketServer, WebSocket } from 'ws';
import crypto from 'crypto';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { query } from '@anthropic-ai/claude-agent-sdk';
import { createTelegramBot } from './telegram/bot.js';
import { createLogger } from './logger.js';

interface ChatMessage {
  type: 'chat';
  conversationId: string;
  content: string;
  images?: ChatImagePayload[];
}

interface ChatImagePayload {
  fileName: string;
  mediaType: string;
  data: string;
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

interface SetTelegramConfigMessage {
  type: 'set_telegram_config';
  botToken: string;
  defaultChatId: string;
}

interface ActiveAppUpdateMessage {
  type: 'active_app_update';
  appName: string;
  bundleId: string;
  pid: number;
  appInstruction?: string;
}

type IncomingMessage = ChatMessage | ToolResultMessage | SetApiKeyMessage | McpAuthMessage | SetTelegramConfigMessage | ActiveAppUpdateMessage;

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

interface ToolUseStartMessage {
  type: 'tool_use_start';
  conversationId: string;
  toolUseId: string;
  toolName: string;
  inputSummary: string;
}

interface ToolUseCompleteMessage {
  type: 'tool_use_complete';
  conversationId: string;
  toolUseId: string;
  toolName: string;
  resultPreview: string;
}

interface StreamChunkMessage {
  type: 'stream_chunk';
  conversationId: string;
  content: string;
}

interface RunStatusMessage {
  type: 'run_status';
  conversationId: string;
  isWorking: boolean;
}

type OutgoingMessage =
  | AssistantMessage
  | ToolRequestMessage
  | ToolUseStartMessage
  | ToolUseCompleteMessage
  | StreamChunkMessage
  | RunStatusMessage;

interface SDKUserMessage {
  type: 'user';
  message: { role: 'user'; content: string | SDKUserContentBlock[] };
  parent_tool_use_id: null;
  session_id: string;
}

type SDKUserContentBlock = SDKUserTextContentBlock | SDKUserImageContentBlock;

interface SDKUserTextContentBlock {
  type: 'text';
  text: string;
}

interface SDKUserImageContentBlock {
  type: 'image';
  source: {
    type: 'base64';
    media_type: string;
    data: string;
  };
}

interface QueuedUserMessage {
  text: string;
  images: ChatImagePayload[];
}

const log = createLogger('bridge');

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const AGENT_IDLE_TIMEOUT_MS = 120_000;
const TOOL_TIMEOUT_MS = 60_000;

process.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = '1';

const sessions = new Map<string, ConversationSession>();
const telegramSessionMap = new Map<string, string>();
const telegramConversationMeta = new Map<string, { chatId: string; threadId?: number }>();
const mcpAuthTokens = new Map<string, string>();

let activeClient: WebSocket | null = null;
let runtimeApiKey: string | null = process.env.ANTHROPIC_API_KEY ?? null;
let mcpBridgeUrl = '';

/** Currently active (frontmost) app, updated live by the Swift client. */
let lastActiveApp: { appName: string; bundleId: string; pid: number; appInstruction?: string } | null = null;

function sanitizeAppInstruction(instruction: string | undefined): string | undefined {
  if (!instruction) return undefined;
  const trimmed = instruction.trim();
  if (trimmed.length === 0) return undefined;
  const maxLen = 2_000;
  const clipped = trimmed.length > maxLen ? `${trimmed.slice(0, maxLen)}…` : trimmed;
  return clipped.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

interface ConversationSession {
  conversationId: string;
  stream: MessageStream | null;
  sessionId?: string;
  lastAssistantUuid?: string;
  isRunning: boolean;
  idleTimer?: NodeJS.Timeout;
  pendingMessages: QueuedUserMessage[];
  /** Track tool_use content blocks by stream index during streaming */
  toolUseByIndex: Map<number, { id: string; name: string; inputChunks: string[] }>;
  /** Non-MCP tool calls started but not yet completed (toolUseId → toolName) */
  pendingToolCompletions: Map<string, string>;
}

class MessageStream {
  private queue: SDKUserMessage[] = [];
  private waiting: (() => void) | null = null;
  private done = false;

  push(message: QueuedUserMessage): void {
    if (this.done) return;
    const content = userMessageContent(message);
    this.queue.push({
      type: 'user',
      message: { role: 'user', content },
      parent_tool_use_id: null,
      session_id: '',
    });
    this.waiting?.();
  }

  end(): void {
    if (this.done) return;
    this.done = true;
    this.waiting?.();
  }

  isDone(): boolean {
    return this.done;
  }

  async *[Symbol.asyncIterator](): AsyncGenerator<SDKUserMessage> {
    while (true) {
      while (this.queue.length > 0) {
        yield this.queue.shift()!;
      }
      if (this.done) return;
      await new Promise<void>((resolve) => {
        this.waiting = resolve;
      });
      this.waiting = null;
    }
  }
}

const telegramBot = createTelegramBot({
  onMessage: async (msg) => {
    await handleTelegramMessage(msg.chatId, msg.threadId, msg.text);
  },
  onLog: (level, message) => {
    if (level === 'error') log.error(message);
    else if (level === 'warn') log.warn(message);
    else log.info(message);
  },
});

export function startBridge(port: number): void {
  const wss = new WebSocketServer({ port });
  startMcpBridge(port + 1);

  log.info(`WebSocket server listening on port ${port}`);

  wss.on('connection', (ws) => {
    log.info('Swift app connected');
    activeClient = ws;

    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString()) as IncomingMessage;
        handleMessage(ws, message);
      } catch (error) {
        log.error('Failed to parse message:', error);
      }
    });

    ws.on('close', () => {
      log.info('Swift app disconnected');
      if (activeClient === ws) {
        activeClient = null;
      }

      // Fail any pending tool calls waiting on Swift.
      flushPendingToolCalls('Flux is offline. Open the app to reconnect.');
    });

    ws.on('error', (error) => {
      log.error('WebSocket error:', error);
    });
  });
}

function handleMessage(ws: WebSocket, message: IncomingMessage): void {
  switch (message.type) {
    case 'chat':
      handleChat(ws, message);
      break;
    case 'tool_result':
      handleToolResult(message);
      break;
    case 'set_api_key':
      runtimeApiKey = message.apiKey;
      if (runtimeApiKey) {
        process.env.ANTHROPIC_API_KEY = runtimeApiKey;
      }
      log.info('API key updated from Swift app');
      break;
    case 'mcp_auth':
      handleMcpAuth(message);
      break;
    case 'set_telegram_config':
      telegramBot.updateConfig({
        botToken: message.botToken ?? '',
        defaultChatId: message.defaultChatId ?? '',
      });
      break;
    case 'active_app_update':
      handleActiveAppUpdate(message);
      break;
    default:
      log.warn('Unknown message type:', (message as Record<string, unknown>).type);
  }
}

function handleActiveAppUpdate(message: ActiveAppUpdateMessage): void {
  lastActiveApp = {
    appName: message.appName ?? 'Unknown',
    bundleId: message.bundleId ?? 'unknown',
    pid: message.pid ?? 0,
    appInstruction: sanitizeAppInstruction(message.appInstruction),
  };
  log.info(`Active app updated: ${lastActiveApp.appName} (${lastActiveApp.bundleId})`);
}

function handleMcpAuth(message: McpAuthMessage): void {
  const token = message.token ?? '';
  if (token.trim().length === 0) {
    mcpAuthTokens.delete(message.serverId);
  } else {
    mcpAuthTokens.set(message.serverId, token);
  }
}

async function handleChat(ws: WebSocket, message: ChatMessage): Promise<void> {
  const { conversationId, content } = message;
  const images = sanitizeChatImages(message.images);
  const summary = content.trim().length > 0 ? content : '[image-only message]';
  const imageSummary = images.length > 0 ? ` (+${images.length} image${images.length === 1 ? '' : 's'})` : '';
  log.info(`[${conversationId}] User: ${summary}${imageSummary}`);

  if (!runtimeApiKey) {
    sendToClient(ws, {
      type: 'assistant_message',
      conversationId,
      content: 'No Anthropic API key configured. Please set your API key in Island Settings.',
    });
    return;
  }

  enqueueUserMessage(conversationId, content, images);
}

function sanitizeChatImages(images: ChatImagePayload[] | undefined): ChatImagePayload[] {
  if (!Array.isArray(images)) return [];
  return images
    .filter((image) => typeof image?.data === 'string' && image.data.length > 0)
    .map((image) => {
      const mediaType = image.mediaType?.startsWith('image/') ? image.mediaType : 'image/png';
      const fileName = typeof image.fileName === 'string' && image.fileName.trim().length > 0
        ? image.fileName
        : 'image';
      return {
        fileName,
        mediaType,
        data: image.data,
      };
    });
}

function userMessageContent(message: QueuedUserMessage): string | SDKUserContentBlock[] {
  if (message.images.length === 0) {
    return message.text;
  }

  const blocks: SDKUserContentBlock[] = [];
  if (message.text.trim().length > 0) {
    blocks.push({
      type: 'text',
      text: message.text,
    });
  }

  for (const image of message.images) {
    blocks.push({
      type: 'image',
      source: {
        type: 'base64',
        media_type: image.mediaType,
        data: image.data,
      },
    });
  }

  if (blocks.length === 0) {
    blocks.push({
      type: 'text',
      text: '',
    });
  }
  return blocks;
}

function enqueueUserMessage(conversationId: string, content: string, images: ChatImagePayload[] = []): void {
  if (content.trim().length === 0 && images.length === 0) return;
  const session = getSession(conversationId);
  const message: QueuedUserMessage = { text: content, images };

  if (session.isRunning) {
    if (session.stream && !session.stream.isDone()) {
      session.stream.push(message);
      touchIdle(session);
    } else {
      session.pendingMessages.push(message);
    }
    return;
  }

  startSessionRun(session, [message]);
}

function startSessionRun(session: ConversationSession, messages: QueuedUserMessage[]): void {
  session.stream = new MessageStream();
  for (const msg of messages) {
    session.stream.push(msg);
  }
  session.isRunning = true;
  touchIdle(session);

  void runAgentSession(session).catch((error) => {
    log.error('Agent run error:', error);
    sendToClient(activeClient, {
      type: 'assistant_message',
      conversationId: session.conversationId,
      content: `Error: ${error instanceof Error ? error.message : 'Unknown error'}`,
    });
  });
}

async function runAgentSession(session: ConversationSession): Promise<void> {
  if (!session.stream) return;

  sendToClient(activeClient, { type: 'run_status', conversationId: session.conversationId, isWorking: true });

  const runId = crypto.randomUUID();
  const mcpServerConfig = resolveMcpServerConfig(session.conversationId, runId);

  try {
    for await (const message of query({
      prompt: session.stream,
      options: {
        cwd: process.cwd(),
        resume: session.sessionId,
        resumeSessionAt: session.lastAssistantUuid,
        permissionMode: 'bypassPermissions',
        allowDangerouslySkipPermissions: true,
        includePartialMessages: true,
        settingSources: ['project', 'user'],
        allowedTools: [
          'WebSearch',
          'WebFetch',
          'ToolSearch',
          'TodoWrite',
          'Task',
          'TaskOutput',
          'TaskStop',
          'TeamCreate',
          'TeamDelete',
          'SendMessage',
          'Skill',
          'NotebookEdit',
          'mcp__flux__*',
        ],
        mcpServers: {
          flux: mcpServerConfig,
        },
        model: 'claude-sonnet-4-20250514',
        systemPrompt: {
          type: 'preset',
          preset: 'claude_code',
          append: buildFluxSystemPrompt(),
        },
      },
    })) {
      handleAgentMessage(session, message as any);
    }
  } finally {
    clearIdle(session);
    session.isRunning = false;
    session.stream = null;
    sendToClient(activeClient, { type: 'run_status', conversationId: session.conversationId, isWorking: false });

    if (session.pendingMessages.length > 0) {
      const next = [...session.pendingMessages];
      session.pendingMessages = [];
      startSessionRun(session, next);
      return;
    }

    touchIdle(session);
  }
}

function handleAgentMessage(session: ConversationSession, message: any): void {
  const msgType = message.type === 'system' ? `system/${message.subtype}` : message.type;
  log.debug(`[agent] ${session.conversationId} message=${msgType}`);

  if (message.type === 'assistant' && message.uuid) {
    session.lastAssistantUuid = message.uuid;
  }

  if (message.type === 'system' && message.subtype === 'init') {
    session.sessionId = message.session_id;
  }

  if (message.type === 'system' && message.subtype === 'task_notification') {
    const summary = message.summary ? ` (${message.summary})` : '';
    log.debug(`task_notification: ${message.status}${summary}`);
    touchIdle(session);
    return;
  }

  if (message.type === 'stream_event') {
    const event = message.event;

    // New message starting — complete any pending non-MCP tool calls from the previous turn.
    // A new message_start means the SDK finished executing tools and is streaming the next response.
    if (event?.type === 'message_start') {
      flushPendingToolCompletions(session);
      session.toolUseByIndex.clear();
      touchIdle(session);
      return;
    }

    // Tool use content block starting
    if (event?.type === 'content_block_start' && event.content_block?.type === 'tool_use') {
      const index = event.index as number;
      const toolUseId = event.content_block.id as string;
      const toolName = event.content_block.name as string;
      session.toolUseByIndex.set(index, { id: toolUseId, name: toolName, inputChunks: [] });

      // MCP-bridged tools emit their own tool_use_start via the MCP bridge — skip them here
      // to avoid duplicate entries in the UI.
      if (!toolName.startsWith('mcp__')) {
        sendToClient(activeClient, {
          type: 'tool_use_start',
          conversationId: session.conversationId,
          toolUseId,
          toolName,
          inputSummary: toolName,
        });
        session.pendingToolCompletions.set(toolUseId, toolName);
      }

      touchIdle(session);
      return;
    }

    // Accumulate input JSON for tool uses
    if (event?.type === 'content_block_delta' && event.delta?.type === 'input_json_delta') {
      const tracked = session.toolUseByIndex.get(event.index as number);
      if (tracked) {
        tracked.inputChunks.push(event.delta.partial_json);
        touchIdle(session);
      }
      return;
    }

    // Content block finished — update tool input summary with parsed input
    if (event?.type === 'content_block_stop') {
      const tracked = session.toolUseByIndex.get(event.index as number);
      if (tracked && !tracked.name.startsWith('mcp__') && tracked.inputChunks.length > 0) {
        try {
          const fullInput = JSON.parse(tracked.inputChunks.join(''));
          // Update the existing tool call entry on the Swift side via completeToolCall.
          // The Swift side's addToolCall uses toolUseId to identify entries, so re-sending
          // tool_use_start would create a duplicate. Instead, we just log the parsed input.
          log.debug(`tool input for ${tracked.name}: ${summarizeToolInput(tracked.name, fullInput)}`);
        } catch {
          // Input parsing failed — keep the tool name as summary
        }
      }
      if (tracked) {
        session.toolUseByIndex.delete(event.index as number);
      }
      return;
    }

    // Text delta — stream to UI
    if (event?.type === 'content_block_delta' && event.delta?.type === 'text_delta' && event.delta.text) {
      sendToClient(activeClient, {
        type: 'stream_chunk',
        conversationId: session.conversationId,
        content: event.delta.text,
      });
      touchIdle(session);
    }
    return;
  }

  if (message.type === 'result') {
    flushPendingToolCompletions(session);
    session.toolUseByIndex.clear();

    const textResult = typeof message.result === 'string'
      ? message.result
      : message.result != null
        ? JSON.stringify(message.result)
        : '';
    if (textResult.trim().length > 0) {
      // Don't send to Swift client — text was already streamed via stream_event chunks.
      forwardToTelegramIfNeeded(session.conversationId, textResult);
      touchIdle(session);
    }
  }
}

/**
 * Mark all pending non-MCP tool calls as complete. Called when a new assistant
 * turn starts (meaning the SDK finished executing the previous turn's tools)
 * or when the conversation result arrives.
 */
function flushPendingToolCompletions(session: ConversationSession): void {
  for (const [toolUseId, toolName] of session.pendingToolCompletions) {
    sendToClient(activeClient, {
      type: 'tool_use_complete',
      conversationId: session.conversationId,
      toolUseId,
      toolName,
      resultPreview: 'Done',
    });
  }
  session.pendingToolCompletions.clear();
}

function buildFluxSystemPrompt(): string {
  let prompt = `You are Flux, a macOS AI desktop copilot. Your role is to help users accomplish tasks on their Mac by reading their screen when necessary and taking actions on their behalf.

You have access to the following tools:

**Screen Context Tools** (use ONLY when the user explicitly asks about what is on their screen, needs information about visible windows/UI elements, or when visual information is required to complete their request):
- mcp__flux__read_visible_windows: Reads text content from multiple visible windows
- mcp__flux__read_ax_tree: Reads accessibility tree text from the frontmost window
- mcp__flux__capture_screen: Captures a visual screenshot of the screen
- mcp__flux__read_selected_text: Reads currently selected text
- mcp__flux__read_clipboard_history: Reads recent clipboard history (last 10 copied items with source app and timestamp)

**Session Context Tools** (use these to understand what the user was recently doing across their desktop):
- mcp__flux__read_session_history: Read which apps/windows the user recently visited (with timestamps)
- mcp__flux__get_session_context_summary: Get a human-readable text summary of recent app activity

**Action Tools** (use these to perform tasks on behalf of the user):
- mcp__flux__execute_applescript: Execute AppleScript commands
- mcp__flux__run_shell_command: Run shell commands
- mcp__flux__send_slack_message: Send messages via Slack
- mcp__flux__send_discord_message: Send messages via Discord
- mcp__flux__send_telegram_message: Send messages via Telegram

**GitHub / CI Tools**:
- mcp__flux__check_github_status: Check GitHub CI/CD status and notifications via gh CLI. Returns recent CI failures and notifications. Pass optional repo (owner/repo) to filter.
- mcp__flux__manage_github_repos: Manage the list of watched GitHub repos (list/add/remove). Use this when the user asks to watch or stop watching a repo.

**Delegation Tool**:
- TeamCreate: For complex tasks requiring research, planning, or multi-step workflows, spin up a small agent team to delegate work

Important guidelines:
- Do NOT use screen context tools unless the user's request specifically requires information about what's currently on their screen or visible in their windows
- If the user has attached a screenshot or image to their message, use that image instead of capturing a new screenshot
- Be concise and helpful in your responses
- Ask clarifying questions when the user's request is ambiguous or lacks necessary details
- When you use memory skills to remember information about the user, apply them silently without announcing that you're doing so
- For straightforward requests that don't require screen information, proceed directly with the appropriate action`;

  // Inject live app context so the agent knows what the user is working in.
  // NOTE: This prompt is built once at session start. If the user switches apps
  // mid-conversation, the context won't update until the next query session.
  if (lastActiveApp) {
    prompt += `\n\nThe user is currently using: ${lastActiveApp.appName} (${lastActiveApp.bundleId}).`;
    prompt += '\nTailor your responses to the context of this application when relevant.';
    if (lastActiveApp.appInstruction) {
      prompt += `\n\nApp-specific instructions:\n${lastActiveApp.appInstruction}`;
    }
  }

  return prompt;
}

function getSession(conversationId: string): ConversationSession {
  let session = sessions.get(conversationId);
  if (!session) {
    session = {
      conversationId,
      stream: null,
      isRunning: false,
      pendingMessages: [],
      toolUseByIndex: new Map(),
      pendingToolCompletions: new Map(),
    };
    sessions.set(conversationId, session);
  }
  return session;
}

function touchIdle(session: ConversationSession): void {
  if (sessions.get(session.conversationId) !== session) return;

  clearIdle(session);
  session.idleTimer = setTimeout(() => {
    if (sessions.get(session.conversationId) !== session) return;

    session.idleTimer = undefined;
    if (session.isRunning) {
      if (session.stream && !session.stream.isDone()) {
        session.stream.end();
      }
      touchIdle(session);
      return;
    }
    evictSession(session.conversationId);
  }, AGENT_IDLE_TIMEOUT_MS);
}

function clearIdle(session: ConversationSession): void {
  if (session.idleTimer) {
    clearTimeout(session.idleTimer);
    session.idleTimer = undefined;
  }
}

function evictSession(conversationId: string, reason = 'Session expired due to inactivity.'): void {
  const session = sessions.get(conversationId);
  if (!session) return;

  clearIdle(session);

  if (session.stream && !session.stream.isDone()) {
    session.stream.end();
  }
  session.stream = null;
  session.pendingMessages = [];
  session.toolUseByIndex.clear();
  flushPendingToolCompletions(session);
  clearPendingToolCallsForConversation(conversationId, reason);

  sessions.delete(conversationId);
  telegramConversationMeta.delete(conversationId);

  for (const [key, value] of telegramSessionMap.entries()) {
    if (value === conversationId) {
      telegramSessionMap.delete(key);
    }
  }
}

function resolveMcpServerConfig(conversationId: string, runId: string): { command: string; args: string[]; env: Record<string, string> } {
  const jsPath = path.resolve(__dirname, 'mcp', 'flux-stdio.js');
  const tsPath = path.resolve(__dirname, 'mcp', 'flux-stdio.ts');
  let command = process.execPath;
  let args: string[] = [];

  if (fs.existsSync(jsPath)) {
    args = [jsPath];
  } else {
    const tsxPath = path.resolve(__dirname, '../node_modules/.bin/tsx');
    if (!fs.existsSync(tsxPath) || !fs.existsSync(tsPath)) {
      throw new Error('Unable to locate flux MCP server entrypoint.');
    }
    command = tsxPath;
    args = [tsPath];
  }

  const env: Record<string, string> = {
    ...Object.fromEntries(Object.entries(process.env).filter(([, value]) => typeof value === 'string')),
    FLUX_MCP_BRIDGE_URL: mcpBridgeUrl,
    FLUX_CONVERSATION_ID: conversationId,
    FLUX_RUN_ID: runId,
  };

  for (const [serverId, token] of mcpAuthTokens.entries()) {
    if (!token) continue;
    env[`MCP_${serverId.toUpperCase()}_TOKEN`] = token;
  }

  return { command, args, env };
}

function startMcpBridge(port: number): void {
  mcpBridgeUrl = `ws://127.0.0.1:${port}`;
  const wss = new WebSocketServer({ port, host: '127.0.0.1' });

  wss.on('connection', (ws) => {
    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString()) as BridgeMessage;
        handleMcpBridgeMessage(ws, message);
      } catch (error) {
        log.error('Failed to parse MCP bridge message:', error);
      }
    });

    ws.on('close', () => {
      cleanupBridgeSocket(ws);
    });
  });

  log.info(`MCP bridge listening on ${mcpBridgeUrl}`);
}

interface BridgeHello {
  type: 'hello';
  conversationId: string;
  runId: string;
}

interface BridgeToolRequest {
  type: 'tool_request';
  conversationId: string;
  runId: string;
  toolUseId: string;
  toolName: string;
  input: Record<string, unknown>;
}

interface BridgeToolResponse {
  type: 'tool_response';
  toolUseId: string;
  result: string;
  isError?: boolean;
}

type BridgeMessage = BridgeHello | BridgeToolRequest;

interface PendingToolCall {
  ws: WebSocket;
  conversationId: string;
  toolName: string;
  timeout: NodeJS.Timeout;
}

const pendingToolCalls = new Map<string, PendingToolCall>();

function handleMcpBridgeMessage(ws: WebSocket, message: BridgeMessage): void {
  if (message.type === 'hello') {
    return;
  }

  if (message.type !== 'tool_request') return;

  if (!activeClient || activeClient.readyState !== WebSocket.OPEN) {
    sendBridgeResponse(ws, {
      type: 'tool_response',
      toolUseId: message.toolUseId,
      result: 'Flux is offline. Open the app to reconnect.',
      isError: true,
    });
    return;
  }

  const timeout = setTimeout(() => {
    pendingToolCalls.delete(message.toolUseId);
    sendBridgeResponse(ws, {
      type: 'tool_response',
      toolUseId: message.toolUseId,
      result: 'Tool execution timed out',
      isError: true,
    });
    sendToClient(activeClient, {
      type: 'tool_use_complete',
      conversationId: message.conversationId,
      toolUseId: message.toolUseId,
      toolName: message.toolName,
      resultPreview: 'Timed out',
    });
  }, TOOL_TIMEOUT_MS);

  pendingToolCalls.set(message.toolUseId, {
    ws,
    conversationId: message.conversationId,
    toolName: message.toolName,
    timeout,
  });

  const session = sessions.get(message.conversationId);
  if (session) {
    touchIdle(session);
  }

  sendToClient(activeClient, {
    type: 'tool_request',
    conversationId: message.conversationId,
    toolUseId: message.toolUseId,
    toolName: message.toolName,
    input: message.input,
  });

  sendToClient(activeClient, {
    type: 'tool_use_start',
    conversationId: message.conversationId,
    toolUseId: message.toolUseId,
    toolName: message.toolName,
    inputSummary: summarizeToolInput(message.toolName, message.input),
  });
}

function handleToolResult(message: ToolResultMessage): void {
  const pending = pendingToolCalls.get(message.toolUseId);
  if (!pending) {
    log.warn(`No pending tool result for toolUseId=${message.toolUseId}`);
    return;
  }

  pendingToolCalls.delete(message.toolUseId);
  clearTimeout(pending.timeout);

  sendBridgeResponse(pending.ws, {
    type: 'tool_response',
    toolUseId: message.toolUseId,
    result: message.toolResult,
  });

  sendToClient(activeClient, {
    type: 'tool_use_complete',
    conversationId: message.conversationId,
    toolUseId: message.toolUseId,
    toolName: message.toolName,
    resultPreview: toolResultPreview(message.toolName, message.toolResult),
  });

  const session = sessions.get(message.conversationId);
  if (session) {
    touchIdle(session);
  }
}

function sendBridgeResponse(ws: WebSocket, message: BridgeToolResponse): void {
  if (ws.readyState !== WebSocket.OPEN) return;
  ws.send(JSON.stringify(message));
}

function cleanupBridgeSocket(ws: WebSocket): void {
  for (const [toolUseId, pending] of pendingToolCalls.entries()) {
    if (pending.ws === ws) {
      clearTimeout(pending.timeout);
      pendingToolCalls.delete(toolUseId);
      sendToClient(activeClient, {
        type: 'tool_use_complete',
        conversationId: pending.conversationId,
        toolUseId,
        toolName: pending.toolName,
        resultPreview: 'Disconnected',
      });
    }
  }
}

function clearPendingToolCallsForConversation(conversationId: string, reason: string): void {
  for (const [toolUseId, pending] of pendingToolCalls.entries()) {
    if (pending.conversationId !== conversationId) continue;

    clearTimeout(pending.timeout);
    sendBridgeResponse(pending.ws, {
      type: 'tool_response',
      toolUseId,
      result: reason,
      isError: true,
    });
    sendToClient(activeClient, {
      type: 'tool_use_complete',
      conversationId,
      toolUseId,
      toolName: pending.toolName,
      resultPreview: reason,
    });
    pendingToolCalls.delete(toolUseId);
  }
}

function flushPendingToolCalls(reason: string): void {
  for (const [toolUseId, pending] of pendingToolCalls.entries()) {
    clearTimeout(pending.timeout);
    sendBridgeResponse(pending.ws, {
      type: 'tool_response',
      toolUseId,
      result: reason,
      isError: true,
    });
    sendToClient(activeClient, {
      type: 'tool_use_complete',
      conversationId: pending.conversationId,
      toolUseId,
      toolName: pending.toolName,
      resultPreview: reason,
    });
    pendingToolCalls.delete(toolUseId);
  }
}

function sendToClient(ws: WebSocket | null, message: OutgoingMessage): void {
  if (!ws || ws.readyState !== WebSocket.OPEN) return;
  ws.send(JSON.stringify(message));
}

async function handleTelegramMessage(chatId: string, threadId: number | undefined, text: string): Promise<void> {
  if (!runtimeApiKey) {
    await telegramBot.sendMessage(
      'No Anthropic API key configured. Open Island Settings and set your API key.',
      chatId,
      threadId,
    );
    return;
  }

  if (!activeClient || activeClient.readyState !== WebSocket.OPEN) {
    await telegramBot.sendMessage('Flux is offline. Open the app to reconnect.', chatId, threadId);
    return;
  }

  const conversationId = getTelegramConversationId(chatId, threadId);
  telegramConversationMeta.set(conversationId, { chatId, threadId });
  enqueueUserMessage(conversationId, text, []);
}

function forwardToTelegramIfNeeded(conversationId: string, content: string): void {
  const meta = telegramConversationMeta.get(conversationId);
  if (!meta) return;
  void telegramBot.sendMessage(content, meta.chatId, meta.threadId);
}

function getTelegramConversationId(chatId: string, threadId?: number): string {
  const key = threadId != null ? `${chatId}:${threadId}` : chatId;
  let conversationId = telegramSessionMap.get(key);
  if (!conversationId) {
    conversationId = crypto.randomUUID();
    telegramSessionMap.set(key, conversationId);
  }
  return conversationId;
}

function toolResultPreview(toolName: string, result: string): string {
  if (toolName === 'capture_screen') {
    const parsed = parseImageToolResult(result);
    if (parsed) {
      const decodedBytes = Buffer.from(parsed.data, 'base64').length;
      return `[image ${parsed.mediaType}, decoded bytes=${decodedBytes}]`;
    }
  }
  return result.substring(0, 200);
}

function parseImageToolResult(raw: string): { mediaType: string; data: string } | null {
  const trimmed = raw.trim();
  const dataUrlMatch = trimmed.match(/^data:(image\/[^;]+);base64,(.+)$/);
  if (dataUrlMatch) {
    return { mediaType: dataUrlMatch[1], data: dataUrlMatch[2] };
  }

  if (trimmed.startsWith('iVBOR')) return { mediaType: 'image/png', data: trimmed };
  if (trimmed.startsWith('/9j/')) return { mediaType: 'image/jpeg', data: trimmed };
  if (trimmed.startsWith('R0lGOD')) return { mediaType: 'image/gif', data: trimmed };
  if (trimmed.startsWith('UklGR')) return { mediaType: 'image/webp', data: trimmed };
  return null;
}

function summarizeToolInput(toolName: string, input: Record<string, unknown>): string {
  const candidates = [
    'path',
    'file',
    'target',
    'command',
    'script',
    'query',
    'url',
    'text',
    'content',
    'id',
    'name',
    'scheduleExpression',
    'schedule',
  ];
  for (const key of candidates) {
    const val = input[key];
    if (typeof val === 'string' && val.length > 0) {
      return val.length > 80 ? val.substring(0, 77) + '...' : val;
    }
  }

  for (const val of Object.values(input)) {
    if (typeof val === 'string' && val.length > 0) {
      return val.length > 80 ? val.substring(0, 77) + '...' : val;
    }
  }

  return toolName;
}
