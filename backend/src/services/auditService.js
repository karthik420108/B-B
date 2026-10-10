'use strict';

const { AuditEvent } = require('../models');
const { hashIp } = require('../utils/crypto');
const logger = require('../utils/logger');

/**
 * Records security-relevant events. Metadata must stay sanitized: no medical
 * content, no document text, no tokens. IPs are hashed before storage.
 */
async function record(req, { action, patient, entityType, entityId, metadata = {}, actor, actorRole } = {}) {
  try {
    const doc = {
      action,
      entityType,
      entityId,
      patient,
      metadata,
      actor: actor || (req && req.user && req.user._id) || undefined,
      actorRole: actorRole || (req && req.user && req.user.role) || undefined,
      ipHash: req ? hashIp(req.ip || (req.socket && req.socket.remoteAddress)) : undefined,
      userAgent: req ? String(req.headers['user-agent'] || '').slice(0, 200) : undefined,
    };
    return await AuditEvent.create(doc);
  } catch (err) {
    // Audit failures must never break the request path, but should be visible.
    logger.warn('Audit write failed: %s', err.message);
    return null;
  }
}

module.exports = { record };
