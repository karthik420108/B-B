'use strict';

const config = require('./config');
const { createApp } = require('./app');
const db = require('./config/db');
const ai = require('./ai');
const logger = require('./utils/logger');

async function main() {
  await db.connect();
  const app = createApp();

  const server = app.listen(config.port, () => {
    const aiInfo = ai.describe();
    logger.info('Health Wallet API listening on http://localhost:%d', config.port);
    logger.info('AI provider: %s (%s)%s', aiInfo.active, aiInfo.model, aiInfo.external ? ' [EXTERNAL]' : ' [offline]');
    if (aiInfo.fallbackReason) logger.warn(aiInfo.fallbackReason);
    logger.info('Storage driver: %s', config.storage.driver);
  });

  const shutdown = async (signal) => {
    logger.info('%s received, shutting down', signal);
    server.close(async () => {
      try {
        const ocr = require('./services/extraction/ocr');
        await ocr.shutdown();
      } catch { /* ignore */ }
      await db.disconnect();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10000).unref();
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

if (require.main === module) {
  main().catch((err) => {
    logger.error('Fatal startup error: %s', err.message);
    process.exit(1);
  });
}

module.exports = { main };
