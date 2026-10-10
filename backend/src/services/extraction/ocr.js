'use strict';

const fs = require('fs');
const config = require('../../config');
const logger = require('../../utils/logger');

/**
 * OCR adapter backed by tesseract.js (WASM). Runs fully locally - no cloud
 * service or system binary (e.g. `tesseract`) is required. Language data is
 * downloaded once into a cache directory and then reused offline.
 *
 * The worker is created lazily and reused across calls, then closed on idle to
 * release memory.
 */

let workerPromise = null;
let idleTimer = null;

async function getWorker() {
  if (!workerPromise) {
    fs.mkdirSync(config.ocr.cacheDir, { recursive: true });
    const { createWorker } = require('tesseract.js');
    workerPromise = createWorker(config.ocr.languages, undefined, {
      cachePath: config.ocr.cacheDir,
      logger: () => {},
    }).catch((err) => {
      workerPromise = null;
      throw err;
    });
  }
  return workerPromise;
}

function scheduleIdleStop() {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = setTimeout(async () => {
    if (workerPromise) {
      try {
        const w = await workerPromise;
        await w.terminate();
      } catch { /* ignore */ }
      workerPromise = null;
    }
  }, 60_000);
  if (idleTimer.unref) idleTimer.unref();
}

/**
 * Recognise text from an image buffer (PNG/JPEG).
 * @param {Buffer} buffer
 * @returns {Promise<{ text: string, confidence: number }>}
 */
async function recognizeImage(buffer) {
  const worker = await getWorker();
  const { data } = await worker.recognize(buffer);
  scheduleIdleStop();
  return { text: data.text || '', confidence: typeof data.confidence === 'number' ? data.confidence : null };
}

async function shutdown() {
  if (idleTimer) clearTimeout(idleTimer);
  if (workerPromise) {
    try { (await workerPromise).terminate(); } catch { /* ignore */ }
    workerPromise = null;
  }
}

async function isAvailable() {
  try {
    const { createWorker } = require('tesseract.js');
    return typeof createWorker === 'function';
  } catch (err) {
    logger.warn('OCR unavailable: %s', err.message);
    return false;
  }
}

module.exports = { recognizeImage, shutdown, isAvailable };
