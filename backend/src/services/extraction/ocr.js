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

/**
 * Drop the current worker and terminate it in the background. Used both on idle
 * and after a worker-level error so the next call starts from a clean worker.
 */
function resetWorker() {
  const pending = workerPromise;
  workerPromise = null;
  if (pending) {
    pending.then((w) => w.terminate()).catch(() => { /* ignore */ });
  }
}

async function getWorker() {
  if (!workerPromise) {
    fs.mkdirSync(config.ocr.cacheDir, { recursive: true });
    const { createWorker } = require('tesseract.js');
    workerPromise = createWorker(config.ocr.languages, undefined, {
      cachePath: config.ocr.cacheDir,
      logger: () => {},
      // tesseract.js re-throws worker errors asynchronously when no errorHandler
      // is supplied, which surfaces as an uncaught exception and takes the whole
      // process down (e.g. an unreadable/corrupt image). Swallow it here: the
      // individual recognize() call still rejects and is handled by the caller.
      errorHandler: (err) => {
        logger.warn('OCR worker error: %s', err && err.message ? err.message : err);
        resetWorker();
      },
    }).catch((err) => {
      workerPromise = null;
      throw err;
    });
  }
  return workerPromise;
}

function scheduleIdleStop() {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = setTimeout(() => {
    resetWorker();
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
