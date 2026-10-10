'use strict';
const mongoose = require('mongoose');

const appointmentSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    providerName: { type: String, trim: true },
    provider: { type: mongoose.Schema.Types.ObjectId, ref: 'Provider' },
    title: { type: String, trim: true },
    dateTime: { type: Date, required: true, index: true },
    status: { type: String, enum: ['scheduled', 'completed', 'cancelled'], default: 'scheduled', index: true },
    reason: { type: String, trim: true },
    reminder: { type: Boolean, default: false },
    reminderMinutesBefore: { type: Number, default: 60 },
    reminderSentAt: Date,
  },
  { timestamps: true }
);

appointmentSchema.index({ patient: 1, dateTime: 1 });

module.exports = mongoose.model('Appointment', appointmentSchema);
