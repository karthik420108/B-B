'use strict';

const express = require('express');
const { z } = require('zod');
const shareService = require('../services/shareService');
const documentsService = require('../services/documentsService');
const aiService = require('../services/aiService');
const { Document } = require('../models');
const { optionalAuth, authenticate, requireRole, requireVerifiedDoctor } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { sensitiveLimiter } = require('../middleware/rateLimit');
const { asyncHandler, ok } = require('../utils/http');
const { forbidden, notFound } = require('../utils/errors');

const router = express.Router();

/**
 * Public-ish share endpoints. A token is required for every one of them and the
 * server re-validates status, expiry, max-access and authorization each time.
 * No medical data or permanent credential is ever embedded in the QR/link.
 */

/** Inspect a token without consuming an access (used before claiming). */
router.get('/:token/inspect', sensitiveLimiter, optionalAuth, asyncHandler(async (req, res) => {
  return ok(res, await shareService.inspectToken(req.params.token, { req }));
}));

/** Claim a link share (first authenticated access binds it to the doctor). */
router.post('/:token/claim', sensitiveLimiter, authenticate, requireRole('doctor'), requireVerifiedDoctor, asyncHandler(async (req, res) => {
  const grant = await shareService.resolveAccess(req.params.token, { req, doctorUser: req.user, countAccess: true });
  await shareService.bindToDoctor(grant, req.user);
  const bundle = await shareService.buildBundle(grant, { req });
  return ok(res, bundle);
}));

/** Fetch the authorized bundle. */
router.get('/:token/bundle', sensitiveLimiter, authenticate, requireRole('doctor'), requireVerifiedDoctor, asyncHandler(async (req, res) => {
  const grant = await shareService.resolveAccess(req.params.token, { req, doctorUser: req.user, countAccess: false });
  if (grant.doctorUser && String(grant.doctorUser) !== String(req.user._id)
      && !(grant.doctorEmail && grant.doctorEmail === req.user.email)) {
    throw forbidden('This share is authorized to a different doctor.');
  }
  if (!grant.doctorUser) await shareService.bindToDoctor(grant, req.user);
  // Count exactly one access per bundle fetch.
  grant.accessCount += 1;
  grant.lastAccessedAt = new Date();
  grant.accessLog.push({ action: 'viewed', actorUser: req.user._id, actorRole: 'doctor' });
  await grant.save();
  const bundle = await shareService.buildBundle(grant, { req });
  return ok(res, bundle);
}));

/** Stream a shared source document, only if it is inside the grant's scope. */
router.get('/:token/documents/:docId/file', authenticate, requireRole('doctor'), requireVerifiedDoctor, asyncHandler(async (req, res) => {
  const grant = await shareService.resolveAccess(req.params.token, { req, doctorUser: req.user, countAccess: false });
  if (grant.doctorUser && String(grant.doctorUser) !== String(req.user._id)
      && !(grant.doctorEmail && grant.doctorEmail === req.user.email)) {
    throw forbidden('This share is authorized to a different doctor.');
  }
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

/** Ask a question via Doctor AI grounded in the token-authorized records. */
router.post('/:token/ai/ask', authenticate, requireRole('doctor'), requireVerifiedDoctor, sensitiveLimiter, validate({
  body: z.object({
    question: z.string().min(3).max(500),
    topK: z.number().int().min(1).max(20).optional(),
    documentIds: z.array(z.string()).max(50).optional(),
    resetConversation: z.boolean().optional(),
  }),
}), asyncHandler(async (req, res) => {
  const grant = await shareService.resolveAccess(req.params.token, { req, doctorUser: req.user, countAccess: false });
  if (grant.doctorUser && String(grant.doctorUser) !== String(req.user._id)
      && !(grant.doctorEmail && grant.doctorEmail === req.user.email)) {
    throw forbidden('This share is authorized to a different doctor.');
  }
  const allowedIds = await shareService.scopedDocumentIds(grant);
  const answer = await aiService.answerDoctorQuestion({
    req, grant, doctorUser: req.user, allowedIds, body: req.body,
  });
  return ok(res, answer);
}));

/** Current doctor AI conversation for a token-authorized share. */
router.get('/:token/ai/conversation', authenticate, requireRole('doctor'), requireVerifiedDoctor, sensitiveLimiter, asyncHandler(async (req, res) => {
  const grant = await shareService.resolveAccess(req.params.token, { req, doctorUser: req.user, countAccess: false });
  if (grant.doctorUser && String(grant.doctorUser) !== String(req.user._id)
      && !(grant.doctorEmail && grant.doctorEmail === req.user.email)) {
    throw forbidden('This share is authorized to a different doctor.');
  }
  const messages = await aiService.loadConversation(grant, req.user);
  return ok(res, { shareId: String(grant._id), patient: String(grant.patient), messages });
}));

/** Clear the doctor's conversation for a token-authorized share. */
router.delete('/:token/ai/conversation', authenticate, requireRole('doctor'), requireVerifiedDoctor, sensitiveLimiter, asyncHandler(async (req, res) => {
  const grant = await shareService.resolveAccess(req.params.token, { req, doctorUser: req.user, countAccess: false });
  if (grant.doctorUser && String(grant.doctorUser) !== String(req.user._id)
      && !(grant.doctorEmail && grant.doctorEmail === req.user.email)) {
    throw forbidden('This share is authorized to a different doctor.');
  }
  await aiService.resetConversation(grant, req.user);
  return ok(res, { cleared: true });
}));

module.exports = router;
