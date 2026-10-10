'use strict';

const express = require('express');
const { AuditEvent } = require('../models');
const { authenticate } = require('../middleware/auth');
const { asyncHandler, ok, parsePagination } = require('../utils/http');

const router = express.Router();
router.use(authenticate);

/** A patient's own audit trail (security events about their data). */
router.get('/', asyncHandler(async (req, res) => {
  const { page, limit, skip } = parsePagination(req.query);
  const filter = req.user.role === 'patient' ? { patient: req.user._id } : { actor: req.user._id };
  const [items, total] = await Promise.all([
    AuditEvent.find(filter).sort({ at: -1 }).skip(skip).limit(limit).lean(),
    AuditEvent.countDocuments(filter),
  ]);
  return ok(res, { items, total, page, limit });
}));

module.exports = router;
