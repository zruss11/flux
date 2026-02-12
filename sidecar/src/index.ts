import 'dotenv/config';
import { spawn, ChildProcess } from 'child_process';
import path from 'path';
import fs from 'fs';
import os from 'os';
import { fileURLToPath } from 'url';
import { startBridgeWithOptions } from './bridge.js';
import { createLogger } from './logger.js';
import { OpenClawRuntime } from './openclaw/runtime.js';

const log = createLogger('sidecar');

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const port = parseInt(process.env.WEBSOCKET_PORT || '7847', 10);

let transcriberProcess: ChildProcess | null = null;
const openClawRuntime = new OpenClawRuntime();
let shuttingDown = false;
let openClawReloadInFlight = false;

const venvPython = path.join(os.homedir(), '.flux', 'transcriber-venv', 'bin', 'python3');
const hfHome = process.env.HF_HOME || path.join(os.homedir(), '.flux', 'hf');

if (fs.existsSync(venvPython)) {
  const serverScript = path.resolve(__dirname, '../../transcriber/server.py');
  transcriberProcess = spawn(venvPython, [serverScript], {
    stdio: ['ignore', 'pipe', 'pipe'],
    env: {
      ...process.env,
      HF_HOME: hfHome,
      HF_HUB_DISABLE_PROGRESS_BARS: '1',
      TOKENIZERS_PARALLELISM: 'false',
    },
  });

  transcriberProcess.stdout?.on('data', (data: Buffer) => {
    for (const line of data.toString().split('\n').filter(Boolean)) {
      log.info(`[transcriber] ${line}`);
    }
  });

  transcriberProcess.stderr?.on('data', (data: Buffer) => {
    for (const line of data.toString().split('\n').filter(Boolean)) {
      log.error(`[transcriber] ${line}`);
    }
  });

  transcriberProcess.on('close', (code) => {
    log.info(`transcriber process exited with code ${code}`);
    transcriberProcess = null;
  });
} else {
  log.warn(
    'Transcriber venv not found at ~/.flux/transcriber-venv — voice transcription unavailable. Run transcriber/setup.sh to set up.'
  );
}

const shutdown = () => {
  if (shuttingDown) return;
  shuttingDown = true;

  const finish = () => {
    process.exit(0);
  };

  if (transcriberProcess) {
    try {
      transcriberProcess.kill();
    } catch {
      // ignore
    }
    transcriberProcess = null;
  }

  void openClawRuntime
    .stop()
    .catch((error) => {
      log.warn(`failed to stop OpenClaw runtime: ${String(error)}`);
    })
    .finally(finish);

  setTimeout(finish, 4000).unref();
};

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

void openClawRuntime.start().catch((error) => {
  log.warn(`OpenClaw runtime failed to start: ${String(error)}`);
});

startBridgeWithOptions(port, {
  onReloadOpenClawRuntime: () => {
    if (openClawReloadInFlight) return;
    openClawReloadInFlight = true;
    log.info('Reloading OpenClaw runtime to apply channel/plugin changes...');
    void openClawRuntime
      .stop()
      .catch((error) => {
        log.warn(`Failed to stop OpenClaw during reload: ${String(error)}`);
      })
      .then(() => openClawRuntime.start())
      .catch((error) => {
        log.warn(`Failed to restart OpenClaw during reload: ${String(error)}`);
      })
      .finally(() => {
        openClawReloadInFlight = false;
      });
  },
});
