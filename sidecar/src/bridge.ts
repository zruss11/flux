import { WebSocketServer, WebSocket } from 'ws';
import crypto from 'crypto';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { Agent, type AgentTool, type AgentMessage } from '@mariozechner/pi-agent-core';
import { getModel } from '@mariozechner/pi-ai';
import { Type, type TSchema } from '@sinclair/typebox';
import { createTelegramBot } from './telegram/bot.js';
import { createLogger } from './logger.js';
import { baseTools } from './tools/index.js';
import type { ToolDefinition } from './tools/types.js';
import { loadInstalledSkills } from './skills/loadInstalledSkills.js';
import { McpManager } from './mcp/manager.js';

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

interface ForkConversationMessage {
  type: 'fork_conversation';
  sourceConversationId: string;
  newConversationId: string;
}

interface ForkConversationResultMessage {
  type: 'fork_conversation_result';
  conversationId: string;
  success: boolean;
  reason?: string;
}

interface PermissionResponseMessage {
  type: 'permission_response';
  requestId: string;
  behavior: 'allow' | 'deny';
  message?: string;
  answers?: Record<string, string>;
}

interface HelloMessage {
  type: 'hello';
  token?: string;
}

type IncomingMessage =
  | HelloMessage
  | ChatMessage
  | ToolResultMessage
  | SetApiKeyMessage
  | McpAuthMessage
  | SetTelegramConfigMessage
  | ActiveAppUpdateMessage
  | ForkConversationMessage
  | PermissionResponseMessage;

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

interface SessionInfoMessage {
  type: 'session_info';
  conversationId: string;
  sessionId: string;
}

interface PermissionRequestMessage {
  type: 'permission_request';
  conversationId: string;
  requestId: string;
  toolName: string;
  input: Record<string, unknown>;
}

interface AskUserQuestionMessage {
  type: 'ask_user_question';
  conversationId: string;
  requestId: string;
  questions: Array<{
    question: string;
    options: Array<{ label: string; description?: string }>;
    multiSelect?: boolean;
  }>;
}

type OutgoingMessage =
  | AssistantMessage
  | ToolRequestMessage
  | ToolUseStartMessage
  | ToolUseCompleteMessage
  | StreamChunkMessage
  | RunStatusMessage
  | SessionInfoMessage
  | ForkConversationResultMessage
  | PermissionRequestMessage
  | AskUserQuestionMessage;

interface SDKUserMessage {
  type: 'user';
  message: { role: 'user'; content: string | SDKUserContentBlock[] };
  parent_tool_use_id: string | null;
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

interface AgentAssistantMessage {
  type: 'assistant';
  uuid?: string;
  [key: string]: unknown;
}

interface AgentSystemMessage {
  type: 'system';
  subtype?: string;
  session_id?: string;
  status?: string;
  summary?: string;
  [key: string]: unknown;
}

interface AgentStreamEvent {
  type?: string;
  index?: number;
  content_block?: {
    type?: string;
    id?: string;
    name?: string;
  };
  delta?: {
    type?: string;
    partial_json?: string;
    text?: string;
  };
  [key: string]: unknown;
}

interface AgentStreamEventMessage {
  type: 'stream_event';
  event?: AgentStreamEvent;
  [key: string]: unknown;
}

interface AgentResultMessage {
  type: 'result';
  result?: unknown;
  [key: string]: unknown;
}

interface AgentUserMessage {
  type: 'user';
  parent_tool_use_id?: string | null;
  [key: string]: unknown;
}

interface AgentToolProgressMessage {
  type: 'tool_progress';
  tool_use_id?: string;
  tool_name?: string;
  [key: string]: unknown;
}

interface AgentToolUseSummaryMessage {
  type: 'tool_use_summary';
  summary?: string;
  [key: string]: unknown;
}

interface AgentAuthStatusMessage {
  type: 'auth_status';
  [key: string]: unknown;
}

type LegacySdkMessage = AgentAssistantMessage | AgentSystemMessage | AgentStreamEventMessage | AgentResultMessage | AgentUserMessage | AgentToolProgressMessage | AgentToolUseSummaryMessage | AgentAuthStatusMessage;

type UnknownRecord = Record<string, unknown>;

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === 'object' && value !== null;
}

function isAgentMessage(value: unknown): value is LegacySdkMessage {
  if (!isRecord(value)) return false;

  const message = value;
  return (
    message.type === 'assistant'
    || message.type === 'system'
    || message.type === 'stream_event'
    || message.type === 'result'
    || message.type === 'user'
    || message.type === 'tool_progress'
    || message.type === 'tool_use_summary'
    || message.type === 'auth_status'
  );
}

function isString(value: unknown): value is string {
  return typeof value === 'string';
}

function isNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function isChatImagePayload(value: unknown): value is ChatImagePayload {
  return isRecord(value)
    && isString(value.fileName)
    && isString(value.mediaType)
    && isString(value.data);
}

function isChatImageList(value: unknown): value is ChatImagePayload[] {
  return Array.isArray(value) && value.every(isChatImagePayload);
}

function isIncomingMessage(value: unknown): value is IncomingMessage {
  if (!isRecord(value)) return false;

  if (value.type === 'hello') {
    return value.token === undefined || isString(value.token);
  }

  if (value.type === 'chat') { 
    return isString(value.conversationId)
      && isString(value.content)
      && (value.images === undefined || isChatImageList(value.images));
  }

  if (value.type === 'tool_result') {
    return isString(value.conversationId)
      && isString(value.toolUseId)
      && isString(value.toolName)
      && isString(value.toolResult);
  }

  if (value.type === 'set_api_key') {
    return isString(value.apiKey);
  }

  if (value.type === 'mcp_auth') {
    return isString(value.serverId) && isString(value.token);
  }

  if (value.type === 'set_telegram_config') {
    return isString(value.botToken) && isString(value.defaultChatId);
  }

  if (value.type === 'active_app_update') {
    return isString(value.appName)
      && isString(value.bundleId)
      && isNumber(value.pid)
      && (value.appInstruction === undefined || isString(value.appInstruction));
  }

  if (value.type === 'fork_conversation') {
    return isString(value.sourceConversationId) && isString(value.newConversationId);
  }

  if (value.type === 'permission_response') {
    return isString(value.requestId) && isString(value.behavior);
  }

  return false;
}

function parseIncomingMessage(payload: string): IncomingMessage | null {
  let raw: unknown;
  try {
    raw = JSON.parse(payload);
  } catch {
    return null;
  }

  return isIncomingMessage(raw) ? raw : null;
}

function isBridgeMessage(value: unknown): value is BridgeMessage {
  if (!isRecord(value)) return false;

  if (value.type === 'hello') {
    return isString(value.conversationId) && isString(value.runId);
  }

  if (value.type === 'tool_request') {
    return isString(value.conversationId)
      && isString(value.runId)
      && isString(value.toolUseId)
      && isString(value.toolName)
      && isRecord(value.input);
  }

  return false;
}

function parseBridgeMessage(payload: string): BridgeMessage | null {
  let raw: unknown;
  try {
    raw = JSON.parse(payload);
  } catch {
    return null;
  }

  return isBridgeMessage(raw) ? raw : null;
}

function parseEventTextDelta(value: AgentStreamEvent): string | null {
  return isString(value.delta?.text) ? value.delta.text : null;
}

function parseEventInputJsonDelta(value: AgentStreamEvent): string | null {
  return isString(value.delta?.partial_json) ? value.delta.partial_json : null;
}

function parseStreamBlockId(value: AgentStreamEvent): string | null {
  return isRecord(value.content_block) && isString(value.content_block.id) ? value.content_block.id : null;
}

function parseStreamBlockName(value: AgentStreamEvent): string | null {
  return isRecord(value.content_block) && isString(value.content_block.name) ? value.content_block.name : null;
}

function parseEventIndex(value: AgentStreamEvent): number | null {
  return isNumber(value.index) ? value.index : null;
}

const log = createLogger('bridge');

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function parsePositiveIntEnv(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return parsed;
}

function parseSettingSources(value: string | undefined): Array<'user' | 'project' | 'local'> {
  const raw = value?.trim();
  if (!raw) return ['project'];
  const valid = new Set(['user', 'project', 'local']);
  const parsed = raw
    .split(',')
    .map((item) => item.trim())
    .filter((item): item is 'user' | 'project' | 'local' => valid.has(item));
  return parsed.length > 0 ? parsed : ['project'];
}

type ThinkingLevel = 'off' | 'minimal' | 'low' | 'medium' | 'high' | 'xhigh';

function parseAgentModelSpec(spec: string): { provider: string; model: string } {
  const trimmed = spec.trim();
  if (!trimmed) return { provider: 'anthropic', model: 'claude-sonnet-4-20250514' };
  const match = trimmed.match(/^([^:\/]+)[:\/](.+)$/);
  if (match) return { provider: match[1], model: match[2] };

  const fallbackProvider = (process.env.FLUX_AGENT_PROVIDER || 'anthropic').trim() || 'anthropic';
  return { provider: fallbackProvider, model: trimmed };
}

const AGENT_MODEL_SPEC = process.env.FLUX_AGENT_MODEL || 'anthropic:claude-sonnet-4-20250514';
const { provider: AGENT_PROVIDER, model: AGENT_MODEL } = parseAgentModelSpec(AGENT_MODEL_SPEC);
const AGENT_THINKING_LEVEL = ((process.env.FLUX_AGENT_THINKING_LEVEL || 'low').trim() || 'low') as ThinkingLevel;
const AGENT_SETTING_SOURCES = parseSettingSources(process.env.FLUX_AGENT_SETTING_SOURCES);
const AGENT_IDLE_TIMEOUT_MS = parsePositiveIntEnv(process.env.FLUX_AGENT_IDLE_TIMEOUT_MS, 900_000);
const AGENT_WARMUP_ENABLED = process.env.FLUX_AGENT_WARMUP_ENABLED !== '0';
const AGENT_WARMUP_MAX_ATTEMPTS = parsePositiveIntEnv(process.env.FLUX_AGENT_WARMUP_MAX_ATTEMPTS, 2);
const TOOL_TIMEOUT_MS = 60_000;
const ALLOWED_TOOLS = [
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
  'AskUserQuestion',
  'mcp__flux__*',
];

process.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = '1';

const sessions = new Map<string, ConversationSession>();
const telegramSessionMap = new Map<string, string>();
const telegramConversationMeta = new Map<string, { chatId: string; threadId?: number }>();
const mcpAuthTokens = new Map<string, string>();
const pendingPermissions = new Map<string, {
  resolve: (result: { behavior: 'allow'; updatedInput: Record<string, unknown> } | { behavior: 'deny'; message: string }) => void;
  conversationId: string;
  toolName: string;
  input: Record<string, unknown>;
  timeout: NodeJS.Timeout;
}>();

let activeClient: WebSocket | null = null;
let runtimeApiKey: string | null = process.env.ANTHROPIC_API_KEY ?? null;

const BRIDGE_AUTH_TOKEN = (process.env.FLUX_BRIDGE_TOKEN ?? '').trim();
const REQUIRE_BRIDGE_AUTH = BRIDGE_AUTH_TOKEN.length > 0;
let mcpBridgeUrl = '';
let mainWss: WebSocketServer | null = null;
let mcpBridgeWss: WebSocketServer | null = null;
let agentWarmupPromise: Promise<void> | null = null;
let agentWarmupAttempts = 0;
let agentWarmupComplete = false;

/** Currently active (frontmost) app, updated live by the Swift client. */
let lastActiveApp: { appName: string; bundleId: string; pid: number; appInstruction?: string } | null = null;

function sanitizeAppInstruction(instruction: string | undefined): string | undefined {
  if (!instruction) return undefined;
  const trimmed = instruction.trim();
  if (trimmed.length === 0) return undefined;
  const maxLen = 2_000;
  const clipped = trimmed.length > maxLen ? `${trimmed.slice(0, maxLen)}…` : trimmed;
  return clipped.replace(/\r\n|\r/g, '\n');
}

// Optimization: Combine multiple dangerous command patterns into a single regex
// to avoid O(N*M) matching (where N=inputs, M=patterns).
const DANGEROUS_COMMAND_PATTERN = new RegExp(
  [
    String.raw`\brm\b`,
    String.raw`\bsudo\s+rm\b`,
    String.raw`\bgit\s+reset\s+--hard\b`,
    String.raw`\bgit\s+clean\s+-f(?:d|x|dx|fd|fdx)?\b`,
    String.raw`\bgit\s+checkout\s+--\b`,
    String.raw`\bgit\s+branch\s+-D\b`,
    String.raw`\bgit\s+push\s+--force(?!-with-lease)\b`,
    String.raw`\bgit\s+rebase\s+--abort\b`,
    String.raw`\bgit\s+rebase\s+--skip\b`,
    String.raw`\bgit\s+stash\s+(?:drop|clear)\b`,
  ].join('|'),
  'i'
);

const COMMAND_LIKE_KEYS = ['command', 'cmd', 'script', 'shell', 'bash', 'args'];

export function collectCommandLikeInputValues(input: Record<string, unknown>): string[] {
  const values: string[] = [];
  for (const key of COMMAND_LIKE_KEYS) {
    const value = input[key];
    if (typeof value === 'string' && value.trim().length > 0) {
      values.push(value);
      continue;
    }
    if (Array.isArray(value)) {
      const combined = value.filter((item): item is string => typeof item === 'string').join(' ');
      if (combined.trim().length > 0) values.push(combined);
    }
  }
  return values;
}

export function requiresApproval(toolName: string, input: Record<string, unknown>): boolean {
  const lowerToolName = toolName.toLowerCase();
  const isCommandExecutionTool =
    lowerToolName.includes('shell') ||
    lowerToolName.includes('bash') ||
    lowerToolName.includes('terminal') ||
    lowerToolName.includes('applescript') ||
    lowerToolName.includes('command');

  const commandCandidates = collectCommandLikeInputValues(input);
  if (!isCommandExecutionTool && commandCandidates.length === 0) {
    return false;
  }

  return commandCandidates.some((command) => DANGEROUS_COMMAND_PATTERN.test(command));
}

interface ConversationSession {
  conversationId: string;
  agent: Agent;
  isRunning: boolean;
  idleTimer?: NodeJS.Timeout;
  pendingMessages: QueuedUserMessage[];
}

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

const mcpManager = new McpManager();
let cachedRemoteTools: ToolDefinition[] = [];
let mcpInitPromise: Promise<void> | null = null;

async function ensureMcpInitialized(): Promise<void> {
  if (mcpInitPromise) return mcpInitPromise;
  mcpInitPromise = (async () => {
    const installedSkills = await loadInstalledSkills();
    mcpManager.registerFromSkills(installedSkills);
    cachedRemoteTools = await loadRemoteTools();
  })().catch((err) => {
    const msg = err instanceof Error ? err.message : String(err);
    log.warn(`MCP init failed: ${msg}`);
  });
  return mcpInitPromise;
}

async function loadRemoteTools(): Promise<ToolDefinition[]> {
  const tools: ToolDefinition[] = [];
  for (const serverId of mcpManager.listServerIds()) {
    if (!mcpManager.hasAuthToken(serverId)) continue;
    try {
      const serverTools = await mcpManager.getAnthropicTools(serverId);
      tools.push(...serverTools);
    } catch {
      // Ignore failures; tools can still be used once auth is fixed.
    }
  }
  return tools;
}

function stringEnum(values: [string, ...string[]], opts?: Record<string, unknown>): TSchema {
  return Type.Unsafe<string>({ type: 'string', enum: values, ...(opts ?? {}) });
}

function jsonSchemaToTypeBox(schema: ToolDefinition['input_schema']): TSchema {
  const properties = schema.properties ?? {};
  const requiredSet = new Set(schema.required ?? []);

  if (Object.keys(properties).length === 0) {
    return Type.Object({}, { additionalProperties: true });
  }

  const shape: Record<string, TSchema> = {};
  for (const [key, rawProp] of Object.entries(properties)) {
    const prop = rawProp as Record<string, unknown>;
    const type = prop.type;
    const desc = typeof prop.description === 'string' ? prop.description : undefined;
    const opts = desc ? { description: desc } : undefined;

    let field: TSchema;
    switch (type) {
      case 'string': {
        const values = Array.isArray(prop.enum) ? (prop.enum as unknown[]) : null;
        const strValues = values?.every((v) => typeof v === 'string') ? (values as string[]) : null;
        field = (strValues && strValues.length > 0)
          ? stringEnum(strValues as [string, ...string[]], opts)
          : Type.String(opts);
        break;
      }
      case 'number':
      case 'integer':
        field = Type.Number(opts);
        break;
      case 'boolean':
        field = Type.Boolean(opts);
        break;
      case 'array':
        field = Type.Array(Type.Any(), opts);
        break;
      case 'object':
        field = Type.Object({}, { additionalProperties: true, ...(opts ?? {}) });
        break;
      default:
        field = Type.Any();
    }

    if (!requiredSet.has(key)) {
      field = Type.Optional(field);
    }

    shape[key] = field;
  }

  return Type.Object(shape, { additionalProperties: true });
}

function toolResultToContent(toolName: string, result: string): Array<
  | { type: 'text'; text: string }
  | { type: 'image'; data: string; mimeType: string }
> {
  if (toolName === 'capture_screen') {
    const parsed = parseImageToolResult(result);
    if (parsed) {
      return [{ type: 'image' as const, data: parsed.data, mimeType: parsed.mediaType }];
    }
  }
  return [{ type: 'text' as const, text: result }];
}

async function requestPermission(
  conversationId: string,
  toolName: string,
  input: Record<string, unknown>,
): Promise<{ behavior: 'allow'; updatedInput: Record<string, unknown> } | { behavior: 'deny'; message: string }> {
  const requestId = crypto.randomUUID();
  sendToClient(activeClient, {
    type: 'permission_request',
    conversationId,
    requestId,
    toolName,
    input,
  });

  return new Promise((resolve) => {
    const timeout = setTimeout(() => {
      pendingPermissions.delete(requestId);
      resolve({ behavior: 'deny', message: 'Permission request timed out' });
    }, 120_000);

    pendingPermissions.set(requestId, { resolve, conversationId, toolName, input, timeout });
  });
}

function createAgentForConversation(
  conversationId: string,
  overrides?: {
    systemPrompt?: string;
    modelProvider?: string;
    modelId?: string;
    thinkingLevel?: ThinkingLevel;
    messages?: AgentMessage[];
  },
): Agent {
  // Best-effort MCP init (skills + remote tools). If it fails, we still run with base tools.
  void ensureMcpInitialized();

  const systemPrompt = overrides?.systemPrompt ?? buildFluxSystemPrompt();
  const provider = overrides?.modelProvider ?? AGENT_PROVIDER;
  const modelId = overrides?.modelId ?? AGENT_MODEL;

  let model;
  try {
    model = getModel(provider as any, modelId);
  } catch {
    model = getModel('anthropic', 'claude-sonnet-4-20250514');
  }

  const allToolDefs: ToolDefinition[] = [
    ...baseTools,
    ...helperTools,
    ...cachedRemoteTools,
  ];

  const tools: AgentTool[] = allToolDefs.map((def) => {
    const parameters = jsonSchemaToTypeBox(def.input_schema);

    const tool: AgentTool = {
      name: def.name,
      label: def.name,
      description: def.description,
      parameters,
      execute: async (toolCallId, params, signal) => {
        const input = (params ?? {}) as Record<string, unknown>;

        // Permission gate for dangerous command-like inputs.
        if (requiresApproval(def.name, input)) {
          const decision = await requestPermission(conversationId, def.name, input);
          if (decision.behavior !== 'allow') {
            sendToClient(activeClient, {
              type: 'tool_use_complete',
              conversationId,
              toolUseId: toolCallId,
              toolName: def.name,
              resultPreview: decision.message,
            });
            throw new Error(decision.message);
          }
        }

        // Local helper tools
        if (def.name === 'linear__setup') {
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

          sendToClient(activeClient, {
            type: 'tool_use_start',
            conversationId,
            toolUseId: toolCallId,
            toolName: def.name,
            inputSummary: def.name,
          });
          sendToClient(activeClient, {
            type: 'tool_use_complete',
            conversationId,
            toolUseId: toolCallId,
            toolName: def.name,
            resultPreview: 'Done',
          });

          return { content: [{ type: 'text', text }], details: {} };
        }

        if (def.name === 'linear__mcp_list_tools') {
          sendToClient(activeClient, {
            type: 'tool_use_start',
            conversationId,
            toolUseId: toolCallId,
            toolName: def.name,
            inputSummary: def.name,
          });

          try {
            await ensureMcpInitialized();
            const tools = await mcpManager.listTools('linear');
            const payload = tools.map((t) => ({ name: t.name, description: t.description ?? null }));
            const text = JSON.stringify(payload, null, 2);

            sendToClient(activeClient, {
              type: 'tool_use_complete',
              conversationId,
              toolUseId: toolCallId,
              toolName: def.name,
              resultPreview: 'Done',
            });

            return { content: [{ type: 'text', text }], details: {} };
          } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            sendToClient(activeClient, {
              type: 'tool_use_complete',
              conversationId,
              toolUseId: toolCallId,
              toolName: def.name,
              resultPreview: msg,
            });
            throw new Error(msg);
          }
        }

        // Remote MCP tools (e.g., linear__issueCreate) are exposed as serverId__tool
        const parsed = mcpManager.parseAnthropicToolName(def.name);
        if (parsed) {
          sendToClient(activeClient, {
            type: 'tool_use_start',
            conversationId,
            toolUseId: toolCallId,
            toolName: def.name,
            inputSummary: summarizeToolInput(def.name, input),
          });

          try {
            await ensureMcpInitialized();
            const res = await mcpManager.callTool(parsed.serverId, parsed.mcpToolName, input);
            const text = JSON.stringify(res, null, 2);

            sendToClient(activeClient, {
              type: 'tool_use_complete',
              conversationId,
              toolUseId: toolCallId,
              toolName: def.name,
              resultPreview: 'Done',
            });

            return { content: [{ type: 'text', text }], details: {} };
          } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            sendToClient(activeClient, {
              type: 'tool_use_complete',
              conversationId,
              toolUseId: toolCallId,
              toolName: def.name,
              resultPreview: msg,
            });
            throw new Error(msg);
          }
        }

        // Flux/Swift tools
        sendToClient(activeClient, {
          type: 'tool_request',
          conversationId,
          toolUseId: toolCallId,
          toolName: def.name,
          input,
        });

        sendToClient(activeClient, {
          type: 'tool_use_start',
          conversationId,
          toolUseId: toolCallId,
          toolName: def.name,
          inputSummary: summarizeToolInput(def.name, input),
        });

        const result = await new Promise<string>((resolve, reject) => {
          if (signal?.aborted) {
            reject(new Error('Tool execution aborted'));
            return;
          }

          const timeout = setTimeout(() => {
            pendingSwiftToolCalls.delete(toolCallId);
            reject(new Error('Tool execution timed out'));
          }, TOOL_TIMEOUT_MS);

          const onAbort = () => {
            clearTimeout(timeout);
            pendingSwiftToolCalls.delete(toolCallId);
            reject(new Error('Tool execution aborted'));
          };

          signal?.addEventListener('abort', onAbort, { once: true });

          pendingSwiftToolCalls.set(toolCallId, {
            resolve: (val) => {
              signal?.removeEventListener('abort', onAbort);
              resolve(val);
            },
            reject: (err) => {
              signal?.removeEventListener('abort', onAbort);
              reject(err);
            },
            conversationId,
            toolName: def.name,
            timeout,
          });
        });

        sendToClient(activeClient, {
          type: 'tool_use_complete',
          conversationId,
          toolUseId: toolCallId,
          toolName: def.name,
          resultPreview: toolResultPreview(def.name, result),
        });

        return { content: toolResultToContent(def.name, result), details: {} };
      },
    };

    return tool;
  });

  const agent = new Agent({
    initialState: {
      systemPrompt,
      model,
      thinkingLevel: overrides?.thinkingLevel ?? AGENT_THINKING_LEVEL,
      tools,
      messages: overrides?.messages ?? [],
    },
  });

  agent.subscribe((event) => {
    if (event.type === 'message_update' && event.assistantMessageEvent.type === 'text_delta') {
      sendToClient(activeClient, {
        type: 'stream_chunk',
        conversationId,
        content: event.assistantMessageEvent.delta,
      });

      // Telegram doesn't want token spam; it gets a final message after the turn.
      const session = sessions.get(conversationId);
      if (session) touchIdle(session);
    }
  });

  return agent;
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
  const wss = new WebSocketServer({
    port,
    host: '127.0.0.1',
    // Keep generous but bounded payload sizes to avoid memory spikes (e.g. huge base64 screenshots).
    maxPayload: parsePositiveIntEnv(process.env.FLUX_WS_MAX_PAYLOAD_BYTES, 25 * 1024 * 1024),
  });
  mainWss = wss;

  log.info(`WebSocket server listening on port ${port}`);
  log.info(`Agent config: provider=${AGENT_PROVIDER}, model=${AGENT_MODEL}, thinking=${AGENT_THINKING_LEVEL}, idleMs=${AGENT_IDLE_TIMEOUT_MS}`);

  wss.on('connection', (ws) => {
    // If auth is enabled, require a 'hello' handshake before accepting any other messages.
    let isAuthenticated = !REQUIRE_BRIDGE_AUTH;

    const denyAndClose = (reason: string) => {
      try {
        ws.send(JSON.stringify({ type: 'assistant_message', conversationId: 'system', content: reason }));
      } catch {
        // ignore
      }
      try {
        ws.close();
      } catch {
        // ignore
      }
    };

    ws.on('message', (data) => {
      // Cheap precheck before JSON.parse.
      const raw = data.toString();
      if (raw.length > 0) {
        const firstNonWs = raw.trimStart()[0];
        if (firstNonWs !== '{') {
          log.warn('Received non-JSON message from Swift app');
          return;
        }
      }

      const message = parseIncomingMessage(raw);
      if (!message) {
        log.warn('Received invalid message from Swift app');
        return;
      }

      if (!isAuthenticated) {
        if (message.type !== 'hello') {
          log.warn('Rejected unauthenticated client message');
          denyAndClose('Unauthorized: missing hello handshake.');
          return;
        }

        const token = (message.token ?? '').trim();
        if (token.length === 0 || token !== BRIDGE_AUTH_TOKEN) {
          log.warn('Rejected client: invalid bridge token');
          denyAndClose('Unauthorized: invalid bridge token.');
          return;
        }

        isAuthenticated = true;
        log.info('Swift app authenticated');

        // Only now mark this socket as the active client.
        activeClient = ws;
        return;
      }

      // Ignore subsequent hello messages.
      if (message.type === 'hello') return;

      handleMessage(ws, message);
    });

    if (!REQUIRE_BRIDGE_AUTH) {
      log.info('Swift app connected');
      activeClient = ws;
    } else {
      log.info('Swift app connected (awaiting authentication)');
    }

    ws.on('close', () => {
      log.info('Swift app disconnected');
      if (activeClient === ws) {
        activeClient = null;
      }

      // Fail any pending tool calls and permissions waiting on Swift.
      flushPendingToolCalls('Flux is offline. Open the app to reconnect.');
      for (const [requestId, pending] of pendingPermissions.entries()) {
        clearTimeout(pending.timeout);
        pending.resolve({ behavior: 'deny', message: 'Flux is offline. Open the app to reconnect.' });
        pendingPermissions.delete(requestId);
      }
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
    case 'fork_conversation':
      handleForkConversation(message);
      break;
    case 'permission_response':
      handlePermissionResponse(message);
      break;
    default:
      log.warn('Unknown message type:', (message as unknown as Record<string, unknown>).type);
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

function handleForkConversation(message: ForkConversationMessage): void {
  const { sourceConversationId, newConversationId } = message;
  const sourceSession = sessions.get(sourceConversationId);

  if (!sourceSession) {
    const reason = 'Unable to fork: the source conversation was not found.';
    sendToClient(activeClient, {
      type: 'fork_conversation_result',
      conversationId: newConversationId,
      success: false,
      reason,
    });
    return;
  }

  const state = sourceSession.agent.state;
  const forkedAgent = createAgentForConversation(newConversationId, {
    systemPrompt: state.systemPrompt,
    thinkingLevel: state.thinkingLevel as ThinkingLevel,
    messages: [...state.messages],
  });

  const forkedSession: ConversationSession = {
    conversationId: newConversationId,
    agent: forkedAgent,
    isRunning: false,
    pendingMessages: [],
  };

  sessions.set(newConversationId, forkedSession);
  sendToClient(activeClient, {
    type: 'fork_conversation_result',
    conversationId: newConversationId,
    success: true,
  });
}

async function handleChat(ws: WebSocket, message: ChatMessage): Promise<void> {
  const { conversationId, content } = message;
  const images = sanitizeChatImages(message.images);
  const summary = content.trim().length > 0 ? content : '[image-only message]';
  const imageSummary = images.length > 0 ? ` (+${images.length} image${images.length === 1 ? '' : 's'})` : '';
  log.info(`[${conversationId}] User: ${summary}${imageSummary}`);

  const anthropicKey = (process.env.ANTHROPIC_API_KEY ?? '').trim();
  if (AGENT_PROVIDER === 'anthropic' && anthropicKey.length === 0) {
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

  const maxImages = parsePositiveIntEnv(process.env.FLUX_MAX_IMAGES_PER_MESSAGE, 4);
  // Base64 overhead is ~33%, so 8MB base64 is ~6MB binary.
  const maxBase64Chars = parsePositiveIntEnv(process.env.FLUX_MAX_IMAGE_BASE64_CHARS, 8 * 1024 * 1024);

  return images
    .slice(0, Math.max(0, maxImages))
    .filter((image) => typeof image?.data === 'string' && image.data.length > 0)
    .filter((image) => image.data.length <= maxBase64Chars)
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
    session.pendingMessages.push(message);
    touchIdle(session);
    return;
  }

  startSessionRun(session, [message]);
}

function startSessionRun(session: ConversationSession, messages: QueuedUserMessage[]): void {
  session.isRunning = true;
  touchIdle(session);

  void runAgentSession(session, messages).catch((error) => {
    log.error('Agent run error:', error);
    sendToClient(activeClient, {
      type: 'assistant_message',
      conversationId: session.conversationId,
      content: `Error: ${error instanceof Error ? error.message : 'Unknown error'}`,
    });
  });
}

async function runAgentSession(session: ConversationSession, messages: QueuedUserMessage[]): Promise<void> {
  const conversationId = session.conversationId;
  sendToClient(activeClient, { type: 'run_status', conversationId, isWorking: true });

  try {
    for (const msg of messages) {
      const attachments = msg.images.map((image) => ({
        type: 'image' as const,
        data: image.data,
        mimeType: image.mediaType,
      }));

      await session.agent.prompt(msg.text, attachments.length > 0 ? attachments : undefined);
    }
  } finally {
    clearIdle(session);
    session.isRunning = false;
    flushPendingPermissions(conversationId, 'Session ended');
    sendToClient(activeClient, { type: 'run_status', conversationId, isWorking: false });

    if (session.pendingMessages.length > 0) {
      const next = [...session.pendingMessages];
      session.pendingMessages = [];
      startSessionRun(session, next);
      return;
    }

    touchIdle(session);
  }
}

const FLUX_SYSTEM_PROMPT = `You are Flux, a macOS AI desktop copilot. Your role is to help users accomplish tasks on their Mac by reading their screen when necessary and taking actions on their behalf.

You have access to the following tools:

**Screen Context Tools** (use ONLY when the user explicitly asks about what is on their screen, needs information about visible windows/UI elements, or when visual information is required to complete their request):
- capture_screen: Capture a screenshot of the display or frontmost window
- read_visible_windows: Read accessibility context from visible windows
- read_ax_tree: Read the accessibility tree of the frontmost window
- read_selected_text: Read currently selected text
- read_clipboard_history: Read recent clipboard history

**Session Context Tools**:
- read_session_history: Read recently visited apps/windows (with timestamps)
- get_session_context_summary: Human-readable summary of recent app activity

**GitHub / CI Tools**:
- check_github_status
- manage_github_repos

**Calendar Tools**:
- calendar_search_events
- calendar_add_event
- calendar_edit_event
- calendar_delete_event
- calendar_navigate_to_date

**Remote MCP Tools (optional)**:
- <serverId>__<toolName> (for MCP servers discovered via installed skills)

Important guidelines:
- Do NOT use screen context tools unless the user's request specifically requires information about what's currently on their screen or visible in their windows
- If the user has attached a screenshot or image to their message, use that image instead of capturing a new screenshot
- Be concise and helpful in your responses
- Ask clarifying questions when the user's request is ambiguous or lacks necessary details
- For straightforward requests that don't require screen information, proceed directly with the appropriate action`;

function buildFluxSystemPrompt(): string {
  let prompt = FLUX_SYSTEM_PROMPT;

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
      agent: createAgentForConversation(conversationId),
      isRunning: false,
      pendingMessages: [],
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

  // Best-effort cancel any in-flight turn.
  try {
    session.agent.abort();
  } catch {
    // ignore
  }

  session.pendingMessages = [];
  clearPendingToolCallsForConversation(conversationId, reason);
  flushPendingPermissions(conversationId, reason);

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
  mcpBridgeWss = wss;

  wss.on('connection', (ws) => {
    ws.on('message', (data) => {
      const message = parseBridgeMessage(data.toString());
      if (!message) {
        log.warn('Invalid MCP bridge message');
        return;
      }

      handleMcpBridgeMessage(ws, message);
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

type PendingSwiftToolCall = {
  resolve: (result: string) => void;
  reject: (err: Error) => void;
  conversationId: string;
  toolName: string;
  timeout: NodeJS.Timeout;
};

const pendingSwiftToolCalls = new Map<string, PendingSwiftToolCall>();

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
  const swiftPending = pendingSwiftToolCalls.get(message.toolUseId);
  if (swiftPending) {
    pendingSwiftToolCalls.delete(message.toolUseId);
    clearTimeout(swiftPending.timeout);
    swiftPending.resolve(message.toolResult);
    const session = sessions.get(message.conversationId);
    if (session) touchIdle(session);
    return;
  }

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

function handlePermissionResponse(message: PermissionResponseMessage): void {
  const pending = pendingPermissions.get(message.requestId);
  if (!pending) {
    log.warn(`No pending permission for requestId=${message.requestId}`);
    return;
  }
  clearTimeout(pending.timeout);
  pendingPermissions.delete(message.requestId);

  if (message.behavior === 'allow') {
    if (pending.toolName === 'AskUserQuestion') {
      const answers = message.answers ?? {};
      const updatedInput: Record<string, unknown> = {
        ...pending.input,
        answers,
      };
      pending.resolve({ behavior: 'allow', updatedInput });
      return;
    }
    pending.resolve({ behavior: 'allow', updatedInput: pending.input });
  } else {
    pending.resolve({ behavior: 'deny', message: message.message || 'User denied this action' });
  }
}

function flushPendingPermissions(conversationId: string, reason: string): void {
  for (const [requestId, pending] of pendingPermissions.entries()) {
    if (pending.conversationId !== conversationId) continue;
    clearTimeout(pending.timeout);
    pending.resolve({ behavior: 'deny', message: reason });
    pendingPermissions.delete(requestId);
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

const TOOL_INPUT_SUMMARY_KEYS = [
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

function summarizeToolInput(toolName: string, input: Record<string, unknown>): string {
  for (const key of TOOL_INPUT_SUMMARY_KEYS) {
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

export async function shutdownBridge(): Promise<void> {
  log.info('Shutting down bridge: evicting all sessions...');

  // Evict every tracked session — this ends streams, flushes pending
  // tool calls / permissions, and lets the SDK tear down MCP children.
  const ids = Array.from(sessions.keys());
  for (const id of ids) {
    evictSession(id, 'Sidecar shutting down.');
  }

  // Close both WebSocket servers so no new connections are accepted
  // and existing sockets are terminated.
  const closeServer = (wss: WebSocketServer | null, label: string): Promise<void> =>
    new Promise((resolve) => {
      if (!wss) { resolve(); return; }
      // Terminate all connected clients first.
      for (const client of wss.clients) {
        try { client.terminate(); } catch { /* ignore */ }
      }
      wss.close((err) => {
        if (err) log.warn(`Error closing ${label} server: ${err.message}`);
        resolve();
      });
    });

  await Promise.all([
    closeServer(mainWss, 'main'),
    closeServer(mcpBridgeWss, 'MCP bridge'),
  ]);

  mainWss = null;
  mcpBridgeWss = null;
  log.info('Bridge shutdown complete.');
}
