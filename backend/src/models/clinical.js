'use strict';
const mongoose = require('mongoose');

/**
 * Shared provenance fields for every extracted clinical fact. The UI relies on
 * these to clearly distinguish patient-entered, AI-extracted, clinician-entered
 * and verified information, and to link facts back to source documents.
 */
const provenanceFields = {
  patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  source: { type: String, enum: ['patient', 'ai-extracted', 'clinician'], default: 'patient' },
  verification: { type: String, enum: ['unverified', 'verified', 'rejected'], default: 'unverified', index: true },
  sourceDocument: { type: mongoose.Schema.Types.ObjectId, ref: 'Document', index: true },
  /** Confidence 0..1 for machine-extracted facts; null for patient-entered. */
  confidence: { type: Number, min: 0, max: 1, default: null },
  provider: { type: mongoose.Schema.Types.ObjectId, ref: 'Provider', index: true },
  providerName: { type: String, trim: true },
  deletedAt: { type: Date, index: true },
};

// ---------------------------------------------------------------------------
// Encounter (FHIR Encounter)
// ---------------------------------------------------------------------------
const encounterSchema = new mongoose.Schema(
  {
    ...provenanceFields,
    type: {
      type: String,
      enum: ['consultation', 'admission', 'discharge', 'emergency', 'procedure', 'follow_up', 'vaccination', 'other'],
      default: 'consultation',
      index: true,
    },
    date: { type: Date, index: true },
    dateEstimated: { type: Boolean, default: false },
    reason: { type: String, trim: true },
    diagnosis: { type: [String], default: [] },
    notes: { type: String },
    admissionDate: Date,
    dischargeDate: Date,
  },
  { timestamps: true }
);
encounterSchema.index({ patient: 1, date: -1 });

// ---------------------------------------------------------------------------
// Observation (FHIR Observation) - labs, vitals
// ---------------------------------------------------------------------------
const observationSchema = new mongoose.Schema(
  {
    ...provenanceFields,
    encounter: { type: mongoose.Schema.Types.ObjectId, ref: 'Encounter', index: true },
    testName: { type: String, required: true, trim: true },
    /** Normalized comparison key (see utils/clinical.normalizeTestName). */
    normalizedTestName: { type: String, index: true },
    value: { type: Number, default: null },
    valueString: { type: String, trim: true },
    unit: { type: String, trim: true },
    referenceRange: { type: String, trim: true },
    specimen: { type: String, trim: true },
    date: { type: Date, index: true },
    dateEstimated: { type: Boolean, default: false },
    abnormal: { type: Boolean, default: null },
  },
  { timestamps: true }
);
observationSchema.index({ patient: 1, normalizedTestName: 1, date: -1 });

// ---------------------------------------------------------------------------
// Condition (FHIR Condition)
// ---------------------------------------------------------------------------
const conditionSchema = new mongoose.Schema(
  {
    ...provenanceFields,
    encounter: { type: mongoose.Schema.Types.ObjectId, ref: 'Encounter', index: true },
    name: { type: String, required: true, trim: true },
    normalizedName: { type: String, index: true },
    code: { type: String, trim: true },
    onsetDate: Date,
    status: { type: String, enum: ['active', 'resolved', 'historical', 'unknown'], default: 'unknown', index: true },
    notes: { type: String },
  },
  { timestamps: true }
);
conditionSchema.index({ patient: 1, onsetDate: -1 });

// ---------------------------------------------------------------------------
// AllergyIntolerance (FHIR AllergyIntolerance)
// ---------------------------------------------------------------------------
const allergyIntoleranceSchema = new mongoose.Schema(
  {
    ...provenanceFields,
    substance: { type: String, required: true, trim: true },
    normalizedSubstance: { type: String, index: true },
    reaction: { type: String, trim: true },
    severity: { type: String, enum: ['mild', 'moderate', 'severe', 'unknown'], default: 'unknown', index: true },
    onsetDate: Date,
    notes: { type: String },
  },
  { timestamps: true }
);
allergyIntoleranceSchema.index({ patient: 1, substance: 1 });

// ---------------------------------------------------------------------------
// MedicationStatement (FHIR MedicationStatement / MedicationRequest)
// ---------------------------------------------------------------------------
const medicationSchema = new mongoose.Schema(
  {
    ...provenanceFields,
    name: { type: String, required: true, trim: true },
    genericName: { type: String, trim: true },
    normalizedName: { type: String, index: true },
    strength: { type: String, trim: true },
    dose: { type: String, trim: true },
    frequency: { type: String, trim: true },
    route: { type: String, trim: true },
    form: { type: String, trim: true },
    startDate: Date,
    endDate: Date,
    status: {
      type: String,
      enum: ['active', 'discontinued', 'completed', 'historical', 'unknown'],
      default: 'unknown',
      index: true,
    },
    prescriber: { type: String, trim: true },
    reason: { type: String, trim: true },
  },
  { timestamps: true }
);
medicationSchema.index({ patient: 1, normalizedName: 1, startDate: -1 });
medicationSchema.index({ patient: 1, status: 1 });

module.exports = {
  Encounter: mongoose.model('Encounter', encounterSchema),
  Observation: mongoose.model('Observation', observationSchema),
  Condition: mongoose.model('Condition', conditionSchema),
  AllergyIntolerance: mongoose.model('AllergyIntolerance', allergyIntoleranceSchema),
  MedicationStatement: mongoose.model('MedicationStatement', medicationSchema),
  provenanceFields,
};
