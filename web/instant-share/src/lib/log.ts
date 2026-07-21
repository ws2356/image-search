const PREFIX = '[IS]';

export const log = {
  debug: (msg: string, ...args: unknown[]) => {
    if (typeof process !== 'undefined' && process.env.NODE_ENV === 'test') return;
    console.debug(PREFIX, msg, ...args);
  },
  info: (msg: string, ...args: unknown[]) => {
    if (typeof process !== 'undefined' && process.env.NODE_ENV === 'test') return;
    console.info(PREFIX, msg, ...args);
  },
  warn: (msg: string, ...args: unknown[]) => {
    if (typeof process !== 'undefined' && process.env.NODE_ENV === 'test') return;
    console.warn(PREFIX, msg, ...args);
  },
  error: (msg: string, ...args: unknown[]) => {
    if (typeof process !== 'undefined' && process.env.NODE_ENV === 'test') return;
    console.error(PREFIX, msg, ...args);
  },
};
