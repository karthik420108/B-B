'use strict';

const express = require('express');
const { z } = require('zod');
const patientService = require('../services/patientService');
const dashboardService = require('../services/dashboardService');
const { authenticate, requireRole } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { asyncHandler, ok } = require('../utils/http');

const router = express.Router();
router.use(authenticate, requireRole('patient'));

router.get('/profile', asyncHandler(async (req, res) => ok(res, await patientService.getProfile(req.user._id))));

const profileSchema = z.object({
  name: z.string().min(2).max(120).optional(),
  phone: z.string().max(40).optional(),
  dateOfBirth: z.string().max(40).nullable().optional(),
  sex: z.enum(['female', 'male', 'intersex', 'unknown', 'prefer_not_to_say']).optional(),
  bloodGroup: z.enum(['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'unknown']).optional(),
  address: z.string().max(300).optional(),
  chronicConditions: z.array(z.string().max(160)).max(100).optional(),
  medicalHistory: z.array(z.string().max(300)).max(100).optional(),
  currentMedicationsText: z.array(z.string().max(160)).max(100).optional(),
  emergencyContacts: z.array(z.object({ name: z.string().max(120), relation: z.string().max(60).optional(), phone: z.string().max(40).optional() })).max(10).optional(),
  onboardingComplete: z.boolean().optional(),
}).strict();

router.patch('/profile', validate({ body: profileSchema }), asyncHandler(async (req, res) => ok(res, await patientService.updateProfile(req.user._id, req.body, { req }))));

router.post('/allergies', validate({ body: z.object({ substance: z.string().min(2).max(120), reaction: z.string().max(200).optional(), severity: z.enum(['mild', 'moderate', 'severe', 'unknown']).optional() }) }), asyncHandler(async (req, res) => ok(res, await patientService.addAllergy(req.user._id, req.body, { req }))));

router.delete('/allergies/:allergyId', asyncHandler(async (req, res) => ok(res, await patientService.removeAllergy(req.user._id, req.params.allergyId, { req }))));

router.put('/emergency-card', validate({ body: z.object({
  enabled: z.boolean().optional(),
  shareConditions: z.boolean().optional(),
  shareAllergies: z.boolean().optional(),
  shareMedications: z.boolean().optional(),
  shareEmergencyContact: z.boolean().optional(),
  shareRecentResults: z.boolean().optional(),
}) }), asyncHandler(async (req, res) => ok(res, await patientService.updateEmergencyCard(req.user._id, req.body, { req }))));

router.get('/emergency-card', asyncHandler(async (req, res) => ok(res, await dashboardService.getEmergencyCard(req.user._id))));

router.get('/dashboard', asyncHandler(async (req, res) => ok(res, await dashboardService.getDashboard(req.user._id))));

router.get('/export', asyncHandler(async (req, res) => ok(res, await patientService.exportData(req.user._id))));

router.delete('/account', validate({ body: z.object({ confirm: z.literal('DELETE') }) }), asyncHandler(async (req, res) => ok(res, await patientService.deleteAllData(req.user._id, { req }))));

module.exports = router;
