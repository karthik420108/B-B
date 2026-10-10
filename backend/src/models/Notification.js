'use strict';
const mongoose = require('mongoose');

const notificationSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    type: {
      type: String,
      enum: ['document', 'extraction_failed', 'share_expiring', 'share_accessed', 'duplicate_alert', 'medication_alert', 'appointment', 'system'],
      required: true,
      default: 'system',
    },
    title: { type: String, required: true },
    body: { type: String, default: '' },
    /** No medical detail is placed here - only ids so the client can fetch. */
    refType: { type: String },
    refId: { type: mongoose.Schema.Types.ObjectId },
    read: { type: Boolean, default: false, index: true },
  },
  { timestamps: true }
);

notificationSchema.index({ user: 1, createdAt: -1 });

module.exports = mongoose.model('Notification', notificationSchema);
