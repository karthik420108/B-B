'use strict';

const express = require('express');
const { z } = require('zod');
const authService = require('../services/authService');
const { authenticate } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { sensitiveLimiter } = require('../middleware/rateLimit');
const { asyncHandler, ok } = require('../utils/http');

const router = express.Router();

const registerSchema = z.object({
  email: z.string().email().max(200),
  password: z.string().min(8).max(200),
  name: z.string().min(2).max(120),
  role: z.enum(['patient', 'doctor']).default('patient'),
  phone: z.string().max(40).optional(),
  doctorProfile: z.object({
    specialty: z.string().max(120).optional(),
    licenseNumber: z.string().max(80).optional(),
    clinicName: z.string().max(160).optional(),
  }).optional(),
  patientProfile: z.object({
    dateOfBirth: z.string().max(20).optional(),
    bloodGroup: z.enum(['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'unknown']).optional(),
    sex: z.enum(['female', 'male', 'intersex', 'unknown', 'prefer_not_to_say']).optional(),
  }).optional(),
});

const loginSchema = z.object({
  email: z.string().email().max(200),
  password: z.string().min(1).max(200),
});

router.post('/register', sensitiveLimiter, validate({ body: registerSchema }), asyncHandler(async (req, res) => {
  const result = await authService.register(req.body, { req });
  return res.status(201).json({ success: true, data: result });
}));

router.post('/login', sensitiveLimiter, validate({ body: loginSchema }), asyncHandler(async (req, res) => {
  const result = await authService.login(req.body, { req });
  return ok(res, result);
}));

router.post('/refresh', sensitiveLimiter, validate({ body: z.object({ refreshToken: z.string().min(10) }) }), asyncHandler(async (req, res) => {
  const result = await authService.refresh(req.body, { req });
  return ok(res, result);
}));

router.post('/logout', authenticate, asyncHandler(async (req, res) => {
  const result = await authService.logout({ refreshToken: req.body && req.body.refreshToken, allDevices: req.body && req.body.allDevices }, { user: req.user, req });
  return ok(res, result);
}));

router.post('/forgot-password', sensitiveLimiter, validate({ body: z.object({ email: z.string().email() }) }), asyncHandler(async (req, res) => {
  const result = await authService.forgotPassword(req.body, { req });
  return ok(res, result);
}));

router.post('/reset-password', sensitiveLimiter, validate({ body: z.object({ token: z.string().min(10), password: z.string().min(8).max(200) }) }), asyncHandler(async (req, res) => {
  const result = await authService.resetPassword(req.body, { req });
  return ok(res, result);
}));

router.post('/change-password', authenticate, sensitiveLimiter, validate({ body: z.object({ currentPassword: z.string().min(1), newPassword: z.string().min(8).max(200) }) }), asyncHandler(async (req, res) => {
  const result = await authService.changePassword(req.user, req.body, { req });
  return ok(res, result);
}));

router.get('/me', authenticate, asyncHandler(async (req, res) => {
  const result = await authService.getMe(req.user._id);
  return ok(res, result);
}));

module.exports = router;
