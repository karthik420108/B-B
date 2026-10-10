'use strict';
const mongoose = require('mongoose');

const auditEventSchema = new mongoose.Schema(
  {
    actor: { type: mongoose.Schema.Types.ObjectId, ref: 'User', index: true },
    actorRole: { type: String },
    /** Patient whose data the event concerns (for patient-scoped audit views). */
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', index: true },
    action: { type: String, required: true, index: true },
    entityType: { type: String },
    entityId: { type: mongoose.Schema.Types.ObjectId },
    /** Sanitized metadata only - never medical content or tokens. */
    metadata: { type: mongoose.Schema.Types.Mixed, default: {} },
    ipHash: String,
    userAgent: String,
    at: { type: Date, default: Date.now, index: true },
  },
  { timestamps: false }
);

auditEventSchema.index({ patient: 1, at: -1 });
auditEventSchema.index({ actor: 1, at: -1 });

module.exports = mongoose.model('AuditEvent', auditEventSchema);
