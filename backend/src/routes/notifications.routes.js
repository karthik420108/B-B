'use strict';

const express = require('express');
const { z } = require('zod');
const notificationService = require('../services/notificationService');
const { authenticate } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { asyncHandler, ok } = require('../utils/http');

const router = express.Router();
router.use(authenticate);

router.get('/', asyncHandler(async (req, res) => ok(res, await notificationService.listForUser(req.user._id, { unreadOnly: req.query.unread === 'true', limit: parseInt(req.query.limit || '50', 10) }))));
router.get('/unread-count', asyncHandler(async (req, res) => ok(res, { count: await notificationService.unreadCount(req.user._id) })));
router.post('/:id/read', asyncHandler(async (req, res) => ok(res, await notificationService.markRead(req.user._id, req.params.id))));
router.post('/read-all', asyncHandler(async (req, res) => ok(res, await notificationService.markAllRead(req.user._id))));

module.exports = router;
