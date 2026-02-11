import 'dotenv/config';
import { spawn, ChildProcess } from 'child_process';
import path from 'path';
import fs from 'fs';
import os from 'os';
import { fileURLToPath } from 'url';
import { startBridge } from './bridge.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const port = parseInt(process.env.WEBSOCKET_PORT || '7847', 10);

let transcriberProcess: ChildProcess | null = null;

const venvPython = path.join(os.homedir(), '.flux', 'transcriber-venv', 'bin', 'python3');

if (fs.existsSync(venvPython)) {
  const serverScript = path.resolve(__dirname, '../../transcriber/server.py');
  transcriberProcess = spawn(venvPython, [serverScript], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  transcriberProcess.stdout?.on('data', (data: Buffer) => {
    for (const line of data.toString().split('\n').filter(Boolean)) {
      console.log(`[transcriber] ${line}`);
    }
  });

  transcriberProcess.stderr?.on('data', (data: Buffer) => {
    for (const line of data.toString().split('\n').filter(Boolean)) {
      console.error(`[transcriber] ${line}`);
    }
  });

  transcriberProcess.on('close', (code) => {
    console.log(`[transcriber] process exited with code ${code}`);
    transcriberProcess = null;
  });
} else {
  console.log(
    '[sidecar] Transcriber venv not found at ~/.flux/transcriber-venv — voice transcription unavailable. Run transcriber/setup.sh to set up.'
  );
}

const shutdown = () => {
  if (transcriberProcess) {
    transcriberProcess.kill();
    transcriberProcess = null;
  }
  process.exit(0);
};

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

startBridge(port);
