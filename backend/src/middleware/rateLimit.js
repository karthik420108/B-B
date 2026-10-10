'use strict';

const rateLimit = require('express-rate-limit');
const config = require('../config');
const { tooMany } = require('../utils/errors');

function build({ max, windowMs, message }) {
  return rateLimit({
    windowMs,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    // In tests, don't rate-limit so suites stay deterministic.
    skip: () => config.isTest,
    handler: (req, res, next) => next(tooMany(message)),
    keyGenerator: (req) => req.ip,
  });
}

/** Broad limiter applied to the whole API. */
const apiLimiter = build({
  max: config.rateLimit.max,
  windowMs: config.rateLimit.windowMs,
  message: 'Too many requests. Please slow down.',
});

/** Tighter limiter for sensitive endpoints (auth, sharing, AI queries). */
const sensitiveLimiter = build({
  max: config.rateLimit.sensitiveMax,
  windowMs: config.rateLimit.windowMs,
  message: 'Too many attempts on a sensitive endpoint. Please wait and try again.',
});

module.exports = { apiLimiter, sensitiveLimiter, build };
