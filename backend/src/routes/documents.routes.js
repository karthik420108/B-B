'use strict';

const express = require('express');
const { z } = require('zod');
const documentsService = require('../services/documentsService');
const extractionService = require('../services/extractionService');
const { Document } = require('../models');
const { authenticate, requireRole } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { singleFile } = require('../middleware/upload');
const { sensitiveLimiter } = require('../middleware/rateLimit');
const { asyncHandler, ok, paginated, parsePagination } = require('../utils/http');
const { notFound } = require('../utils/errors');

const router = express.Router();
router.use(authenticate, requireRole('patient'));

/**
 * Upload a document. Multipart form field `file` plus optional metadata.
 * Extraction runs inline by default so callers immediately receive structured
 * data; pass `extract=false` to defer.
 */
router.post('/', sensitiveLimiter, singleFile('file'), asyncHandler(async (req, res) => {
  const meta = {
    originalName: req.body.originalName,
    category: req.body.category,
    providerName: req.body.providerName,
    provider: req.body.provider,
    eventDate: req.body.eventDate,
    eventDateEstimated: req.body.eventDateEstimated === 'true',
    source: req.body.source,
    notes: req.body.notes,
    manual: req.body.manual === 'true',
    tags: req.body.tags ? String(req.body.tags).split(',').map((s) => s.trim()).filter(Boolean) : [],
  };
  const result = await documentsService.createDocument(req.user, req.file, meta, { req, extract: req.body.extract !== 'false' });
  return res.status(201).json({ success: true, data: result });
}));

router.get('/', asyncHandler(async (req, res) => {
  const { items, total, page, limit } = await documentsService.listDocuments(req.user._id, req.query);
  return paginated(res, items, total, { page, limit });
}));

router.get('/categories', asyncHandler(async (req, res) => {
  const { DOCUMENT_CATEGORIES } = require('../models/Document');
  return ok(res, DOCUMENT_CATEGORIES);
}));

router.get('/:id', asyncHandler(async (req, res) => {
  const doc = await documentsService.getDocument(req.user._id, req.params.id, { includeText: req.query.includeText === 'true' });
  const data = doc.toClient();
  if (req.query.includeText === 'true') data.rawText = doc.rawText;
  // Include extracted child resources so the review screen can show fields.
  const { Observation, Condition, AllergyIntolerance, MedicationStatement, Encounter } = require('../models');
  const [observations, conditions, allergies, medications, encounters] = await Promise.all([
    Observation.find({ sourceDocument: doc._id, deletedAt: null }).lean(),
    Condition.find({ sourceDocument: doc._id, deletedAt: null }).lean(),
    AllergyIntolerance.find({ sourceDocument: doc._id, deletedAt: null }).lean(),
    MedicationStatement.find({ sourceDocument: doc._id, deletedAt: null }).lean(),
    Encounter.find({ sourceDocument: doc._id, deletedAt: null }).lean(),
  ]);
  data.extracted = { observations, conditions, allergies, medications, encounters };
  return ok(res, data);
}));

router.get('/:id/file', asyncHandler(async (req, res) => {
  const { doc, buffer } = await documentsService.readDocumentFile(req.user._id, req.params.id);
  res.setHeader('Content-Type', doc.mimeType);
  res.setHeader('Content-Disposition', `inline; filename="${encodeURIComponent(doc.originalName)}"`);
  res.setHeader('Cache-Control', 'private, no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  return res.send(buffer);
}));

router.patch('/:id', validate({ body: z.object({
  originalName: z.string().min(1).max(250).optional(),
  category: z.string().optional(),
  eventDate: z.string().nullable().optional(),
  eventDateEstimated: z.boolean().optional(),
  providerName: z.string().max(160).optional(),
  tags: z.array(z.string().max(40)).max(20).optional(),
  notes: z.string().max(2000).optional(),
}) }), asyncHandler(async (req, res) => ok(res, await documentsService.updateDocument(req.user._id, req.params.id, req.body, { req }))));

router.delete('/:id', asyncHandler(async (req, res) => ok(res, await documentsService.deleteDocument(req.user._id, req.params.id, { req }))));

/** Retry extraction for a failed document (clears prior auto-extracted children). */
router.post('/:id/extract', sensitiveLimiter, validate({ body: z.object({ force: z.boolean().optional() }).optional() }), asyncHandler(async (req, res) => {
  const doc = await Document.findOne({ _id: req.params.id, patient: req.user._id, deletedAt: null });
  if (!doc) throw notFound('Document not found');
  doc.extractionStatus = 'pending';
  await doc.save();
  const result = await extractionService.runExtraction(doc._id, { force: true, req });
  return ok(res, result);
}));

module.exports = router;
