import 'dotenv/config';
import { startBridge, shutdownBridge } from './bridge.js';
import { createLogger } from './logger.js';

const log = createLogger('sidecar');

const port = parseInt(process.env.WEBSOCKET_PORT || '7847', 10);

let shuttingDown = false;

const shutdown = async (signal?: string) => {
  if (shuttingDown) return;
  shuttingDown = true;

  if (signal) log.info(`Received ${signal}, shutting down...`);

  try {
    await shutdownBridge();
  } catch (err) {
    log.error('Error during bridge shutdown:', err);
  }

  process.exit(0);
};

process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('SIGTERM', () => void shutdown('SIGTERM'));

process.on('uncaughtException', (err) => {
  log.error('Uncaught exception:', err);
  void shutdown('uncaughtException');
});

process.on('unhandledRejection', (reason) => {
  log.error('Unhandled rejection:', reason);
  void shutdown('unhandledRejection');
});

log.info('Starting sidecar bridge (voice transcription handled in macOS app)');
startBridge(port);
