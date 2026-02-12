import 'dotenv/config';
import { startBridge } from './bridge.js';
import { createLogger } from './logger.js';

const log = createLogger('sidecar');

const port = parseInt(process.env.WEBSOCKET_PORT || '7847', 10);

const shutdown = () => {
  process.exit(0);
};

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

log.info('Starting sidecar bridge (voice transcription handled in macOS app)');
startBridge(port);
