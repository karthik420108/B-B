'use strict';

/**
 * Demo document factory. Produces real files (a valid PDF with a text layer and
 * a raster PNG) so the seed exercises the actual extraction pipeline - the PDF
 * path via pdf-parse and the image path via tesseract.js OCR. Nothing here is a
 * mocked/fixed extraction response.
 */

const PDFDocument = require('pdfkit');
const { createCanvas } = require('@napi-rs/canvas');

/** Build a simple, valid one/two-column text PDF. */
function makePdf(title, lines) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 50 });
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
    doc.fontSize(16).text(title, { align: 'left' });
    doc.moveDown(0.5);
    doc.fontSize(11);
    lines.forEach((line) => {
      if (line === '') doc.moveDown(0.4);
      else doc.text(line);
    });
    doc.end();
  });
}

/** Render a "scanned" lab report as a PNG for the OCR path. */
function makeReportPng(title, lines, { width = 1200 } = {}) {
  const lineHeight = 44;
  const height = 110 + lines.length * lineHeight + 50;
  const canvas = createCanvas(width, height);
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, width, height);
  // Crisper type renders far better for tesseract (small thin text OCRs as
  // garbage - e.g. "HbA1c" -> "HbATC"), so use a large, legible font.
  ctx.fillStyle = '#0b2447';
  ctx.font = 'bold 34px Helvetica';
  ctx.fillText(title, 48, 72);
  ctx.fillStyle = '#111827';
  ctx.font = '30px Helvetica';
  let y = 130;
  for (const line of lines) {
    ctx.fillText(line, 48, y);
    y += lineHeight;
  }
  return canvas.toBuffer('image/png');
}

function makePlainText(lines) {
  return Buffer.from(lines.join('\n'), 'utf8');
}

module.exports = { makePdf, makeReportPng, makePlainText };
