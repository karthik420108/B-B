'use strict';

const mongoose = require('mongoose');

/**
 * A patient's medication reminder schedule.
 *
 * Reminder times are WALL-CLOCK times ("HH:mm") interpreted in the schedule's
 * IANA `timezone`; concrete dose occurrences are resolved to UTC instants (see
 * services/medicationService.computeOccurrences) so daylight-saving changes are
 * handled by re-resolving wall-clock times rather than shifting them.
 *
 * `sourceType` records how the schedule was created: typed in by the patient
 * (MANUAL) or confirmed from a prescription extraction (PRESCRIPTION). A
 * PRESCRIPTION schedule always carries a reference to the source document and
 * the supporting text snippet so the patient can trace it back.
 */
const medicationScheduleSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    name: { type: String, required: true, trim: true, maxlength: 160 },
    /** Prescribed strength, e.g. "500 mg". Kept separate from dose amount. */
    strength: { type: String, trim: true, maxlength: 80, default: null },
    /** Amount taken per administration, e.g. "1 tablet". */
    doseInstructions: { type: String, trim: true, maxlength: 160, default: null },
    route: { type: String, trim: true, maxlength: 40, default: null },
    /**
     * Descriptive frequency. The authoritative administration times are
     * `reminderTimes`; frequency only labels the pattern and is validated
     * against the number of times (once=1, twice=2, three=3, custom=1..8).
     */
    frequency: {
      type: String,
      enum: ['once_daily', 'twice_daily', 'three_times_daily', 'custom'],
      default: 'custom',
    },
    /** Explicit wall-clock reminder times "HH:mm", unique within a schedule. */
    reminderTimes: {
      type: [String],
      required: true,
      validate: {
        validator: (v) => Array.isArray(v) && v.length >= 1 && v.length <= 8
          && v.every((t) => /^([01]\d|2[0-3]):([0-5]\d)$/.test(t))
          && new Set(v).size === v.length,
        message: 'reminderTimes must be 1-8 unique times in HH:mm format.',
      },
    },
    /**
     * Optional weekday restriction (0=Sunday..6=Saturday). Null/undefined
     * means every day.
     */
    weekdays: { type: [Number], default: null, validate: {
      validator: (v) => v == null || (Array.isArray(v) && v.length >= 1 && v.every((d) => Number.isInteger(d) && d >= 0 && d <= 6)),
      message: 'weekdays must contain integers 0-6.',
    } },
    startDate: { type: Date, required: true, index: true },
    /** Null means the duration is unknown/ongoing - never invented. */
    endDate: { type: Date, default: null },
    /** IANA timezone id the reminder times refer to (e.g. "Europe/Paris"). */
    timezone: { type: String, default: 'UTC', maxlength: 64 },
    /** Special instructions, e.g. "take with food". */
    instructions: { type: String, trim: true, maxlength: 400, default: null },
    notes: { type: String, trim: true, maxlength: 1000, default: null },

    sourceType: { type: String, enum: ['MANUAL', 'PRESCRIPTION'], default: 'MANUAL' },
    sourceDocument: { type: mongoose.Schema.Types.ObjectId, ref: 'Document', default: null, index: true },
    /** Traceability for prescription-derived schedules. */
    extraction: {
      snippet: { type: String, default: null, maxlength: 2000 },
      extractedAt: { type: Date, default: null },
      documentName: { type: String, default: null, maxlength: 250 },
    },
    /** True once the patient explicitly confirmed the dose + schedule. */
    confirmed: { type: Boolean, default: false },

    status: {
      type: String,
      enum: ['ACTIVE', 'PAUSED', 'COMPLETED', 'DISCONTINUED'],
      default: 'ACTIVE',
      index: true,
    },

    /** Client-generated idempotency key for safe repeated submissions. */
    clientRequestId: { type: String, maxlength: 64, default: null },

    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true }
);

medicationScheduleSchema.index({ patient: 1, status: 1 });
medicationScheduleSchema.index({ patient: 1, createdAt: -1 });
// Idempotency: the same clientRequestId may exist at most once per patient.
medicationScheduleSchema.index(
  { patient: 1, clientRequestId: 1 },
  { unique: true, partialFilterExpression: { clientRequestId: { $type: 'string' } } }
);

/** Client-safe projection (no Mongo internals). */
medicationScheduleSchema.methods.toClient = function toClient() {
  return {
    id: this._id,
    name: this.name,
    strength: this.strength || null,
    doseInstructions: this.doseInstructions || null,
    route: this.route || null,
    frequency: this.frequency,
    reminderTimes: this.reminderTimes || [],
    weekdays: this.weekdays || null,
    startDate: this.startDate,
    endDate: this.endDate || null,
    timezone: this.timezone,
    instructions: this.instructions || null,
    notes: this.notes || null,
    sourceType: this.sourceType,
    sourceDocument: this.sourceDocument || null,
    sourceDocumentName: (this.extraction && this.extraction.documentName) || null,
    extractionSnippet: (this.extraction && this.extraction.snippet) || null,
    extractedAt: (this.extraction && this.extraction.extractedAt) || null,
    confirmed: this.confirmed,
    status: this.status,
    createdAt: this.createdAt,
    updatedAt: this.updatedAt,
  };
};

module.exports = mongoose.model('MedicationSchedule', medicationScheduleSchema);
