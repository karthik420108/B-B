'use strict';
const mongoose = require('mongoose');

/**
 * Structured allergy entry. `source` records provenance so the UI can clearly
 * distinguish patient-reported, AI-extracted, clinician-entered and verified data.
 */
const allergySchema = new mongoose.Schema(
  {
    substance: { type: String, required: true, trim: true },
    reaction: { type: String, trim: true },
    severity: { type: String, enum: ['mild', 'moderate', 'severe', 'unknown'], default: 'unknown' },
    /** patient | ai-extracted | clinician */
    source: { type: String, enum: ['patient', 'ai-extracted', 'clinician'], default: 'patient' },
    /** unverified | verified | rejected */
    verification: { type: String, enum: ['unverified', 'verified', 'rejected'], default: 'unverified' },
    sourceDocument: { type: mongoose.Schema.Types.ObjectId, ref: 'Document' },
    notedAt: Date,
  },
  { _id: true, timestamps: false }
);

const emergencyContactSchema = new mongoose.Schema(
  { name: String, relation: String, phone: String },
  { _id: false }
);

const patientProfileSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, unique: true, index: true },
    dateOfBirth: Date,
    sex: { type: String, enum: ['female', 'male', 'intersex', 'unknown', 'prefer_not_to_say'], default: 'unknown' },
    bloodGroup: {
      type: String,
      enum: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'unknown'],
      default: 'unknown',
    },
    address: { type: String, trim: true },
    emergencyContacts: { type: [emergencyContactSchema], default: [] },
    chronicConditions: { type: [String], default: [] },
    allergies: { type: [allergySchema], default: [] },
    medicalHistory: { type: [String], default: [] },
    /** Free-text current medications entered by the patient (baseline). */
    currentMedicationsText: { type: [String], default: [] },
    onboardingComplete: { type: Boolean, default: false },
    /** Which sections the patient wants to expose on the emergency card. */
    emergencyCard: {
      shareConditions: { type: Boolean, default: true },
      shareAllergies: { type: Boolean, default: true },
      shareMedications: { type: Boolean, default: true },
      shareEmergencyContact: { type: Boolean, default: true },
      shareRecentResults: { type: Boolean, default: false },
      enabled: { type: Boolean, default: false },
    },
    dataOrigin: { type: String, default: 'patient' },
  },
  { timestamps: true }
);

module.exports = mongoose.model('PatientProfile', patientProfileSchema);
