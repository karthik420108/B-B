'use strict';

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const config = require('./config');
const routes = require('./routes');
const { apiLimiter } = require('./middleware/rateLimit');
const { errorHandler, notFoundHandler } = require('./middleware/errorHandler');
const logger = require('./utils/logger');

function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1);

  // Security headers. CSP left to the client host; API returns JSON only.
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));

  app.use(cors({
  origin: true, // allow any origin
  credentials: true,
  exposedHeaders: ['Content-Disposition'],
}));

  // Small body limit; uploads use multipart instead.
  app.use(express.json({ limit: '1mb' }));
  app.use(express.urlencoded({ extended: false, limit: '1mb' }));

  // Minimal request logging that never records bodies, query strings or tokens.
  app.use((req, res, next) => {
    const start = Date.now();
    res.on('finish', () => {
      logger.debug('%s %s -> %d (%dms)', req.method, req.path, res.statusCode, Date.now() - start);
    });
    next();
  });

  app.get('/', (req, res) => res.json({ success: true, data: { name: 'Health Wallet API', docs: '/api/meta/config' } }));

  app.use('/api', apiLimiter, routes);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}

module.exports = { createApp };
