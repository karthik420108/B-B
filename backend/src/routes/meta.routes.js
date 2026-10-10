'use strict';

const express = require('express');
const mongoose = require('mongoose');
const config = require('../config');
const ai = require('../ai');
const ocr = require('../services/extraction/ocr');
const medicationSafetyService = require('../services/medicationSafetyService');
const { getStorage } = require('../storage');
const { asyncHandler, ok } = require('../utils/http');

const router = express.Router();

/** Liveness + integration status. Never exposes secrets. */
router.get('/health', asyncHandler(async (req, res) => {
  const dbState = mongoose.connection.readyState;
  const storage = getStorage();
  return ok(res, {
    status: 'ok',
    time: new Date().toISOString(),
    env: config.env,
    database: dbState === 1 ? 'connected' : 'disconnected',
  });
}));

/** Capability/config report so the client can show accurate, honest status. */
router.get('/config', asyncHandler(async (req, res) => {
  const storage = getStorage();
  return ok(res, {
    app: 'AI-Powered Personal Health Wallet',
    version: '1.0.0',
    ai: ai.describe(),
    ocr: {
      engine: 'tesseract.js (local WASM)',
      languages: config.ocr.languages,
      available: await ocr.isAvailable(),
    },
    storage: {
      driver: storage.name,
      available: storage.name === 'local' ? true : Boolean(storage.available),
      reason: storage.name === 'local' ? undefined : storage.reason,
    },
    medicationSafety: medicationSafetyService.datasetInfo(),
    limits: {
      maxUploadMB: Math.round(config.maxUploadBytes / (1024 * 1024)),
      shareMaxDays: 90,
    },
    demo: {
      seedCommand: 'npm run seed:reset',
    },
  });
}));

module.exports = router;
