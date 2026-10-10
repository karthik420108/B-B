'use strict';

const express = require('express');
const { z } = require('zod');
const shareService = require('../services/shareService');
const { shareSchema } = require('./shareSchemas');
const { authenticate, requireRole } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { sensitiveLimiter } = require('../middleware/rateLimit');
const { asyncHandler, ok } = require('../utils/http');

const router = express.Router();
router.use(authenticate, requireRole('patient'));

/** Create a share. Returns the raw token exactly once for QR/URL generation. */
router.post('/', sensitiveLimiter, validate({ body: shareSchema }), asyncHandler(async (req, res) => {
  const { grant, rawToken, shareUrl } = await shareService.createShare(req.user, req.body, { req });
  return res.status(201).json({
    success: true,
    data: {
      share: grant.toClient(),
      token: rawToken,
      shareUrl,
      absoluteUrl: `${require('../config').publicBaseUrl}${shareUrl}`,
      qrPayload: rawToken,
      notice: 'The token is shown only once. It contains no medical data or permanent credentials.',
    },
  });
}));

router.get('/', asyncHandler(async (req, res) => ok(res, await shareService.listPatientShares(req.user._id, { status: req.query.status }))));

router.get('/:id', asyncHandler(async (req, res) => {
  const grant = await shareService.getPatientShare(req.user._id, req.params.id);
  return ok(res, shareService.shareWithHistory(grant));
}));

router.post('/:id/revoke', validate({ body: z.object({ reason: z.string().max(200).optional() }) }), asyncHandler(async (req, res) => {
  const grant = await shareService.revokeShare(req.user, req.params.id, { reason: req.body.reason, req });
  return ok(res, shareService.shareWithHistory(grant));
}));

module.exports = router;
