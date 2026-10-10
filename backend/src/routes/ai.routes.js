'use strict';

const express = require('express');
const { z } = require('zod');
const aiService = require('../services/aiService');
const ai = require('../ai');
const { authenticate, requireRole } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { sensitiveLimiter } = require('../middleware/rateLimit');
const { asyncHandler, ok } = require('../utils/http');

const router = express.Router();
router.use(authenticate, requireRole('patient'));

/** Describe which AI provider is active and whether external transfer is on. */
router.get('/provider', asyncHandler(async (req, res) => ok(res, ai.describe())));

/** Ask a question grounded in the patient's own records (RAG). */
router.post('/ask', sensitiveLimiter, validate({ body: z.object({
  question: z.string().min(3).max(500),
  topK: z.number().int().min(1).max(20).optional(),
}) }), asyncHandler(async (req, res) => {
  const result = await aiService.ask(req.user._id, req.body.question, { req, topK: req.body.topK || 8 });
  return ok(res, result);
}));

/** Generate a structured, source-linked medical summary. */
router.post('/summary', sensitiveLimiter, asyncHandler(async (req, res) => {
  const result = await aiService.medicalSummary(req.user._id, { req });
  return ok(res, result);
}));

module.exports = router;
