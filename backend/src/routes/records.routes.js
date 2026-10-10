'use strict';

const express = require('express');
const { z } = require('zod');
const recordsService = require('../services/recordsService');
const duplicateTestService = require('../services/duplicateTestService');
const medicationSafetyService = require('../services/medicationSafetyService');
const { authenticate, requireRole } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { asyncHandler, ok, paginated } = require('../utils/http');

const router = express.Router();
router.use(authenticate, requireRole('patient'));

// ---- Unified timeline -----------------------------------------------------
router.get('/timeline', asyncHandler(async (req, res) => ok(res, await recordsService.buildTimeline(req.user._id, req.query))));

// ---- Search ---------------------------------------------------------------
router.get('/search', asyncHandler(async (req, res) => ok(res, await recordsService.search(req.user._id, req.query.q, { limit: 40 }))));

// ---- Resource lists -------------------------------------------------------
router.get('/observations', asyncHandler(async (req, res) => {
  const { items, total, page, limit } = await recordsService.listObservations(req.user._id, req.query);
  return paginated(res, items, total, { page, limit });
}));
router.get('/conditions', asyncHandler(async (req, res) => ok(res, await recordsService.listConditions(req.user._id, req.query))));
router.get('/allergies', asyncHandler(async (req, res) => ok(res, await recordsService.listAllergies(req.user._id, req.query))));
router.get('/medications', asyncHandler(async (req, res) => ok(res, await recordsService.listMedications(req.user._id, req.query))));
router.get('/encounters', asyncHandler(async (req, res) => ok(res, await recordsService.listEncounters(req.user._id, req.query))));

// ---- Manual entry ---------------------------------------------------------
router.post('/manual', validate({ body: z.object({
  kind: z.enum(['observation', 'condition', 'allergy', 'medication', 'encounter']),
  data: z.object({
    testName: z.string().max(120).optional(),
    name: z.string().max(160).optional(),
    substance: z.string().max(120).optional(),
    value: z.number().nullable().optional(),
    valueString: z.string().max(120).optional(),
    unit: z.string().max(40).optional(),
    referenceRange: z.string().max(80).optional(),
    reaction: z.string().max(200).optional(),
    severity: z.enum(['mild', 'moderate', 'severe', 'unknown']).optional(),
    status: z.string().max(40).optional(),
    strength: z.string().max(60).optional(),
    dose: z.string().max(60).optional(),
    frequency: z.string().max(60).optional(),
    route: z.string().max(40).optional(),
    form: z.string().max(40).optional(),
    genericName: z.string().max(120).optional(),
    prescriber: z.string().max(120).optional(),
    reason: z.string().max(200).optional(),
    diagnosis: z.array(z.string().max(160)).max(20).optional(),
    type: z.string().max(40).optional(),
    date: z.string().optional(),
    onsetDate: z.string().optional(),
    startDate: z.string().optional(),
    providerName: z.string().max(160).optional(),
  }),
}) }), asyncHandler(async (req, res) => {
    const result = await recordsService.addManualRecord(req.user._id, req.body, { req });
    return res.status(201).json({ success: true, data: result });
  }));

// ---- Verification / correction -------------------------------------------
router.patch('/:kind/:id/verify', validate({ params: z.object({ kind: z.enum(['observation', 'condition', 'allergy', 'medication', 'encounter']), id: z.string().min(1) }), body: z.object({
  verification: z.enum(['unverified', 'verified', 'rejected']),
  corrections: z.record(z.any()).optional(),
}) }), asyncHandler(async (req, res) => ok(res, await recordsService.verifyRecord(req.user._id, req.params.kind, req.params.id, req.body, { req }))));

// ---- Charts ---------------------------------------------------------------
router.get('/charts', asyncHandler(async (req, res) => ok(res, await recordsService.chartSeries(req.user._id, { testName: req.query.testName }))));

// ---- Duplicate test detection --------------------------------------------
router.get('/duplicates/tests', asyncHandler(async (req, res) => {
  const windowDays = Math.min(365, Math.max(1, parseInt(req.query.windowDays || '180', 10) || 180));
  return ok(res, await duplicateTestService.detectRepeatedTests(req.user._id, { windowDays }));
}));
router.get('/duplicates/documents', asyncHandler(async (req, res) => ok(res, await duplicateTestService.detectDuplicateDocuments(req.user._id))));

// ---- Medication safety ----------------------------------------------------
router.get('/medications/safety', asyncHandler(async (req, res) => ok(res, await medicationSafetyService.report(req.user._id))));

module.exports = router;
