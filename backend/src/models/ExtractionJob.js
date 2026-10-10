'use strict';
const mongoose = require('mongoose');

/** Tracks asynchronous extraction jobs so uploads can return immediately. */
const extractionJobSchema = new mongoose.Schema(
  {
    document: { type: mongoose.Schema.Types.ObjectId, ref: 'Document', required: true, index: true },
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    status: { type: String, enum: ['queued', 'running', 'succeeded', 'failed'], default: 'queued', index: true },
    attempts: { type: Number, default: 0 },
    lastError: String,
    startedAt: Date,
    finishedAt: Date,
    stats: {
      pageCount: Number,
      textChars: Number,
      observations: Number,
      conditions: Number,
      allergies: Number,
      medications: Number,
      encounters: Number,
    },
  },
  { timestamps: true }
);

extractionJobSchema.index({ document: 1, createdAt: -1 });

module.exports = mongoose.model('ExtractionJob', extractionJobSchema);
