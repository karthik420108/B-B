'use strict';

/**
 * Minimal structured logger.
 *
 * SECURITY: this logger must never receive medical content, document text,
 * patient identifiers or access tokens. Callers pass only short, non-sensitive
 * messages and scalar diagnostics.
 */

const LEVELS = { error: 0, warn: 1, info: 2, debug: 3 };
const threshold = LEVELS[process.env.LOG_LEVEL || (process.env.NODE_ENV === 'test' ? 'error' : 'info')] ?? 2;

function fmt(level, args) {
  const ts = new Date().toISOString();
  const [msg, ...rest] = args;
  let rendered = msg;
  if (typeof msg === 'string' && rest.length) {
    let i = 0;
    rendered = msg.replace(/%s/g, () => (rest[i] !== undefined ? String(rest[i++]) : '%s'));
    if (i < rest.length) rendered += ` ${rest.slice(i).map((r) => (typeof r === 'object' ? JSON.stringify(r) : String(r))).join(' ')}`;
  }
  return `${ts} [${level}] ${rendered}`;
}

const logger = {
  error: (...a) => { if (threshold >= 0) console.error(fmt('error', a)); },
  warn: (...a) => { if (threshold >= 1) console.warn(fmt('warn', a)); },
  info: (...a) => { if (threshold >= 2) console.log(fmt('info', a)); },
  debug: (...a) => { if (threshold >= 3) console.log(fmt('debug', a)); },
};

module.exports = logger;
