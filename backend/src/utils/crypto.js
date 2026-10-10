'use strict';
const crypto = require('crypto');

const ID_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/** Cryptographically random URL-safe token. */
function randomToken(bytes = 32) {
  return crypto.randomBytes(bytes).toString('base64url');
}

/** SHA-256 hash of a token, hex encoded. Used so raw tokens are never stored. */
function hashToken(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

/** SHA-256 of arbitrary content (used for file dedupe + audit IPs). */
function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

/** Constant-time string comparison. */
function safeEqual(a, b) {
  const ab = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ab.length !== bb.length) return false;
  return crypto.timingSafeEqual(ab, bb);
}

/** ULID-like sortable id (time + randomness), no external dependency. */
function ulid() {
  const time = Date.now();
  let ts = '';
  let t = time;
  for (let i = 0; i < 10; i += 1) {
    ts = ID_ALPHABET[t % 32] + ts;
    t = Math.floor(t / 32);
  }
  const rand = crypto.randomBytes(16);
  let out = '';
  for (let i = 0; i < 16; i += 1) out += ID_ALPHABET[rand[i] % 32];
  return ts + out;
}

/** Hash an IP for audit logging without storing the raw address. */
function hashIp(ip) {
  if (!ip) return null;
  return sha256(`health-wallet:${ip}`).slice(0, 32);
}

module.exports = { randomToken, hashToken, sha256, safeEqual, ulid, hashIp };
