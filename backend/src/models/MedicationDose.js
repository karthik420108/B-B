'use strict';

const mongoose = require('mongoose');

/**
 * A single scheduled dose occurrence for one medication schedule.
 *
 * Occurrences are generated deterministically from the schedule's reminder
 * times and guarded by a unique index on (schedule, scheduledFor) so repeated
 * generation can never create duplicates. Only explicit patient actions
 * (TAKEN / SKIPPED) are stored as patient-authoritative history; a MISSED dose
 * is derived later and persisted lazily - it is a record that no action was
 * captured in the app, not proof the medicine was not taken.
 *
 * Historical occurrences are never rewritten when a future schedule changes.
 */
const medicationDoseSchema = new mongoose.Schema(
  {
    schedule: { type: mongoose.Schema.Types.ObjectId, ref: 'MedicationSchedule', required: true, index: true },
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    /** The exact UTC instant the dose is scheduled for. */
    scheduledFor: { type: Date, required: true },
    status: {
      type: String,
      enum: ['UPCOMING', 'DUE', 'TAKEN', 'SKIPPED', 'MISSED'],
      default: 'UPCOMING',
      index: true,
    },
    /** When the patient actually acted (TAKEN/SKIPPED). */
    actedAt: { type: Date, default: null },
    actionSource: { type: String, enum: ['PATIENT', 'SYSTEM'], default: null },
    note: { type: String, trim: true, maxlength: 300, default: null },
    /** When the dose was classified MISSED (derived, bounded tracking window). */
    missedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

// A schedule cannot have two occurrences at the same instant.
medicationDoseSchema.index({ schedule: 1, scheduledFor: 1 }, { unique: true });
medicationDoseSchema.index({ patient: 1, scheduledFor: -1 });

module.exports = mongoose.model('MedicationDose', medicationDoseSchema);
