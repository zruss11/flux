import 'dotenv/config';
import { startBridge } from './bridge.js';

const port = parseInt(process.env.WEBSOCKET_PORT || '7847', 10);
startBridge(port);
