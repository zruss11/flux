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

type IncomingMessage = ChatMessage | ToolResultMessage | SetApiKeyMessage | McpAuthMessage | SetTelegramConfigMessage | ActiveAppUpdateMessage | ForkConversationMessage | PermissionResponseMessage;

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

type AgentMessage = AgentAssistantMessage | AgentSystemMessage | AgentStreamEventMessage | AgentResultMessage;

type UnknownRecord = Record<string, unknown>;

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === 'object' && value !== null;
}

function isAgentMessage(value: unknown): value is AgentMessage {
  if (!isRecord(value)) return false;

  const message = value;
  return (
    message.type === 'assistant'
    || message.type === 'system'
    || message.type === 'stream_event'
    || message.type === 'result'
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

const AGENT_MODEL = process.env.FLUX_AGENT_MODEL || 'claude-sonnet-4-20250514';
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
let mcpBridgeUrl = '';
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
    String.raw`\brm\s+-rf\b`,
    String.raw`\brm\s+-fr\b`,
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
  /** When true, the next `query()` call will pass `forkSession: true` to create a new session branch. */
  forkOnNextRun?: boolean;
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
  log.info(`Agent config: model=${AGENT_MODEL}, settingSources=${AGENT_SETTING_SOURCES.join(',')}, idleMs=${AGENT_IDLE_TIMEOUT_MS}`);
  maybeStartAgentWarmup('bridge_start');

  wss.on('connection', (ws) => {
    log.info('Swift app connected');
    activeClient = ws;

    ws.on('message', (data) => {
      const message = parseIncomingMessage(data.toString());
      if (!message) {
        log.warn('Received invalid message from Swift app');
        return;
      }
      handleMessage(ws, message);
    });

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
        maybeStartAgentWarmup('api_key_updated');
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

function handleForkConversation(message: ForkConversationMessage): void {
  const { sourceConversationId, newConversationId } = message;
  const sourceSession = sessions.get(sourceConversationId);

  if (!sourceSession?.sessionId) {
    log.warn(`Cannot fork: no SDK session found for conversation ${sourceConversationId}`);
    const reason = 'Unable to fork: the source conversation has no active session.';
    sendToClient(activeClient, {
      type: 'fork_conversation_result',
      conversationId: newConversationId,
      success: false,
      reason,
    });
    return;
  }

  log.info(`Forking session ${sourceSession.sessionId} from ${sourceConversationId} → ${newConversationId}`);

  const forkedSession: ConversationSession = {
    conversationId: newConversationId,
    stream: null,
    sessionId: sourceSession.sessionId,
    lastAssistantUuid: sourceSession.lastAssistantUuid,
    isRunning: false,
    pendingMessages: [],
    toolUseByIndex: new Map(),
    pendingToolCompletions: new Map(),
    forkOnNextRun: true,
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

  if (!runtimeApiKey) {
    sendToClient(ws, {
      type: 'assistant_message',
      conversationId,
      content: 'No Anthropic API key configured. Please set your API key in Island Settings.',
    });
    return;
  }

  maybeStartAgentWarmup('first_chat');
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
  // Skip idle timer for forked sessions until first run completes,
  // ensuring the fork remains available when the user first interacts with it.
  if (session.forkOnNextRun !== true) {
    touchIdle(session);
  }

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

  const conversationId = session.conversationId;
  sendToClient(activeClient, { type: 'run_status', conversationId, isWorking: true });

  const runId = crypto.randomUUID();
  const shouldFork = session.forkOnNextRun === true;
  session.forkOnNextRun = false;

  const canUseTool = (
    toolName: string,
    input: Record<string, unknown>,
  ): Promise<{ behavior: 'allow'; updatedInput: Record<string, unknown> } | { behavior: 'deny'; message: string }> => {
    if (toolName !== 'AskUserQuestion' && !requiresApproval(toolName, input)) {
      return Promise.resolve({ behavior: 'allow', updatedInput: input });
    }

    const requestId = crypto.randomUUID();

    if (toolName === 'AskUserQuestion') {
      const questions = (input.questions ?? []) as Array<{
        question: string;
        options: Array<{ label: string; description?: string }>;
        multiSelect?: boolean;
      }>;
      sendToClient(activeClient, {
        type: 'ask_user_question',
        conversationId,
        requestId,
        questions,
      });
    } else {
      sendToClient(activeClient, {
        type: 'permission_request',
        conversationId,
        requestId,
        toolName,
        input,
      });
    }

    return new Promise((resolve) => {
      const timeout = setTimeout(() => {
        pendingPermissions.delete(requestId);
        resolve({ behavior: 'deny', message: 'Permission request timed out' });
      }, 120_000);

      pendingPermissions.set(requestId, { resolve, conversationId, toolName, input, timeout });
    });
  };

  try {
    for await (const message of query({
      prompt: session.stream,
      options: buildQueryOptions(conversationId, runId, {
        resume: session.sessionId,
        resumeSessionAt: session.lastAssistantUuid,
        permissionMode: 'default',
        allowDangerouslySkipPermissions: false,
        canUseTool,
        includePartialMessages: true,
        ...(shouldFork ? { forkSession: true } : {}),
      }),
    })) {
      if (isAgentMessage(message)) {
        handleAgentMessage(session, message);
      } else {
        log.warn(`Ignoring unsupported message type: ${session.conversationId}`, message);
      }
    }
  } finally {
    clearIdle(session);
    session.isRunning = false;
    session.stream = null;
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

function buildQueryOptions(
  conversationId: string,
  runId: string,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    cwd: process.cwd(),
    permissionMode: 'bypassPermissions',
    allowDangerouslySkipPermissions: true,
    includePartialMessages: true,
    settingSources: AGENT_SETTING_SOURCES,
    allowedTools: ALLOWED_TOOLS,
    mcpServers: {
      flux: resolveMcpServerConfig(conversationId, runId),
    },
    model: AGENT_MODEL,
    systemPrompt: {
      type: 'preset',
      preset: 'claude_code',
      append: buildFluxSystemPrompt(),
    },
    ...overrides,
  };
}

function maybeStartAgentWarmup(trigger: string): void {
  if (!AGENT_WARMUP_ENABLED) return;
  if (!runtimeApiKey) return;
  if (agentWarmupComplete) return;
  if (agentWarmupPromise) return;
  if (agentWarmupAttempts >= AGENT_WARMUP_MAX_ATTEMPTS) return;

  agentWarmupAttempts += 1;
  agentWarmupPromise = runAgentWarmup(trigger)
    .then(() => {
      agentWarmupComplete = true;
    })
    .catch((error) => {
      log.warn(`Agent warmup failed (${trigger}):`, error instanceof Error ? error.message : error);
    })
    .finally(() => {
      agentWarmupPromise = null;
    });
}

async function runAgentWarmup(trigger: string): Promise<void> {
  const startedAt = Date.now();
  const warmupConversationId = `warmup-${crypto.randomUUID()}`;
  const runId = crypto.randomUUID();

  log.info(`Starting agent warmup (trigger=${trigger})`);

  for await (const message of query({
    prompt: 'Warmup run. Reply with exactly: ok',
    options: buildQueryOptions(warmupConversationId, runId, {
      includePartialMessages: false,
      persistSession: false,
      maxTurns: 1,
      thinking: { type: 'disabled' },
      effort: 'low',
    }),
  })) {
    if (message.type === 'result') break;
  }

  log.info(`Agent warmup completed in ${Date.now() - startedAt}ms`);
}

function handleAgentMessage(session: ConversationSession, message: AgentMessage): void {
  const msgType = message.type === 'system' ? `system/${message.subtype}` : message.type;
  log.debug(`[agent] ${session.conversationId} message=${msgType}`);

  if (message.type === 'assistant' && message.uuid) {
    session.lastAssistantUuid = message.uuid;
  }

  if (message.type === 'system' && message.subtype === 'init') {
    session.sessionId = message.session_id;
    if (message.session_id) {
      sendToClient(activeClient, {
        type: 'session_info',
        conversationId: session.conversationId,
        sessionId: message.session_id,
      });
    }
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
      const index = parseEventIndex(event);
      const toolUseId = parseStreamBlockId(event);
      const toolName = parseStreamBlockName(event);
      if (index === null || toolUseId === null || toolName === null) return;

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
      const index = parseEventIndex(event);
      const partialJson = parseEventInputJsonDelta(event);
      if (index === null || partialJson === null) return;

      const tracked = session.toolUseByIndex.get(index);
      if (tracked) {
        tracked.inputChunks.push(partialJson);
        touchIdle(session);
      }
      return;
    }

    // Content block finished — update tool input summary with parsed input
    if (event?.type === 'content_block_stop') {
      const index = parseEventIndex(event);
      if (index === null) return;

      const tracked = session.toolUseByIndex.get(index);
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
        session.toolUseByIndex.delete(index);
      }
      return;
    }

    // Text delta — stream to UI
    if (
      event?.type === 'content_block_delta'
      && event.delta?.type === 'text_delta'
      && event.delta.text
    ) {
      const content = parseEventTextDelta(event);
      if (content === null) return;

      sendToClient(activeClient, {
        type: 'stream_chunk',
        conversationId: session.conversationId,
        content,
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

const FLUX_SYSTEM_PROMPT = `You are Flux, a macOS AI desktop copilot. Your role is to help users accomplish tasks on their Mac by reading their screen when necessary and taking actions on their behalf.

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
