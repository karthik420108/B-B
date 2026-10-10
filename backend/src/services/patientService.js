'use strict';

const {
  PatientProfile, User, Document, Observation, Condition, AllergyIntolerance,
  MedicationStatement, Encounter, ShareGrant, Notification, Appointment, AuditEvent,
} = require('../models');
const { badRequest, notFound } = require('../utils/errors');
const auditService = require('./auditService');

async function getProfile(userId) {
  const profile = await PatientProfile.findOne({ user: userId }).lean();
  if (!profile) throw notFound('Patient profile not found');
  return profile;
}

const ALLOWED_SEX = ['female', 'male', 'intersex', 'unknown', 'prefer_not_to_say'];
const ALLOWED_BLOOD = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'unknown'];

/** Update personal + medical profile fields. Only known fields are accepted. */
async function updateProfile(userId, data = {}, { req = null } = {}) {
  const profile = await PatientProfile.findOne({ user: userId });
  if (!profile) throw notFound('Patient profile not found');

  if (data.dateOfBirth !== undefined) {
    if (data.dateOfBirth === null || data.dateOfBirth === '') profile.dateOfBirth = undefined;
    else {
      const d = new Date(data.dateOfBirth);
      if (Number.isNaN(d.getTime())) throw badRequest('Invalid date of birth.');
      if (d.getTime() > Date.now()) throw badRequest('Date of birth cannot be in the future.');
      profile.dateOfBirth = d;
    }
  }
  if (data.sex !== undefined) {
    if (!ALLOWED_SEX.includes(data.sex)) throw badRequest('Invalid sex value.');
    profile.sex = data.sex;
  }
  if (data.bloodGroup !== undefined) {
    if (!ALLOWED_BLOOD.includes(data.bloodGroup)) throw badRequest('Invalid blood group.');
    profile.bloodGroup = data.bloodGroup;
  }
  if (data.address !== undefined) profile.address = String(data.address).slice(0, 300);
  if (data.chronicConditions !== undefined) {
    if (!Array.isArray(data.chronicConditions)) throw badRequest('chronicConditions must be an array.');
    profile.chronicConditions = data.chronicConditions.slice(0, 100).map((s) => String(s).slice(0, 160));
  }
  if (data.medicalHistory !== undefined) {
    if (!Array.isArray(data.medicalHistory)) throw badRequest('medicalHistory must be an array.');
    profile.medicalHistory = data.medicalHistory.slice(0, 100).map((s) => String(s).slice(0, 300));
  }
  if (data.currentMedicationsText !== undefined) {
    if (!Array.isArray(data.currentMedicationsText)) throw badRequest('currentMedicationsText must be an array.');
    profile.currentMedicationsText = data.currentMedicationsText.slice(0, 100).map((s) => String(s).slice(0, 160));
  }
  if (data.emergencyContacts !== undefined) {
    if (!Array.isArray(data.emergencyContacts)) throw badRequest('emergencyContacts must be an array.');
    profile.emergencyContacts = data.emergencyContacts.slice(0, 10).map((c) => ({
      name: String(c.name || '').slice(0, 120),
      relation: String(c.relation || '').slice(0, 60),
      phone: String(c.phone || '').slice(0, 40),
    }));
  }
  if (data.onboardingComplete !== undefined) profile.onboardingComplete = Boolean(data.onboardingComplete);

  // Keep the user record's name/phone in sync (single source of truth for name).
  if (data.name !== undefined) {
    const name = String(data.name).trim();
    if (name.length < 2) throw badRequest('Name must be at least 2 characters.');
    await User.updateOne({ _id: userId }, { $set: { name: name.slice(0, 120) } });
  }
  if (data.phone !== undefined) {
    await User.updateOne({ _id: userId }, { $set: { phone: String(data.phone).slice(0, 40) } });
  }

  await profile.save();
  await auditService.record(req, { action: 'profile.updated', patient: userId, entityType: 'PatientProfile', entityId: profile._id, metadata: { fields: Object.keys(data) } });
  return profile.toObject();
}

/** Patient-entered allergy (embedded on the profile, kept clearly labelled). */
async function addAllergy(userId, { substance, reaction, severity } = {}, { req = null } = {}) {
  if (!substance || String(substance).trim().length < 2) throw badRequest('An allergy substance is required.');
  const profile = await PatientProfile.findOne({ user: userId });
  if (!profile) throw notFound('Patient profile not found');
  profile.allergies.push({
    substance: String(substance).trim().slice(0, 120),
    reaction: reaction ? String(reaction).slice(0, 200) : undefined,
    severity: ['mild', 'moderate', 'severe', 'unknown'].includes(severity) ? severity : 'unknown',
    source: 'patient',
    verification: 'verified', // patient-entered is treated as self-reported/verified by the patient
  });
  await profile.save();
  await auditService.record(req, { action: 'profile.allergy_added', patient: userId, entityType: 'PatientProfile', entityId: profile._id });
  return profile.toObject();
}

async function removeAllergy(userId, allergyId, { req = null } = {}) {
  const profile = await PatientProfile.findOne({ user: userId });
  if (!profile) throw notFound('Patient profile not found');
  const before = profile.allergies.length;
  profile.allergies = profile.allergies.filter((a) => String(a._id) !== String(allergyId));
  if (profile.allergies.length === before) throw notFound('Allergy not found');
  await profile.save();
  await auditService.record(req, { action: 'profile.allergy_removed', patient: userId, entityType: 'PatientProfile', entityId: profile._id });
  return profile.toObject();
}

async function updateEmergencyCard(userId, settings = {}, { req = null } = {}) {
  const profile = await PatientProfile.findOne({ user: userId });
  if (!profile) throw notFound('Patient profile not found');
  const allowed = ['shareConditions', 'shareAllergies', 'shareMedications', 'shareEmergencyContact', 'shareRecentResults', 'enabled'];
  for (const key of allowed) {
    if (settings[key] !== undefined) profile.emergencyCard[key] = Boolean(settings[key]);
  }
  await profile.save();
  await auditService.record(req, { action: 'profile.emergency_card_updated', patient: userId, entityType: 'PatientProfile', entityId: profile._id, metadata: { enabled: profile.emergencyCard.enabled } });
  return profile.emergencyCard;
}

/** Data export (portable JSON) - part of privacy/portability requirements. */
async function exportData(userId) {
  const [profile, documents, observations, conditions, allergies, medications, encounters, shares, appointments] = await Promise.all([
    PatientProfile.findOne({ user: userId }).lean(),
    Document.find({ patient: userId, deletedAt: null }).select('-rawText').lean(),
    Observation.find({ patient: userId, deletedAt: null }).lean(),
    Condition.find({ patient: userId, deletedAt: null }).lean(),
    AllergyIntolerance.find({ patient: userId, deletedAt: null }).lean(),
    MedicationStatement.find({ patient: userId, deletedAt: null }).lean(),
    Encounter.find({ patient: userId, deletedAt: null }).lean(),
    ShareGrant.find({ patient: userId }).select('-tokenHash -accessLog').lean(),
    Appointment.find({ patient: userId }).lean(),
  ]);
  return {
    exportedAt: new Date().toISOString(),
    format: 'health-wallet-export/v1',
    profile, documents, observations, conditions, allergies, medications, encounters, shares, appointments,
  };
}

/** Delete all of the patient's data (right to erasure). Documents are hard-deleted. */
async function deleteAllData(userId, { req = null } = {}) {
  const docs = await Document.find({ patient: userId }).select('storageKey').lean();
  const { getStorage } = require('../storage');
  const storage = getStorage();
  for (const d of docs) {
    try { await storage.remove(d.storageKey); } catch { /* best effort */ }
  }
  await Promise.all([
    Document.deleteMany({ patient: userId }),
    Observation.deleteMany({ patient: userId }),
    Condition.deleteMany({ patient: userId }),
    AllergyIntolerance.deleteMany({ patient: userId }),
    MedicationStatement.deleteMany({ patient: userId }),
    Encounter.deleteMany({ patient: userId }),
    ShareGrant.deleteMany({ patient: userId }),
    Notification.deleteMany({ user: userId }),
    Appointment.deleteMany({ patient: userId }),
    PatientProfile.deleteMany({ user: userId }),
    AuditEvent.deleteMany({ patient: userId }),
  ]);
  await auditService.record(req, { action: 'account.data_deleted', actor: userId, patient: userId, metadata: { documents: docs.length } });
  await User.deleteOne({ _id: userId });
  return { ok: true, documentsRemoved: docs.length };
}

module.exports = {
  getProfile, updateProfile, addAllergy, removeAllergy, updateEmergencyCard, exportData, deleteAllData,
};
