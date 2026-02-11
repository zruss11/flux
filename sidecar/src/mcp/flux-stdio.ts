import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import WebSocket from 'ws';
import crypto from 'crypto';

import { baseTools } from '../tools/index.js';
import { loadInstalledSkills } from '../skills/loadInstalledSkills.js';
import { McpManager } from './manager.js';
import type { ToolDefinition } from '../tools/types.js';
import { createLogger } from '../logger.js';

const log = createLogger('mcp');

const BRIDGE_URL = process.env.FLUX_MCP_BRIDGE_URL || 'ws://127.0.0.1:7848';
const conversationId = process.env.FLUX_CONVERSATION_ID || '';
const runId = process.env.FLUX_RUN_ID || '';

if (!conversationId) {
  log.error('Missing FLUX_CONVERSATION_ID env var');
  process.exit(1);
}

const passthroughSchema = z.record(z.string(), z.any());

function jsonSchemaToZod(schema: ToolDefinition['input_schema']): z.ZodType {
  const properties = schema.properties ?? {};
  const requiredSet = new Set(schema.required ?? []);

  if (Object.keys(properties).length === 0) {
    return passthroughSchema;
  }

  const shape: Record<string, z.ZodType> = {};
  for (const [key, prop] of Object.entries(properties)) {
    const p = prop as Record<string, unknown>;
    let field: z.ZodType;

    switch (p.type) {
      case 'string':
        if (Array.isArray(p.enum) && p.enum.length > 0) {
          field = z.enum(p.enum as [string, ...string[]]);
        } else {
          field = z.string();
        }
        break;
      case 'number':
      case 'integer':
        field = z.number();
        break;
      case 'boolean':
        field = z.boolean();
        break;
      case 'array':
        field = z.array(z.any());
        break;
      case 'object':
        field = z.record(z.string(), z.any());
        break;
      default:
        field = z.any();
    }

    if (typeof p.description === 'string') {
      field = field.describe(p.description);
    }

    if (!requiredSet.has(key)) {
      field = field.optional();
    }

    shape[key] = field;
  }

  return z.object(shape).passthrough();
}

const mcp = new McpManager();
const installedSkills = await loadInstalledSkills();
mcp.registerFromSkills(installedSkills);

const baseToolNames = new Set(baseTools.map((tool) => tool.name));

const helperTools: ToolDefinition[] = [
  {
    name: 'linear__setup',
    description: 'Explain how to configure Linear MCP auth for Flux sidecar.',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'linear__mcp_list_tools',
    description: 'List available Linear MCP tools (requires Linear MCP auth).',
    input_schema: { type: 'object', properties: {} },
  },
];

async function loadRemoteTools(): Promise<ToolDefinition[]> {
  const tools: ToolDefinition[] = [];
  for (const serverId of mcp.listServerIds()) {
    if (!mcp.hasAuthToken(serverId)) continue;
    try {
      const serverTools = await mcp.getAnthropicTools(serverId);
      tools.push(...serverTools);
    } catch {
      // Ignore failures; tools can still be used once auth is fixed.
    }
  }
  return tools;
}

const remoteTools = await loadRemoteTools();
const allTools: ToolDefinition[] = [...baseTools, ...helperTools, ...remoteTools];

class BridgeClient {
  private socket: WebSocket | null = null;
  private connectPromise: Promise<void> | null = null;
  private pending = new Map<
    string,
    { resolve: (value: ToolBridgeResponse) => void; reject: (err: Error) => void; timeout: NodeJS.Timeout }
  >();
  private connected = false;

  async connect(): Promise<void> {
    if (this.connected && this.socket?.readyState === WebSocket.OPEN) return;
    if (this.connectPromise) return this.connectPromise;

    this.connectPromise = this.doConnect();
    return this.connectPromise;
  }

  private async doConnect(): Promise<void> {
    const socket = new WebSocket(BRIDGE_URL);
    this.socket = socket;

    try {
      await new Promise<void>((resolve, reject) => {
        const onOpen = () => {
          this.connected = true;
          socket.send(JSON.stringify({ type: 'hello', conversationId, runId }));
          resolve();
        };

        const onError = (err: Error) => {
          reject(err);
        };

        socket.once('open', onOpen);
        socket.once('error', onError);
      });

      socket.on('message', (data) => this.handleMessage(data.toString()));
      socket.on('close', () => this.handleClose(socket));
      socket.on('error', () => this.handleClose(socket));
    } catch (err) {
      if (this.socket === socket) {
        this.socket = null;
      }
      this.connected = false;
      throw err;
    } finally {
      this.connectPromise = null;
    }
  }

  private handleMessage(raw: string): void {
    try {
      const message = JSON.parse(raw) as ToolBridgeResponse;
      if (message.type !== 'tool_response') return;
      const pending = this.pending.get(message.toolUseId);
      if (!pending) return;
      clearTimeout(pending.timeout);
      this.pending.delete(message.toolUseId);
      pending.resolve(message);
    } catch {
      // Ignore malformed messages
    }
  }

  private handleClose(socket: WebSocket): void {
    if (this.socket && this.socket !== socket) return;

    this.connected = false;
    this.socket = null;
    this.connectPromise = null;

    for (const pending of this.pending.values()) {
      clearTimeout(pending.timeout);
      pending.reject(new Error('Bridge connection closed'));
    }
    this.pending.clear();
  }

  async requestTool(toolName: string, input: Record<string, unknown>): Promise<ToolBridgeResponse> {
    try {
      await this.connect();
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Bridge connection failed';
      return { type: 'tool_response', toolUseId: 'unknown', result: message, isError: true };
    }

    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      return { type: 'tool_response', toolUseId: 'unknown', result: 'Bridge not connected', isError: true };
    }

    const toolUseId = `toolu_${crypto.randomBytes(8).toString('hex')}`;

    return new Promise<ToolBridgeResponse>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(toolUseId);
        resolve({
          type: 'tool_response',
          toolUseId,
          result: 'Tool execution timed out',
          isError: true,
        });
      }, 60000);

      this.pending.set(toolUseId, { resolve, reject, timeout });

      this.socket?.send(
        JSON.stringify({
          type: 'tool_request',
          conversationId,
          runId,
          toolUseId,
          toolName,
          input,
        }),
      );
    });
  }
}

interface ToolBridgeResponse {
  type: 'tool_response';
  toolUseId: string;
  result: string;
  isError?: boolean;
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

function toolResultToContent(toolName: string, result: string): any[] {
  if (toolName === 'capture_screen') {
    const parsed = parseImageToolResult(result);
    if (parsed) {
      return [
        {
          type: 'image',
          data: parsed.data,
          mimeType: parsed.mediaType,
        },
      ];
    }
  }
  return [{ type: 'text', text: result }];
}

async function handleToolCall(toolName: string, input: Record<string, unknown>): Promise<any> {
  if (toolName === 'linear__setup') {
    const text = [
      'Linear tools are available via the Linear MCP server, but require an access token.',
      '',
      'Set one of these environment variables for the sidecar process:',
      '- `MCP_LINEAR_TOKEN` (preferred)',
      '- `LINEAR_MCP_TOKEN`',
      '- `LINEAR_TOKEN`',
      '',
      'Then restart the sidecar so it can connect and expose `linear__*` tools.',
    ].join('\n');
    return { content: [{ type: 'text', text }] };
  }

  if (toolName === 'linear__mcp_list_tools') {
    try {
      const tools = await mcp.listTools('linear');
      const payload = tools.map((t) => ({ name: t.name, description: t.description ?? null }));
      return { content: [{ type: 'text', text: JSON.stringify(payload, null, 2) }] };
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      const hint = mcp.getLastError('linear');
      const text = `Failed to list Linear MCP tools: ${msg}${hint ? `\nLast error: ${hint}` : ''}`;
      return { content: [{ type: 'text', text }], isError: true };
    }
  }

  if (baseToolNames.has(toolName)) {
    const bridge = bridgeClient;
    const response = await bridge.requestTool(toolName, input ?? {});
    return {
      content: toolResultToContent(toolName, response.result ?? ''),
      isError: response.isError ?? false,
    };
  }

  const parsed = mcp.parseAnthropicToolName(toolName);
  if (parsed) {
    try {
      const res = await mcp.callTool(parsed.serverId, parsed.mcpToolName, input ?? {});
      const text = JSON.stringify(res, null, 2);
      return { content: [{ type: 'text', text }], isError: Boolean((res as any).isError) };
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      const hint = mcp.getLastError(parsed.serverId);
      const text = `MCP tool call failed (${parsed.serverId}/${parsed.mcpToolName}): ${msg}${hint ? `\nLast error: ${hint}` : ''}`;
      return { content: [{ type: 'text', text }], isError: true };
    }
  }

  return { content: [{ type: 'text', text: `Unknown tool: ${toolName}` }], isError: true };
}

const bridgeClient = new BridgeClient();

const server = new McpServer({
  name: 'flux',
  version: '1.0.0',
});

for (const tool of allTools) {
  const inputSchema = tool.input_schema ? jsonSchemaToZod(tool.input_schema) : passthroughSchema;
  server.registerTool(
    tool.name,
    {
      description: tool.description ?? tool.name,
      inputSchema,
    },
    async (args) => handleToolCall(tool.name, args as Record<string, unknown>),
  );
}

const transport = new StdioServerTransport();
await server.connect(transport);
