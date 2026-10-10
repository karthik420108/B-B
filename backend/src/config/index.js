'use strict';
const path = require('path');
const dotenv = require('dotenv');

dotenv.config({ path: path.resolve(__dirname, '../../.env') });

function bool(value, fallback = false) {
  if (value === undefined || value === '') return fallback;
  return String(value).toLowerCase() === 'true' || value === '1';
}

const config = {
  env: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT || '4000', 10),
  mongoUri: process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/health_wallet',
  publicBaseUrl: (process.env.PUBLIC_BASE_URL || 'http://localhost:4000').replace(/\/$/, ''),
  corsOrigins: (process.env.CORS_ORIGINS || 'http://localhost:5173,http://localhost:8080,http://localhost:3000')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean),
  jwt: {
    accessSecret: process.env.JWT_ACCESS_SECRET || 'dev-access-secret-change-me',
    refreshSecret: process.env.JWT_REFRESH_SECRET || 'dev-refresh-secret-change-me',
    accessTtl: process.env.JWT_ACCESS_TTL || '15m',
    refreshTtl: process.env.JWT_REFRESH_TTL || '7d',
  },
  storage: {
    driver: process.env.STORAGE_DRIVER || 'local',
    localDir: path.resolve(__dirname, '../..', process.env.STORAGE_LOCAL_DIR || './uploads'),
    s3: {
      bucket: process.env.S3_BUCKET || '',
      region: process.env.S3_REGION || '',
      accessKeyId: process.env.S3_ACCESS_KEY_ID || '',
      secretAccessKey: process.env.S3_SECRET_ACCESS_KEY || '',
      endpoint: process.env.S3_ENDPOINT || '',
    },
  },
  ai: {
    provider: (process.env.AI_PROVIDER || 'local').toLowerCase(),
    allowExternal: bool(process.env.AI_ALLOW_EXTERNAL_DATA_TRANSFER, false),
    openai: {
      apiKey: process.env.OPENAI_API_KEY || '',
      model: process.env.OPENAI_MODEL || 'gpt-4o-mini',
      baseUrl: (process.env.OPENAI_BASE_URL || 'https://api.openai.com/v1').replace(/\/$/, ''),
    },
    anthropic: {
      apiKey: process.env.ANTHROPIC_API_KEY || '',
      model: process.env.ANTHROPIC_MODEL || 'claude-3-5-sonnet-latest',
      baseUrl: 'https://api.anthropic.com',
    },
  },
  ocr: {
    languages: process.env.OCR_LANGUAGES || 'eng',
    cacheDir: path.resolve(__dirname, '../..', process.env.OCR_CACHE_DIR || './.ocr-cache'),
  },
  maxUploadBytes: parseInt(process.env.MAX_UPLOAD_MB || '25', 10) * 1024 * 1024,
  medication: {
    /** How long after a dose's scheduled time it can still be marked Taken/Skipped. */
    trackingWindowMinutes: parseInt(process.env.MED_TRACKING_WINDOW_MINUTES || '180', 10),
    /** How early a dose is surfaced as "Due" before its scheduled time. */
    dueWindowMinutes: parseInt(process.env.MED_DUE_WINDOW_MINUTES || '15', 10),
    /** Rolling window of future occurrences generated/maintained per schedule. */
    horizonDays: parseInt(process.env.MED_HORIZON_DAYS || '30', 10),
  },
  interactionDataset: process.env.INTERACTION_DATASET === ''
    ? ''
    : path.resolve(__dirname, '../..', process.env.INTERACTION_DATASET || './data/interactions.json'),
  rateLimit: {
    windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000', 10),
    max: parseInt(process.env.RATE_LIMIT_MAX || '300', 10),
    /** Login / register / password reset / token refresh - strict, brute-force surface. */
    authMax: parseInt(process.env.AUTH_RATE_LIMIT_MAX || '20', 10),
    /** Uploads, extraction, sharing and AI - normal use spends a lot of these. */
    sensitiveMax: parseInt(process.env.SENSITIVE_RATE_LIMIT_MAX || '100', 10),
  },
  isTest: process.env.NODE_ENV === 'test',
};

module.exports = config;
