'use strict';

const express = require('express');
const { z } = require('zod');
const shareService = require('../services/shareService');
const documentsService = require('../services/documentsService');
const aiService = require('../services/aiService');
const { User, DoctorProfile, Document, ShareGrant } = require('../models');
const { authenticate, requireRole, requireVerifiedDoctor } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { sensitiveLimiter } = require('../middleware/rateLimit');
const { asyncHandler, ok } = require('../utils/http');
const { forbidden, notFound } = require('../utils/errors');
const auditService = require('../services/auditService');

const router = express.Router();
router.use(authenticate);

/** Directory of doctor accounts (for the patient share UI). Any signed-in user. */
router.get('/directory', asyncHandler(async (req, res) => {
  const doctors = await User.find({ role: 'doctor', status: 'active' }).select('name email').limit(100);
  const profiles = await DoctorProfile.find({ user: { $in: doctors.map((d) => d._id) } });
  const byUser = new Map(profiles.map((p) => [String(p.user), p]));
  return ok(res, doctors.map((d) => ({
    id: String(d._id),
    name: d.name,
    email: d.email,
    specialty: byUser.get(String(d._id))?.specialty || null,
    clinicName: byUser.get(String(d._id))?.clinicName || null,
    verification: byUser.get(String(d._id))?.verification?.status || 'unverified',
  })));
}));

/** Current doctor's verified identity QR payload for patients to scan. */
router.get('/me/qr', requireRole('doctor'), asyncHandler(async (req, res) => {
  const profile = await DoctorProfile.findOne({ user: req.user._id });
  return ok(res, {
    type: 'doctor',
    doctorId: String(req.user._id),
    name: req.user.name,
    email: req.user.email,
    specialty: profile?.specialty || null,
    clinicName: profile?.clinicName || null,
    verification: profile?.verification?.status || 'unverified',
  });
}));

/** Patients who currently have an active share authorizing this doctor. */
router.get('/shares', requireRole('doctor'), requireVerifiedDoctor, asyncHandler(async (req, res) => ok(res, await shareService.listDoctorShares(req.user))));

/** Authorized bundle for one share (re-checked server-side). */
router.get('/shares/:id', requireRole('doctor'), requireVerifiedDoctor, asyncHandler(async (req, res) => ok(res, await shareService.getDoctorBundle(req.user, req.params.id, { req }))));

/** Stream a shared document file by shareId, verifying doctor authorization and document scope. */
router.get('/shares/:id/documents/:docId/file', requireRole('doctor'), requireVerifiedDoctor, asyncHandler(async (req, res) => {
  const grant = await ShareGrant.findOne({ _id: req.params.id });
  if (!grant) throw notFound('Share not found.');
  const authorized = String(grant.doctorUser || '') === String(req.user._id)
    || (grant.doctorEmail && grant.doctorEmail === req.user.email);
  if (!authorized) {
    await auditService.record(req, { action: 'share.denied.doctor_mismatch', patient: grant.patient, entityType: 'ShareGrant', entityId: grant._id });
    throw forbidden('This share is not authorized for your account.');
  }
  await shareService.resolveAccessByGrant(grant, { req, doctorUser: req.user, countAccess: false });
  const allowedIds = await shareService.scopedDocumentIds(grant);
  const allowed = grant.includeAll || allowedIds.map(String).includes(String(req.params.docId));
  if (!allowed) throw forbidden('This document is not included in the shared records.');

  const doc = await Document.findOne({ _id: req.params.docId, patient: grant.patient, deletedAt: null });
  if (!doc) throw notFound('Document not found.');

  grant.accessLog.push({ action: 'document_opened', actorUser: req.user._id, actorRole: 'doctor', detail: String(doc._id) });
  await grant.save().catch(() => {});

  const { buffer } = await documentsService.readDocumentFile(grant.patient, doc._id);
  res.setHeader('Content-Type', doc.mimeType);
  res.setHeader('Content-Disposition', `inline; filename="${encodeURIComponent(doc.originalName)}"`);
  res.setHeader('Cache-Control', 'private, no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  return res.send(buffer);
}));

/** Ask a question via Doctor AI grounded in the authorized records. */
router.post('/shares/:id/ai/ask', requireRole('doctor'), requireVerifiedDoctor, sensitiveLimiter, validate({
  body: z.object({
    question: z.string().min(3).max(500),
    topK: z.number().int().min(1).max(20).optional(),
    documentIds: z.array(z.string()).max(50).optional(),
    resetConversation: z.boolean().optional(),
  }),
}), asyncHandler(async (req, res) => {
  const grant = await ShareGrant.findOne({ _id: req.params.id });
  if (!grant) throw notFound('Share not found.');
  const authorized = String(grant.doctorUser || '') === String(req.user._id)
    || (grant.doctorEmail && grant.doctorEmail === req.user.email);
  if (!authorized) {
    await auditService.record(req, { action: 'share.denied.doctor_mismatch', patient: grant.patient, entityType: 'ShareGrant', entityId: grant._id });
    throw forbidden('This share is not authorized for your account.');
  }
  await shareService.resolveAccessByGrant(grant, { req, doctorUser: req.user, countAccess: false });
  const allowedIds = await shareService.scopedDocumentIds(grant);

  const answer = await aiService.answerDoctorQuestion({
    req, grant, doctorUser: req.user, allowedIds, body: req.body,
  });
  return ok(res, answer);
}));

/** Current doctor AI conversation for a share (re-validated server-side). */
router.get('/shares/:id/ai/conversation', requireRole('doctor'), requireVerifiedDoctor, sensitiveLimiter, asyncHandler(async (req, res) => {
  const grant = await ShareGrant.findOne({ _id: req.params.id });
  if (!grant) throw notFound('Share not found.');
  const authorized = String(grant.doctorUser || '') === String(req.user._id)
    || (grant.doctorEmail && grant.doctorEmail === req.user.email);
  if (!authorized) throw forbidden('This share is not authorized for your account.');
  await shareService.resolveAccessByGrant(grant, { req, doctorUser: req.user, countAccess: false });
  const messages = await aiService.loadConversation(grant, req.user);
  return ok(res, { shareId: String(grant._id), patient: String(grant.patient), messages });
}));

/** Clear the doctor's conversation for a share. */
router.delete('/shares/:id/ai/conversation', requireRole('doctor'), requireVerifiedDoctor, sensitiveLimiter, asyncHandler(async (req, res) => {
  const grant = await ShareGrant.findOne({ _id: req.params.id });
  if (!grant) throw notFound('Share not found.');
  const authorized = String(grant.doctorUser || '') === String(req.user._id)
    || (grant.doctorEmail && grant.doctorEmail === req.user.email);
  if (!authorized) throw forbidden('This share is not authorized for your account.');
  await shareService.resolveAccessByGrant(grant, { req, doctorUser: req.user, countAccess: false });
  await aiService.resetConversation(grant, req.user);
  return ok(res, { cleared: true });
}));

/**
 * Development-only verification workflow. Requires the X-Doctor-Verify-Key header
 * to match DOCTOR_VERIFY_KEY (set in .env). In production this endpoint is disabled
 * and verification must go through a real credentialing process.
 */
router.post('/verify', requireRole('doctor'), sensitiveLimiter, validate({
  body: z.object({ email: z.string().email().optional() }),
}), asyncHandler(async (req, res) => {
  if (process.env.NODE_ENV === 'production' || !process.env.DOCTOR_VERIFY_KEY) {
    return res.status(403).json({ success: false, error: { code: 'FORBIDDEN', message: 'Doctor verification is not available in this environment.' } });
  }
  const key = req.headers['x-doctor-verify-key'] || '';
  if (key !== process.env.DOCTOR_VERIFY_KEY) {
    await auditService.record(req, { action: 'auth.doctor_verify_failed', metadata: { email: req.body.email } });
    throw forbidden('Invalid verification key.');
  }
  const email = (req.body.email || req.user.email).toLowerCase();
  const doctor = await User.findOne({ email, role: 'doctor' });
  if (!doctor) return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'No doctor account with that email.' } });
  const profile = await DoctorProfile.findOne({ user: doctor._id });
  if (!profile) return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'No doctor profile for that account.' } });
  profile.verification = { status: 'verified', method: 'development-admin', verifiedAt: new Date(), verifiedBy: req.user._id };
  await profile.save();
  await auditService.record(req, { action: 'auth.doctor_verified', actor: req.user._id, actorRole: 'doctor', metadata: { doctor: String(doctor._id) } });
  return ok(res, { id: String(doctor._id), email: doctor.email, status: 'verified' });
}));

module.exports = router;
