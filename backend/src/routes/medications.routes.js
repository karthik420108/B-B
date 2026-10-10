'use strict';

const express = require('express');
const { z } = require('zod');
const medicationService = require('../services/medicationService');
const { authenticate, requireRole } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { asyncHandler, ok } = require('../utils/http');

const router = express.Router();

// Medication schedules are patient-owned. Doctors never get access here just
// because they can view shared records.
router.use(authenticate, requireRole('patient'));

const timeFormat = z.string().regex(/^([01]\d|2[0-3]):([0-5]\d)$/, 'Use 24-hour HH:mm');
const frequencyEnum = z.enum(['once_daily', 'twice_daily', 'three_times_daily', 'custom']);

const scheduleFields = {
  name: z.string().min(1, 'Medicine name is required.').max(160),
  strength: z.string().max(80).nullish(),
  doseInstructions: z.string().max(160).nullish(),
  route: z.string().max(40).nullish(),
  frequency: frequencyEnum.optional(),
  reminderTimes: z.array(timeFormat).min(1).max(8),
  weekdays: z.array(z.number().int().min(0).max(6)).max(7).nullish(),
  startDate: z.string().min(1),
  endDate: z.string().nullish(),
  timezone: z.string().max(64).optional(),
  instructions: z.string().max(400).nullish(),
  notes: z.string().max(1000).nullish(),
  clientRequestId: z.string().max(64).nullish(),
};

const createSchema = z.object(scheduleFields);

const updateSchema = z.object({
  name: scheduleFields.name.optional(),
  strength: scheduleFields.strength,
  doseInstructions: scheduleFields.doseInstructions,
  route: scheduleFields.route,
  frequency: frequencyEnum.optional(),
  reminderTimes: z.array(timeFormat).min(1).max(8).optional(),
  weekdays: scheduleFields.weekdays,
  startDate: z.string().min(1).optional(),
  endDate: scheduleFields.endDate,
  timezone: z.string().max(64).optional(),
  instructions: scheduleFields.instructions,
  notes: scheduleFields.notes,
});

const idParam = z.object({ id: z.string().min(1) });

// ---- Static routes first (must precede the /:id catch-all) -----------------

/** Today's doses in a requested timezone (defaults to UTC). */
router.get('/doses/today', asyncHandler(async (req, res) => {
  const tz = typeof req.query.tz === 'string' ? req.query.tz : undefined;
  return ok(res, await medicationService.todayDoses(req.user._id, { tz }));
}));

/** Dose occurrences in an explicit range. */
router.get('/doses', validate({ query: z.object({ from: z.string().optional(), to: z.string().optional(), tz: z.string().optional() }) }),
  asyncHandler(async (req, res) => ok(res, await medicationService.dosesInRange(req.user._id, req.validatedQuery))));

/** Next scheduled doses across active schedules (deduplicated). */
router.get('/doses/upcoming', asyncHandler(async (req, res) => {
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit || '20', 10) || 20));
  return ok(res, await medicationService.upcomingDoses(req.user._id, { limit }));
}));

/** Medication history (Taken / Skipped / Missed). */
router.get('/history', validate({ query: z.object({
  from: z.string().optional(), to: z.string().optional(),
  page: z.string().optional(), limit: z.string().optional(),
}) }), asyncHandler(async (req, res) => ok(res, await medicationService.getHistory(req.user._id, req.validatedQuery))));

/** Extract (but never persist) candidate medication details from a prescription. */
router.post('/extract', validate({ body: z.object({ documentId: z.string().min(1) }) }),
  asyncHandler(async (req, res) => ok(res, await medicationService.extractFromDocument(req.user._id, req.body.documentId, { req }))));

/** Confirm reviewed extraction and create the schedule + occurrences. */
router.post('/confirm', validate({ body: z.object({
  documentId: z.string().min(1),
  confirmed: z.literal(true),
  snippet: z.string().max(2000).nullish(),
  clientRequestId: z.string().max(64).nullish(),
  medication: z.object({
    name: z.string().min(1, 'Medicine name is required.').max(160),
    strength: z.string().max(80).nullish(),
    doseInstructions: z.string().max(160).nullish(),
    route: z.string().max(40).nullish(),
    frequency: frequencyEnum.optional(),
    reminderTimes: z.array(timeFormat).min(1).max(8),
    weekdays: z.array(z.number().int().min(0).max(6)).max(7).nullish(),
    startDate: z.string().min(1),
    endDate: z.string().nullish(),
    timezone: z.string().max(64).optional(),
    instructions: z.string().max(400).nullish(),
    notes: z.string().max(1000).nullish(),
  }),
}) }), asyncHandler(async (req, res) => {
  const result = await medicationService.confirmExtraction(req.user._id, req.body, { req });
  return res.status(201).json({ success: true, data: result });
}));

// ---- Schedule collection ---------------------------------------------------

router.get('/', validate({ query: z.object({ status: z.enum(['ACTIVE', 'PAUSED', 'COMPLETED', 'DISCONTINUED']).optional() }) }),
  asyncHandler(async (req, res) => ok(res, await medicationService.listSchedules(req.user._id, req.validatedQuery))));

router.post('/', validate({ body: createSchema }), asyncHandler(async (req, res) => {
  const result = await medicationService.createSchedule(req.user._id, req.body, { req });
  return res.status(201).json({ success: true, data: result });
}));

// ---- Dose action (must precede /:id) ---------------------------------------

router.post('/doses/:id/action', validate({
  params: idParam,
  body: z.object({ action: z.enum(['TAKEN', 'SKIPPED']), note: z.string().max(300).nullish() }),
}), asyncHandler(async (req, res) => {
  const result = await medicationService.recordDoseAction(req.user._id, req.params.id, req.body.action, { note: req.body.note, req });
  return ok(res, result);
}));

// ---- Schedule-scoped routes ------------------------------------------------

router.get('/:id', validate({ params: idParam }), asyncHandler(async (req, res) => ok(res, await medicationService.getSchedule(req.user._id, req.params.id))));

router.patch('/:id', validate({ params: idParam, body: updateSchema }), asyncHandler(async (req, res) => ok(res, await medicationService.updateSchedule(req.user._id, req.params.id, req.body, { req }))));

router.post('/:id/pause', validate({ params: idParam }), asyncHandler(async (req, res) => ok(res, await medicationService.setStatus(req.user._id, req.params.id, 'pause', { req }))));
router.post('/:id/resume', validate({ params: idParam, body: z.object({ confirmReopen: z.boolean().optional() }).optional() }), asyncHandler(async (req, res) => ok(res, await medicationService.setStatus(req.user._id, req.params.id, 'resume', { req, confirmReopen: Boolean(req.body && req.body.confirmReopen) }))));
router.post('/:id/discontinue', validate({ params: idParam }), asyncHandler(async (req, res) => ok(res, await medicationService.setStatus(req.user._id, req.params.id, 'discontinue', { req }))));

module.exports = router;
