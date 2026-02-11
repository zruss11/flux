import fs from 'fs';
import os from 'os';
import path from 'path';
import crypto from 'crypto';

export interface TelegramConfig {
  botToken: string;
  defaultChatId: string;
}

export interface TelegramInboundMessage {
  chatId: string;
  threadId?: number;
  text: string;
  isGroup: boolean;
  from: {
    id?: number;
    username?: string;
    firstName?: string;
    lastName?: string;
  };
}

interface PairingRequest {
  chatId: string;
  code: string;
  createdAt: number;
  username?: string;
  firstName?: string;
  lastName?: string;
}

interface PairingApproval {
  approvedAt: number;
}

interface PairingStore {
  pending: Record<string, PairingRequest>;
  approved: Record<string, PairingApproval>;
}

const PAIRING_TTL_SECONDS = 3600;

function pairingFilePath(): string {
  return path.join(os.homedir(), '.flux', 'telegram', 'pairing.json');
}

function loadPairingStore(): PairingStore {
  const filePath = pairingFilePath();
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    const parsed = JSON.parse(raw) as PairingStore;
    return {
      pending: parsed.pending ?? {},
      approved: parsed.approved ?? {},
    };
  } catch {
    return { pending: {}, approved: {} };
  }
}

function savePairingStore(store: PairingStore): void {
  const filePath = pairingFilePath();
  const dir = path.dirname(filePath);
  fs.mkdirSync(dir, { recursive: true });
  const tmpPath = `${filePath}.${process.pid}.${crypto.randomBytes(4).toString('hex')}.tmp`;
  try {
    fs.writeFileSync(tmpPath, JSON.stringify(store, null, 2));
    fs.renameSync(tmpPath, filePath);
  } finally {
    try { fs.unlinkSync(tmpPath); } catch {}
  }
}

function pruneExpiredPending(store: PairingStore): void {
  const now = Date.now() / 1000;
  for (const [chatId, req] of Object.entries(store.pending)) {
    if (now - req.createdAt > PAIRING_TTL_SECONDS) {
      delete store.pending[chatId];
    }
  }
}

function getOrCreatePairing(chatId: string, meta: Omit<PairingRequest, 'chatId' | 'code' | 'createdAt'>) {
  const store = loadPairingStore();
  pruneExpiredPending(store);

  if (store.approved[chatId]) {
    delete store.pending[chatId];
    savePairingStore(store);
    return { code: '', created: false, approved: true };
  }

  const existing = store.pending[chatId];
  if (existing) {
    savePairingStore(store);
    return { code: existing.code, created: false, approved: false };
  }

  const code = crypto.randomBytes(4).toString('hex').toUpperCase();
  store.pending[chatId] = {
    chatId,
    code,
    createdAt: Date.now() / 1000,
    ...meta,
  };
  savePairingStore(store);
  return { code, created: true, approved: false };
}

function isApproved(chatId: string): boolean {
  const store = loadPairingStore();
  pruneExpiredPending(store);
  savePairingStore(store);
  return Boolean(store.approved[chatId]);
}

function buildPairingReply(code: string, chatId: string): string {
  return [
    'Flux pairing required.',
    `Chat ID: ${chatId}`,
    `Pairing code: ${code}`,
    'Approve in Flux Settings → Telegram Pairing Code.',
  ].join('\n');
}

export function createTelegramBot(options: {
  onMessage: (msg: TelegramInboundMessage) => Promise<void> | void;
  onLog?: (level: 'info' | 'warn' | 'error', message: string) => void;
}) {
  let config: TelegramConfig = { botToken: '', defaultChatId: '' };
  let polling = false;
  let stopRequested = false;
  let offset = 0;
  let botUsername = '';
  let currentToken = '';
  let abortController: AbortController | null = null;
  let pollLoopPromise: Promise<void> | null = null;

  const log = (level: 'info' | 'warn' | 'error', message: string) => {
    options.onLog?.(level, message);
  };

  const updateConfig = async (next: TelegramConfig) => {
    const tokenChanged = next.botToken !== currentToken;
    config = next;
    if (!next.botToken) {
      await stopPolling();
      return;
    }
    if (tokenChanged) {
      await stopPolling();
      currentToken = next.botToken;
      offset = 0;
      startPolling();
    } else if (!polling) {
      startPolling();
    }
  };

  const startPolling = () => {
    if (polling) return;
    stopRequested = false;
    polling = true;
    pollLoopPromise = pollLoop().catch((err) => {
      log('error', `telegram polling crashed: ${String(err)}`);
    }).finally(() => {
      polling = false;
      pollLoopPromise = null;
    });
  };

  const stopPolling = async () => {
    stopRequested = true;
    polling = false;
    if (abortController) {
      abortController.abort();
      abortController = null;
    }
    if (pollLoopPromise) {
      await pollLoopPromise;
      pollLoopPromise = null;
    }
  };

  const pollLoop = async () => {
    botUsername = await fetchBotUsername();
    while (!stopRequested && config.botToken) {
      if (!botUsername) {
        botUsername = await fetchBotUsername();
      }
      try {
        abortController = new AbortController();
        const url = new URL(`https://api.telegram.org/bot${config.botToken}/getUpdates`);
        url.searchParams.set('timeout', '25');
        url.searchParams.set('offset', String(offset));
        const res = await fetch(url.toString(), { signal: abortController.signal });
        if (!res.ok) {
          log('warn', `telegram getUpdates failed: HTTP ${res.status}`);
          await delay(1500);
          continue;
        }
        const json = (await res.json()) as { ok: boolean; result: any[]; description?: string };
        if (!json.ok) {
          log('warn', `telegram getUpdates error: ${json.description ?? 'unknown error'}`);
          await delay(1500);
          continue;
        }
        for (const update of json.result) {
          offset = Math.max(offset, (update.update_id ?? 0) + 1);
          await handleUpdate(update);
        }
      } catch (err) {
        if (stopRequested) {
          break;
        }
        log('warn', `telegram polling error: ${String(err)}`);
        await delay(2000);
      }
    }
  };

  const handleUpdate = async (update: any) => {
    const msg = update?.message;
    if (!msg) return;
    if (msg.from?.is_bot) return;
    const text = (msg.text ?? msg.caption ?? '').trim();
    if (!text) return;

    const chat = msg.chat;
    const chatId = String(chat?.id ?? '');
    if (!chatId) return;
    const isGroup = chat?.type === 'group' || chat?.type === 'supergroup';
    const threadId = typeof msg.message_thread_id === 'number' ? msg.message_thread_id : undefined;

    if (isGroup) {
      if (!botUsername || !messageMentionsBot(text, msg, botUsername)) {
        return;
      }
    } else {
      if (!isApproved(chatId)) {
        const result = getOrCreatePairing(chatId, {
          username: msg.from?.username,
          firstName: msg.from?.first_name,
          lastName: msg.from?.last_name,
        });
        if (!result.approved && result.created) {
          await sendMessage(buildPairingReply(result.code, chatId), chatId);
        }
        return;
      }
    }

    await options.onMessage({
      chatId,
      threadId,
      text,
      isGroup,
      from: {
        id: msg.from?.id,
        username: msg.from?.username,
        firstName: msg.from?.first_name,
        lastName: msg.from?.last_name,
      },
    });
  };

  const fetchBotUsername = async (): Promise<string> => {
    if (!config.botToken) return '';
    try {
      const url = `https://api.telegram.org/bot${config.botToken}/getMe`;
      const res = await fetch(url);
      if (!res.ok) {
        log('warn', `telegram getMe failed: HTTP ${res.status}`);
        return '';
      }
      const json = (await res.json()) as { ok: boolean; result?: { username?: string } };
      if (!json.ok) return '';
      return (json.result?.username ?? '').toLowerCase();
    } catch (err) {
      log('warn', `telegram getMe error: ${String(err)}`);
      return '';
    }
  };

  const sendMessage = async (text: string, chatId: string, threadId?: number): Promise<void> => {
    if (!config.botToken) return;
    const url = `https://api.telegram.org/bot${config.botToken}/sendMessage`;
    const payload: Record<string, unknown> = {
      chat_id: chatId,
      text,
    };
    if (threadId != null) {
      payload.message_thread_id = threadId;
    }
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    if (!res.ok) {
      const raw = await res.text();
      log('warn', `telegram sendMessage failed: HTTP ${res.status} ${raw}`);
    }
  };

  return {
    updateConfig,
    sendMessage,
  };
}

function messageMentionsBot(text: string, msg: any, botUsername: string): boolean {
  const lower = text.toLowerCase();
  if (lower.includes(`@${botUsername}`)) return true;
  const replyUsername = msg?.reply_to_message?.from?.username?.toLowerCase();
  if (replyUsername && replyUsername === botUsername) return true;
  return false;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
