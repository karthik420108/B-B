'use strict';

const rateLimit = require('express-rate-limit');
const config = require('../config');
const { tooMany } = require('../utils/errors');

/** Tell the caller how long they must wait, so clients can show a useful message. */
function withRetryHint(req, message) {
  const reset = req.rateLimit && req.rateLimit.resetTime;
  if (!reset) return message;
  const seconds = Math.max(1, Math.ceil((new Date(reset).getTime() - Date.now()) / 1000));
  return `${message} Try again in ${seconds}s.`;
}

/**
 * Build a limiter.
 *
 * Every call creates its own in-memory store, so each limiter owns a separate
 * bucket. That matters: a single shared bucket let a burst of uploads exhaust
 * the login budget too (they all counted against the same 20 requests).
 *
 * `keyByUser` additionally scopes the bucket to the signed-in account on top of
 * the IP, so two users behind one address - or one user in two tabs - do not
 * starve each other.
 */
function build({ max, windowMs, message, keyByUser = false }) {
  return rateLimit({
    windowMs,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    // In tests, don't rate-limit so suites stay deterministic.
    skip: () => config.isTest,
    handler: (req, res, next) => next(tooMany(withRetryHint(req, message))),
    keyGenerator: (req) => {
      const ip = req.ip;
      if (keyByUser && req.user && req.user._id) return `${ip}|${req.user._id}`;
      return ip;
    },
  });
}

/** Broad limiter applied to the whole API. */
const apiLimiter = build({
  max: config.rateLimit.max,
  windowMs: config.rateLimit.windowMs,
  message: 'Too many requests. Please slow down.',
});

/**
 * Credential endpoints (login, register, password reset, token refresh).
 * Kept strict and keyed by IP alone: these are the brute-force target, so they
 * must not get looser just because uploads are more generous.
 */
const authLimiter = build({
  max: config.rateLimit.authMax,
  windowMs: config.rateLimit.windowMs,
  message: 'Too many attempts on a sensitive endpoint. Please wait and try again.',
});

/**
 * Costly but non-credential endpoints (upload, extraction, sharing, AI).
 * More headroom because normal use - upload a few files, ask a few questions,
 * create a share - legitimately spends a lot of them.
 */
const sensitiveLimiter = build({
  max: config.rateLimit.sensitiveMax,
  windowMs: config.rateLimit.windowMs,
  message: 'Too many attempts on a sensitive endpoint. Please wait and try again.',
  keyByUser: true,
});

module.exports = { apiLimiter, authLimiter, sensitiveLimiter, build };
