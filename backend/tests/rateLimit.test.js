'use strict';

const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');
const config = require('../src/config');
const { apiLimiter, authLimiter, sensitiveLimiter } = require('../src/middleware/rateLimit');

before(h.connect);
after(h.disconnect);
beforeEach(h.clearDatabase);

/**
 * Rate limits are skipped while NODE_ENV=test so the rest of the suite stays
 * deterministic. These tests opt in explicitly and put the flag back after.
 */
function withLimits(fn) {
  const previous = config.isTest;
  config.isTest = false;
  return Promise.resolve()
    .then(fn)
    .finally(() => { config.isTest = previous; });
}

function makeReq({ ip = '198.51.100.7', user = null, url = '/api/documents' } = {}) {
  return { ip, ips: [], headers: {}, method: 'POST', url, originalUrl: url, socket: {}, user };
}

function makeRes() {
  const headers = new Map();
  const lower = (k) => String(k).toLowerCase();
  return {
    setHeader: (k, v) => headers.set(lower(k), v),
    getHeader: (k) => headers.get(lower(k)),
    removeHeader: (k) => headers.delete(lower(k)),
    _headers: headers,
  };
}

/** Run one request through a limiter; resolves to the error passed to next(), or null. */
function run(limiter, req) {
  return new Promise((resolve) => {
    limiter(req, makeRes(), (err) => resolve(err || null));
  });
}

/** Burn a bucket until it rejects. Returns the 429 error, or null if never limited. */
async function exhaust(limiter, req) {
  const cap = (limiter === authLimiter ? config.rateLimit.authMax : config.rateLimit.sensitiveMax) + 5;
  for (let i = 0; i < cap; i++) {
    const err = await run(limiter, req);
    if (err) return err;
  }
  return null;
}

test('credential and upload budgets are separate buckets', async () => {
  await withLimits(async () => {
    const ip = '198.51.100.11';

    const blocked = await exhaust(authLimiter, makeReq({ ip }));
    assert.ok(blocked, 'the credential bucket should reject once its budget is spent');
    assert.equal(blocked.status, 429);
    assert.equal(blocked.code, 'RATE_LIMITED');
    // Tell the caller when to come back instead of just "wait".
    assert.match(blocked.message, /Try again in \d+s\./);

    // Uploads, extraction, sharing and AI must be unaffected.
    assert.equal(await run(sensitiveLimiter, makeReq({ ip })), null,
      'spending the login budget must not block uploads');
    assert.equal(await run(apiLimiter, makeReq({ ip })), null);
  });
});

test('upload budget is scoped per account, not per address', async () => {
  await withLimits(async () => {
    const ip = '198.51.100.12';
    const alice = { _id: '6a11ce0000000000000000a1' };
    const bob = { _id: '6a11ce0000000000000000b2' };

    const blocked = await exhaust(sensitiveLimiter, makeReq({ ip, user: alice }));
    assert.ok(blocked, 'one account should be limited after enough uploads');

    // Same address, other signed-in account: untouched.
    assert.equal(await run(sensitiveLimiter, makeReq({ ip, user: bob })), null,
      'a second account behind the same address must keep its own budget');
    // Anonymous callers (e.g. share inspect before auth) key on the address alone.
    assert.equal(await run(sensitiveLimiter, makeReq({ ip })), null);
  });
});

test('different addresses get different budgets', async () => {
  await withLimits(async () => {
    const blocked = await exhaust(authLimiter, makeReq({ ip: '198.51.100.13' }));
    assert.ok(blocked);

    assert.equal(await run(authLimiter, makeReq({ ip: '198.51.100.14' })), null);
    assert.equal(await run(authLimiter, makeReq({ ip: '2001:db8::1' })), null);
  });
});

test('limits are configured from the environment', () => {
  assert.ok(config.rateLimit.authMax >= 1, 'credential budget must exist');
  assert.ok(config.rateLimit.sensitiveMax >= config.rateLimit.authMax,
    'uploads/AI get at least as much headroom as login');
  assert.ok(config.rateLimit.max > 0);
});
