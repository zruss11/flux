import { spawn, type ChildProcess } from 'child_process';
import crypto from 'crypto';
import net from 'net';

import { createLogger } from '../logger.js';

interface OpenClawRuntimeOptions {
  bin?: string;
  profile?: string;
  preferredPort?: number;
  autostart?: boolean;
}

const log = createLogger('openclaw-runtime');

const DEFAULT_PROFILE = 'flux';
const DEFAULT_PREFERRED_PORT = 19089;
const HEALTH_TIMEOUT_MS = 3_000;
const STARTUP_TIMEOUT_MS = 20_000;

export class OpenClawRuntime {
  private readonly bin: string;
  private readonly profile: string;
  private readonly preferredPort: number;
  private readonly autostart: boolean;

  private child: ChildProcess | null = null;
  private stopping = false;
  private wanted = false;
  private restartBackoffMs = 1_000;
  private restartTimer: NodeJS.Timeout | null = null;
  private token: string | null = null;
  private port: number | null = null;

  constructor(options: OpenClawRuntimeOptions = {}) {
    this.bin = options.bin ?? process.env.OPENCLAW_BIN ?? 'openclaw';
    this.profile = options.profile ?? process.env.OPENCLAW_PROFILE ?? DEFAULT_PROFILE;
    this.preferredPort = options.preferredPort ?? parseEnvInt(process.env.OPENCLAW_GATEWAY_PORT, DEFAULT_PREFERRED_PORT);
    this.autostart = options.autostart ?? process.env.FLUX_OPENCLAW_AUTOSTART !== '0';
  }

  isEnabled(): boolean {
    return this.autostart;
  }

  async start(): Promise<void> {
    if (!this.autostart) {
      log.info('OpenClaw autostart disabled (FLUX_OPENCLAW_AUTOSTART=0).');
      return;
    }

    if (this.child && !this.child.killed) return;

    this.wanted = true;
    this.stopping = false;
    this.clearRestartTimer();

    const available = await this.checkBinary();
    if (!available) {
      log.warn(`OpenClaw binary not available: ${this.bin}`);
      return;
    }

    await this.spawnAndWaitReady();
  }

  async stop(): Promise<void> {
    this.wanted = false;
    this.stopping = true;
    this.clearRestartTimer();

    const child = this.child;
    if (!child) return;
    this.child = null;

    await new Promise<void>((resolve) => {
      let settled = false;
      const settle = (): void => {
        if (settled) return;
        settled = true;
        resolve();
      };

      child.once('exit', () => settle());
      try {
        child.kill('SIGTERM');
      } catch {
        settle();
        return;
      }

      setTimeout(() => {
        if (!settled) {
          try {
            child.kill('SIGKILL');
          } catch {
            // ignore
          }
          settle();
        }
      }, 3_000);
    });
  }

  private async checkBinary(): Promise<boolean> {
    const result = await runCommand(this.bin, ['--version'], 8_000, {
      ...process.env,
      NO_COLOR: '1',
      FORCE_COLOR: '0',
    });
    return result.ok;
  }

  private async spawnAndWaitReady(): Promise<void> {
    this.port = await pickPort(this.preferredPort);
    this.token = crypto.randomBytes(24).toString('base64url');

    await this.syncProfileGatewayConfig(this.port, this.token);

    process.env.OPENCLAW_PROFILE = this.profile;
    process.env.OPENCLAW_GATEWAY_PORT = String(this.port);
    process.env.OPENCLAW_GATEWAY_TOKEN = this.token;

    const args = [
      '--profile',
      this.profile,
      'gateway',
      '--bind',
      'loopback',
      '--allow-unconfigured',
      '--auth',
      'token',
      '--token',
      this.token,
      '--port',
      String(this.port),
      '--ws-log',
      'compact',
    ];

    log.info(`Starting OpenClaw gateway (profile=${this.profile}, port=${this.port})`);

    const child = spawn(this.bin, args, {
      env: {
        ...process.env,
        NO_COLOR: '1',
        FORCE_COLOR: '0',
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    this.child = child;

    child.stdout?.on('data', (chunk: Buffer) => {
      for (const line of chunk.toString().split('\n').filter(Boolean)) {
        log.info(`[openclaw] ${line}`);
      }
    });
    child.stderr?.on('data', (chunk: Buffer) => {
      for (const line of chunk.toString().split('\n').filter(Boolean)) {
        log.warn(`[openclaw] ${line}`);
      }
    });

    child.on('exit', (code, signal) => {
      this.child = null;
      log.warn(`OpenClaw gateway exited (code=${code ?? 'null'}, signal=${signal ?? 'null'})`);
      if (!this.stopping && this.wanted) {
        this.scheduleRestart();
      }
    });

    const ready = await waitForHealth(this.bin, this.profile, this.port, this.token, STARTUP_TIMEOUT_MS);
    if (!ready) {
      log.warn('OpenClaw gateway did not become healthy in time.');
      if (this.child) {
        try {
          this.child.kill('SIGTERM');
        } catch {
          // ignore
        }
      }
      this.scheduleRestart();
      return;
    }

    this.restartBackoffMs = 1_000;
    log.info('OpenClaw gateway is healthy.');
  }

  private async syncProfileGatewayConfig(port: number, token: string): Promise<void> {
    const env = {
      ...process.env,
      NO_COLOR: '1',
      FORCE_COLOR: '0',
    };

    const configSets: Array<[string, string]> = [
      ['gateway.port', String(port)],
      ['gateway.auth.mode', 'token'],
      ['gateway.auth.token', token],
    ];

    for (const [path, value] of configSets) {
      const result = await runCommand(this.bin, ['--profile', this.profile, 'config', 'set', path, value], 8_000, env);
      if (!result.ok) {
        log.warn(`Failed to sync OpenClaw profile config for ${path}.`);
      }
    }
  }

  private scheduleRestart(): void {
    if (this.restartTimer || !this.wanted) return;
    const delay = this.restartBackoffMs;
    this.restartBackoffMs = Math.min(this.restartBackoffMs * 2, 10_000);
    log.info(`Restarting OpenClaw in ${delay}ms...`);
    this.restartTimer = setTimeout(() => {
      this.restartTimer = null;
      if (!this.wanted) return;
      void this.spawnAndWaitReady();
    }, delay);
  }

  private clearRestartTimer(): void {
    if (!this.restartTimer) return;
    clearTimeout(this.restartTimer);
    this.restartTimer = null;
  }
}

async function waitForHealth(
  bin: string,
  profile: string,
  port: number,
  token: string,
  timeoutMs: number,
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const result = await runCommand(
      bin,
      ['--profile', profile, 'health', '--json', '--timeout', String(HEALTH_TIMEOUT_MS)],
      HEALTH_TIMEOUT_MS + 2_000,
      {
        ...process.env,
        OPENCLAW_GATEWAY_PORT: String(port),
        OPENCLAW_GATEWAY_TOKEN: token,
        OPENCLAW_PROFILE: profile,
        NO_COLOR: '1',
        FORCE_COLOR: '0',
      },
    );

    if (result.ok) return true;
    await sleep(500);
  }
  return false;
}

function runCommand(
  bin: string,
  args: string[],
  timeoutMs: number,
  env: NodeJS.ProcessEnv,
): Promise<{ ok: boolean }> {
  return new Promise<{ ok: boolean }>((resolve) => {
    const child = spawn(bin, args, {
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let settled = false;

    const settle = (ok: boolean): void => {
      if (settled) return;
      settled = true;
      resolve({ ok });
    };

    const timer = setTimeout(() => {
      try {
        child.kill('SIGKILL');
      } catch {
        // ignore
      }
      settle(false);
    }, timeoutMs);

    child.on('close', (code) => {
      clearTimeout(timer);
      settle(code === 0);
    });

    child.on('error', () => {
      clearTimeout(timer);
      settle(false);
    });
  });
}

async function pickPort(preferred: number): Promise<number> {
  if (await isPortFree(preferred)) return preferred;
  return await new Promise<number>((resolve) => {
    const server = net.createServer();
    server.unref();
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const port = typeof address === 'object' && address ? address.port : preferred;
      server.close(() => resolve(port));
    });
    server.on('error', () => resolve(preferred));
  });
}

function isPortFree(port: number): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    const server = net.createServer();
    server.unref();
    server.once('error', () => resolve(false));
    server.listen(port, '127.0.0.1', () => {
      server.close(() => resolve(true));
    });
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parseEnvInt(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return parsed;
}
