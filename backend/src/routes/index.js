'use strict';

const express = require('express');

const router = express.Router();

router.use('/auth', require('./auth.routes'));
router.use('/patient', require('./patient.routes'));
router.use('/documents', require('./documents.routes'));
router.use('/records', require('./records.routes'));
router.use('/ai', require('./ai.routes'));
router.use('/shares', require('./shares.routes'));
router.use('/share', require('./share.routes'));
router.use('/doctor', require('./doctor.routes'));
router.use('/notifications', require('./notifications.routes'));
router.use('/appointments', require('./appointments.routes'));
router.use('/audit', require('./audit.routes'));
router.use('/meta', require('./meta.routes'));

module.exports = router;
