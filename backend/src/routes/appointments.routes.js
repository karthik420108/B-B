'use strict';

const express = require('express');
const { z } = require('zod');
const { Appointment } = require('../models');
const { authenticate, requireRole } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { asyncHandler, ok } = require('../utils/http');
const { notFound } = require('../utils/errors');
const auditService = require('../services/auditService');

const router = express.Router();
router.use(authenticate, requireRole('patient'));

router.get('/', asyncHandler(async (req, res) => {
  const items = await Appointment.find({ patient: req.user._id }).sort({ dateTime: -1 }).limit(200).lean();
  return ok(res, items);
}));

router.post('/', validate({ body: z.object({
  title: z.string().max(160).optional(),
  providerName: z.string().max(160).optional(),
  dateTime: z.string().min(4),
  reason: z.string().max(300).optional(),
  reminder: z.boolean().optional(),
  reminderMinutesBefore: z.number().int().min(0).max(10080).optional(),
}) }), asyncHandler(async (req, res) => {
  const appt = await Appointment.create({
    patient: req.user._id,
    title: req.body.title,
    providerName: req.body.providerName,
    dateTime: new Date(req.body.dateTime),
    reason: req.body.reason,
    reminder: Boolean(req.body.reminder),
    reminderMinutesBefore: req.body.reminderMinutesBefore ?? 60,
  });
  await auditService.record(req, { action: 'appointment.created', patient: req.user._id, entityType: 'Appointment', entityId: appt._id });
  return res.status(201).json({ success: true, data: appt });
}));

router.patch('/:id', validate({ body: z.object({
  title: z.string().max(160).optional(),
  providerName: z.string().max(160).optional(),
  dateTime: z.string().optional(),
  status: z.enum(['scheduled', 'completed', 'cancelled']).optional(),
  reason: z.string().max(300).optional(),
  reminder: z.boolean().optional(),
}) }), asyncHandler(async (req, res) => {
  const appt = await Appointment.findOne({ _id: req.params.id, patient: req.user._id });
  if (!appt) throw notFound('Appointment not found');
  Object.assign(appt, {
    ...(req.body.title !== undefined ? { title: req.body.title } : {}),
    ...(req.body.providerName !== undefined ? { providerName: req.body.providerName } : {}),
    ...(req.body.dateTime !== undefined ? { dateTime: new Date(req.body.dateTime) } : {}),
    ...(req.body.status !== undefined ? { status: req.body.status } : {}),
    ...(req.body.reason !== undefined ? { reason: req.body.reason } : {}),
    ...(req.body.reminder !== undefined ? { reminder: req.body.reminder } : {}),
  });
  await appt.save();
  return ok(res, appt);
}));

router.delete('/:id', asyncHandler(async (req, res) => {
  const result = await Appointment.deleteOne({ _id: req.params.id, patient: req.user._id });
  if (!result.deletedCount) throw notFound('Appointment not found');
  return ok(res, { ok: true });
}));

module.exports = router;
