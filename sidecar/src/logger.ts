type LogLevel = 'debug' | 'info' | 'warn' | 'error';

const LEVEL_ORDER: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

const minLevel: LogLevel = (process.env.FLUX_LOG_LEVEL as LogLevel) || 'debug';

function shouldLog(level: LogLevel): boolean {
  return LEVEL_ORDER[level] >= LEVEL_ORDER[minLevel];
}

function timestamp(): string {
  return new Date().toISOString();
}

export interface FluxLogger {
  debug: (...args: unknown[]) => void;
  info: (...args: unknown[]) => void;
  warn: (...args: unknown[]) => void;
  error: (...args: unknown[]) => void;
}

/**
 * Create a named logger for a sidecar module.
 *
 * Usage:
 *   const log = createLogger('bridge');
 *   log.info('WebSocket server listening on port', port);
 *   log.error('Failed to parse message:', error);
 *   log.debug('Session details:', session);  // only shown when FLUX_LOG_LEVEL=debug
 */
export function createLogger(module: string): FluxLogger {
  const prefix = `[${module}]`;

  return {
    debug: (...args: unknown[]) => {
      if (shouldLog('debug')) console.debug(timestamp(), prefix, ...args);
    },
    info: (...args: unknown[]) => {
      if (shouldLog('info')) console.log(timestamp(), prefix, ...args);
    },
    warn: (...args: unknown[]) => {
      if (shouldLog('warn')) console.warn(timestamp(), prefix, ...args);
    },
    error: (...args: unknown[]) => {
      if (shouldLog('error')) console.error(timestamp(), prefix, ...args);
    },
  };
}
