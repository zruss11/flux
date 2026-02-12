import { spawn } from 'child_process';

export type OpenClawChannel =
  | 'telegram'
  | 'whatsapp'
  | 'discord'
  | 'googlechat'
  | 'slack'
  | 'signal'
  | 'imessage'
  | 'nostr'
  | 'msteams'
  | 'mattermost'
  | 'nextcloud-talk'
  | 'matrix'
  | 'bluebubbles'
  | 'line'
  | 'zalo'
  | 'zalouser'
  | 'tlon';

interface OpenClawClientOptions {
  bin?: string;
  profile?: string;
  timeoutMs?: number;
}

interface OpenClawCommandResult {
  ok: boolean;
  code: number | null;
  stdout: string;
  stderr: string;
}

interface SendMessageInput {
  message: string;
  channel?: OpenClawChannel;
  target?: string;
  account?: string;
  threadId?: string;
  replyTo?: string;
  silent?: boolean;
}

interface StatusInput {
  deep?: boolean;
  timeoutMs?: number;
}

const DEFAULT_TIMEOUT_MS = 45_000;

export class OpenClawClient {
  private readonly bin: string;
  private readonly profile: string;
  private readonly timeoutMs: number;
  private preflightRun = false;

  constructor(options: OpenClawClientOptions = {}) {
    this.bin = options.bin ?? process.env.OPENCLAW_BIN ?? 'openclaw';
    this.profile = options.profile ?? process.env.OPENCLAW_PROFILE ?? 'flux';
    this.timeoutMs = options.timeoutMs ?? parseEnvInt(process.env.OPENCLAW_TIMEOUT_MS, DEFAULT_TIMEOUT_MS);
  }

  async preflight(): Promise<void> {
    if (this.preflightRun) return;
    this.preflightRun = true;

    const result = await this.run(['--profile', this.profile, '--version'], 10_000);
    if (!result.ok) {
      throw new Error(
        `OpenClaw CLI is unavailable (bin=${this.bin}). Install it and retry. ${collectError(result)}`,
      );
    }
  }

  async channelsList(): Promise<string> {
    await this.preflight();
    const result = await this.run(['--profile', this.profile, 'channels', 'list', '--json']);
    return normalizeResult('channels list', result);
  }

  async status(input: StatusInput = {}): Promise<string> {
    await this.preflight();
    const args = ['--profile', this.profile, 'status', '--json'];
    if (input.deep) args.push('--deep');
    if (typeof input.timeoutMs === 'number' && Number.isFinite(input.timeoutMs) && input.timeoutMs > 0) {
      args.push('--timeout', String(Math.floor(input.timeoutMs)));
    }

    const result = await this.run(args);
    return normalizeResult('status', result);
  }

  async sendMessage(input: SendMessageInput): Promise<string> {
    await this.preflight();
    const text = input.message.trim();
    if (!text) throw new Error('message is required');

    const args = ['--profile', this.profile, 'message', 'send', '--message', text, '--json'];
    if (input.channel) args.push('--channel', input.channel);
    if (input.target) args.push('--target', input.target);
    if (input.account) args.push('--account', input.account);
    if (input.threadId) args.push('--thread-id', input.threadId);
    if (input.replyTo) args.push('--reply-to', input.replyTo);
    if (input.silent) args.push('--silent');

    const result = await this.run(args);
    return normalizeResult('message send', result);
  }

  private run(args: string[], timeoutMs = this.timeoutMs): Promise<OpenClawCommandResult> {
    return new Promise<OpenClawCommandResult>((resolve) => {
      const child = spawn(this.bin, args, {
        env: {
          ...process.env,
          NO_COLOR: '1',
          FORCE_COLOR: '0',
        },
        stdio: ['ignore', 'pipe', 'pipe'],
      });

      let stdout = '';
      let stderr = '';
      let settled = false;

      const settle = (payload: OpenClawCommandResult): void => {
        if (settled) return;
        settled = true;
        resolve(payload);
      };

      child.stdout?.on('data', (chunk: Buffer) => {
        stdout += chunk.toString();
      });
      child.stderr?.on('data', (chunk: Buffer) => {
        stderr += chunk.toString();
      });

      const timer = setTimeout(() => {
        try {
          child.kill('SIGKILL');
        } catch {
          // ignore
        }

        settle({
          ok: false,
          code: null,
          stdout,
          stderr: `${stderr}${stderr.trim().length > 0 ? '\n' : ''}timeout after ${timeoutMs}ms`,
        });
      }, timeoutMs);

      child.on('close', (code) => {
        clearTimeout(timer);
        settle({
          ok: code === 0,
          code: typeof code === 'number' ? code : null,
          stdout,
          stderr,
        });
      });

      child.on('error', (err) => {
        clearTimeout(timer);
        settle({
          ok: false,
          code: null,
          stdout,
          stderr: `${stderr}${stderr.trim().length > 0 ? '\n' : ''}${String(err)}`,
        });
      });
    });
  }
}

function parseEnvInt(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return parsed;
}

function normalizeResult(action: string, result: OpenClawCommandResult): string {
  const stdout = stripAnsi(result.stdout).trim();
  const stderr = stripAnsi(result.stderr).trim();

  if (!result.ok) {
    throw new Error(`OpenClaw ${action} failed. ${collectError({ ...result, stdout, stderr })}`);
  }

  if (stdout.length === 0) {
    return `${action}: success`;
  }

  const parsed = parseJsonMaybe(stdout);
  if (parsed) {
    return JSON.stringify(parsed, null, 2);
  }

  return stdout;
}

function parseJsonMaybe(raw: string): unknown | null {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function collectError(result: Pick<OpenClawCommandResult, 'code' | 'stdout' | 'stderr'>): string {
  const parts: string[] = [];
  if (result.code != null) parts.push(`exit=${result.code}`);
  const stderr = stripAnsi(result.stderr).trim();
  const stdout = stripAnsi(result.stdout).trim();
  if (stderr.length > 0) parts.push(`stderr=${stderr}`);
  if (stdout.length > 0) parts.push(`stdout=${stdout}`);
  return parts.join(' ');
}

function stripAnsi(input: string): string {
  return input.replace(/\u001b\[[0-9;]*m/g, '');
}
