'use strict';
const mongoose = require('mongoose');

/**
 * A patient's consent grant: which records a doctor may see, for how long, and
 * with which permissions. Only a hash of the share token is stored.
 */
const accessEntrySchema = new mongoose.Schema(
  {
    at: { type: Date, default: Date.now },
    action: { type: String, enum: ['granted', 'viewed', 'document_opened', 'summary_viewed', 'revoked', 'denied_expired', 'denied_revoked', 'denied_unauthorized'], required: true },
    actorUser: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    actorRole: { type: String },
    /** Only a short label is stored, never the raw IP. */
    ipHash: String,
    userAgent: String,
    detail: String,
  },
  { _id: true }
);

const shareGrantSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },

    /** Optional pre-designated doctor account. Link shares may leave this null. */
    doctorUser: { type: mongoose.Schema.Types.ObjectId, ref: 'User', index: true },
    doctorName: { type: String, trim: true },
    doctorEmail: { type: String, trim: true, lowercase: true },
    doctorSpecialty: { type: String, trim: true },

    label: { type: String, trim: true },

    /** SHA-256 hash of the bearer token. The raw token is shown to the patient once. */
    tokenHash: { type: String, required: true, index: true },
    tokenPreview: { type: String },

    /** Full-access mode: all current and future records of the patient. */
    includeAll: { type: Boolean, default: false },
    /** Explicit record selection. Each entry pins a document + optional child resource ids. */
    documents: { type: [mongoose.Schema.Types.ObjectId], ref: 'Document', default: [] },
    /** Additional non-document context the patient allowed. */
    includeSummary: { type: Boolean, default: true },
    includeTimeline: { type: Boolean, default: true },
    includeMedications: { type: Boolean, default: true },
    includeAllergies: { type: Boolean, default: true },
    includeObservations: { type: Boolean, default: true },
    includeDuplicateAlerts: { type: Boolean, default: true },
    /** Approved AI summary text captured at grant time (frozen snapshot). */
    approvedSummary: { type: String },
    approvedSummaryAt: Date,

    status: { type: String, enum: ['active', 'revoked', 'expired'], default: 'active', index: true },
    expiresAt: { type: Date, required: true, index: true },
    revokedAt: Date,
    revokedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    revokeReason: { type: String },

    maxAccesses: { type: Number, default: 0 }, // 0 = unlimited
    accessCount: { type: Number, default: 0 },
    lastAccessedAt: Date,

    accessLog: { type: [accessEntrySchema], default: [] },
  },
  { timestamps: true }
);

shareGrantSchema.index({ patient: 1, status: 1, expiresAt: 1 });
shareGrantSchema.index({ doctorUser: 1, status: 1 });

shareGrantSchema.methods.isActive = function isActive(now = new Date()) {
  return this.status === 'active' && this.expiresAt.getTime() > now.getTime();
};

shareGrantSchema.methods.toClient = function toClient({ includeToken = false } = {}) {
  return {
    id: this._id,
    patient: this.patient,
    doctorUser: this.doctorUser,
    doctorName: this.doctorName,
    doctorEmail: this.doctorEmail,
    doctorSpecialty: this.doctorSpecialty,
    label: this.label,
    includeAll: this.includeAll,
    documentCount: (this.documents || []).length,
    documents: this.documents,
    permissions: {
      summary: this.includeSummary,
      timeline: this.includeTimeline,
      medications: this.includeMedications,
      allergies: this.includeAllergies,
      observations: this.includeObservations,
      duplicateAlerts: this.includeDuplicateAlerts,
    },
    approvedSummary: this.approvedSummary,
    approvedSummaryAt: this.approvedSummaryAt,
    status: this.status,
    expiresAt: this.expiresAt,
    revokedAt: this.revokedAt,
    accessCount: this.accessCount,
    lastAccessedAt: this.lastAccessedAt,
    tokenPreview: includeToken ? undefined : this.tokenPreview,
    createdAt: this.createdAt,
  };
};

module.exports = mongoose.model('ShareGrant', shareGrantSchema);
