'use strict';

const path = require('path');
const logger = require('../../utils/logger');

/**
 * PDF processing.
 *
 * 1. Attempt to read the embedded text layer (fast path for digital PDFs).
 * 2. If the text layer is (near) empty - i.e. a scanned/image-only PDF - render
 *    each page to a raster image with pdf.js + @napi-rs/canvas and OCR it.
 *
 * Both steps run locally. A hard page cap protects against pathological files.
 */

const MAX_PAGES = 25;
const MIN_TEXT_CHARS = 40;

let pdfjsPromise = null;
function loadPdfjs() {
  if (!pdfjsPromise) {
    // pdfjs-dist v4 ships an ESM legacy build that runs in Node without a DOM.
    pdfjsPromise = import('pdfjs-dist/legacy/build/pdf.mjs');
  }
  return pdfjsPromise;
}

function standardFontPath() {
  try {
    const p = path.dirname(require.resolve('pdfjs-dist/package.json'));
    return path.join(p, 'standard_fonts') + path.sep;
  } catch {
    return undefined;
  }
}

function baseDocParams(buffer) {
  return {
    data: new Uint8Array(buffer),
    isEvalSupported: false,
    disableFontFace: true,
    standardFontDataUrl: standardFontPath(),
    useSystemFonts: true,
    verbosity: 0, // suppress internal pdf.js warnings
  };
}

/**
 * Read the embedded text layer using pdf.js (the same engine used for
 * rendering). Returns an empty string for image-only PDFs, which triggers the
 * OCR fallback.
 */
async function extractTextLayer(buffer) {
  const pdfjs = await loadPdfjs();
  const doc = await pdfjs.getDocument(baseDocParams(buffer)).promise;
  const pageCount = doc.numPages;
  let text = '';
  for (let i = 1; i <= pageCount; i += 1) {
    // eslint-disable-next-line no-await-in-loop
    const page = await doc.getPage(i);
    // eslint-disable-next-line no-await-in-loop
    const content = await page.getTextContent();
    // Reconstruct lines using pdf.js' own end-of-line markers where present.
    let pageText = '';
    for (const item of content.items) {
      if (typeof item.str === 'string') pageText += item.str;
      if (item.hasEOL) pageText += '\n';
    }
    text += `${pageText}\n`;
    page.cleanup();
  }
  await doc.destroy();
  return { text: text.trim(), pageCount };
}

async function renderPagesToImages(buffer) {
  const pdfjs = await loadPdfjs();
  const { createCanvas } = require('@napi-rs/canvas');
  const loadingTask = pdfjs.getDocument(baseDocParams(buffer));
  const doc = await loadingTask.promise;
  const pageCount = Math.min(doc.numPages, MAX_PAGES);
  const images = [];
  for (let i = 1; i <= pageCount; i += 1) {
    const page = await doc.getPage(i);
    const viewport = page.getViewport({ scale: 2.0 });
    const canvas = createCanvas(Math.ceil(viewport.width), Math.ceil(viewport.height));
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    await page.render({ canvasContext: ctx, viewport, canvas }).promise;
    images.push(canvas.toBuffer('image/png'));
    page.cleanup();
  }
  await doc.destroy();
  return { images, pageCount: doc.numPages };
}

/**
 * Extract text from a PDF buffer, falling back to per-page OCR.
 * @returns {Promise<{ text: string, source: 'pdf-text'|'ocr'|'none', pageCount: number, ocrConfidence: number|null, warnings: string[] }>}
 */
async function extractPdfText(buffer) {
  const warnings = [];
  let pageCount = 0;

  try {
    const layer = await extractTextLayer(buffer);
    pageCount = layer.pageCount;
    if (layer.text.length >= MIN_TEXT_CHARS) {
      return { text: layer.text, source: 'pdf-text', pageCount, ocrConfidence: null, warnings };
    }
    warnings.push('PDF has little or no embedded text - falling back to OCR.');
  } catch (err) {
    warnings.push(`PDF text layer could not be read (${err.message}); attempting OCR.`);
  }

  try {
    const { images, pageCount: pc } = await renderPagesToImages(buffer);
    if (pc > MAX_PAGES) warnings.push(`Only the first ${MAX_PAGES} of ${pc} pages were processed.`);
    const ocr = require('./ocr');
    const parts = [];
    let confSum = 0; let confN = 0;
    for (const img of images) {
      const res = await ocr.recognizeImage(img);
      parts.push(res.text);
      if (typeof res.confidence === 'number') { confSum += res.confidence; confN += 1; }
    }
    const text = parts.join('\n').trim();
    if (!text) warnings.push('OCR produced no text. The document may be too low quality to process.');
    return {
      text,
      source: text ? 'ocr' : 'none',
      pageCount: pc || pageCount,
      ocrConfidence: confN ? Math.round(confSum / confN) : null,
      warnings,
    };
  } catch (err) {
    logger.error('PDF OCR failed: %s', err.message);
    return { text: '', source: 'none', pageCount, ocrConfidence: null, warnings: [...warnings, `OCR failed: ${err.message}`] };
  }
}

/** Extract text from a standalone image buffer (uploaded photo/screenshot). */
async function extractImageText(buffer) {
  const ocr = require('./ocr');
  const res = await ocr.recognizeImage(buffer);
  const text = (res.text || '').trim();
  return {
    text,
    source: text ? 'ocr' : 'none',
    pageCount: 1,
    ocrConfidence: typeof res.confidence === 'number' ? Math.round(res.confidence) : null,
    warnings: text ? [] : ['OCR produced no text from the image.'],
  };
}

module.exports = { extractPdfText, extractImageText, extractTextLayer, renderPagesToImages, MAX_PAGES };
