'use strict';

const express = require('express');
const { z } = require('zod');
const shareService = require('../services/shareService');
const { User, DoctorProfile } = require('../models');
const { authenticate, requireRole, requireVerifiedDoctor } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { sensitiveLimiter } = require('../middleware/rateLimit');
const { asyncHandler, ok } = require('../utils/http');
const { forbidden } = require('../utils/errors');
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

/** Patients who currently have an active share authorizing this doctor. */
router.get('/shares', requireRole('doctor'), requireVerifiedDoctor, asyncHandler(async (req, res) => ok(res, await shareService.listDoctorShares(req.user))));

/** Authorized bundle for one share (re-checked server-side). */
router.get('/shares/:id', requireRole('doctor'), requireVerifiedDoctor, asyncHandler(async (req, res) => ok(res, await shareService.getDoctorBundle(req.user, req.params.id, { req }))));

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
