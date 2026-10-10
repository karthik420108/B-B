'use strict';

const {
  Document, Observation, Condition, AllergyIntolerance, MedicationStatement,
  Encounter, ShareGrant, Appointment, PatientProfile,
} = require('../models');
const recordsService = require('./recordsService');
const duplicateTestService = require('./duplicateTestService');
const medicationSafetyService = require('./medicationSafetyService');
const notificationService = require('./notificationService');

/**
 * Aggregated dashboard payload for the patient home screen.
 */
async function getDashboard(patientId) {
  const scope = { patient: patientId, deletedAt: null };
  const now = new Date();

  const [
    recentDocuments, latestObservations, conditions, allergies, medications,
    encounters, activeShares, upcomingAppointments, unverifiedCounts, profile,
    unreadNotifications,
  ] = await Promise.all([
    Document.find(scope).sort({ eventDate: -1, createdAt: -1 }).limit(6).select('originalName category eventDate providerName extractionStatus createdAt').lean(),
    Observation.find({ ...scope, value: { $ne: null } }).sort({ date: -1 }).limit(8).lean(),
    Condition.find(scope).sort({ onsetDate: -1 }).limit(8).lean(),
    AllergyIntolerance.find(scope).limit(10).lean(),
    MedicationStatement.find({ ...scope, status: 'active' }).sort({ startDate: -1 }).limit(20).lean(),
    Encounter.find(scope).sort({ date: -1 }).limit(5).lean(),
    ShareGrant.find({ patient: patientId, status: 'active', expiresAt: { $gt: now } }).lean(),
    Appointment.find({ patient: patientId, status: 'scheduled', dateTime: { $gte: now } }).sort({ dateTime: 1 }).limit(5).lean(),
    Promise.all([
      Observation.countDocuments({ ...scope, verification: 'unverified' }),
      Condition.countDocuments({ ...scope, verification: 'unverified' }),
      AllergyIntolerance.countDocuments({ ...scope, verification: 'unverified' }),
      MedicationStatement.countDocuments({ ...scope, verification: 'unverified' }),
    ]),
    PatientProfile.findOne({ user: patientId }).lean(),
    notificationService.unreadCount(patientId),
  ]);

  // Alerts: duplicate tests + medication safety (best-effort; never fatal).
  let duplicateSummary = { total: 0, top: [] };
  let medicationSummary = { checkerAvailable: medicationSafetyService.isAvailable(), interactions: [], duplicates: [] };
  try {
    const dup = await duplicateTestService.detectRepeatedTests(patientId, { windowDays: 45 });
    duplicateSummary = { total: dup.total, top: dup.findings.slice(0, 3) };
  } catch { /* non-fatal */ }
  try {
    const med = await medicationSafetyService.report(patientId);
    medicationSummary = { checkerAvailable: med.checkerAvailable, interactions: (med.interactions || []).slice(0, 5), duplicates: med.duplicates.slice(0, 5) };
  } catch { /* non-fatal */ }

  const pendingVerification = unverifiedCounts.reduce((a, b) => a + b, 0);

  return {
    generatedAt: now.toISOString(),
    patient: profile ? {
      bloodGroup: profile.bloodGroup,
      chronicConditions: profile.chronicConditions,
      emergencyContacts: profile.emergencyContacts,
      onboardingComplete: profile.onboardingComplete,
    } : null,
    recentDocuments: recentDocuments.map((d) => ({
      id: String(d._id), originalName: d.originalName, category: d.category, eventDate: d.eventDate,
      providerName: d.providerName, extractionStatus: d.extractionStatus, uploadedAt: d.createdAt,
    })),
    latestResults: latestObservations.map((o) => ({
      id: String(o._id), testName: o.testName, value: o.value, unit: o.unit,
      referenceRange: o.referenceRange, date: o.date, abnormal: o.abnormal,
      providerName: o.providerName, verification: o.verification, sourceDocument: o.sourceDocument,
    })),
    conditions: conditions.map((c) => ({ id: String(c._id), name: c.name, status: c.status, onsetDate: c.onsetDate, verification: c.verification })),
    allergies: allergies.map((a) => ({ id: String(a._id), substance: a.substance, reaction: a.reaction, severity: a.severity, verification: a.verification })),
    activeMedications: medications.map((m) => ({ id: String(m._id), name: m.name, strength: m.strength, frequency: m.frequency, startDate: m.startDate, providerName: m.providerName, verification: m.verification })),
    recentEncounters: encounters.map((e) => ({ id: String(e._id), type: e.type, date: e.date, providerName: e.providerName, diagnosis: e.diagnosis })),
    counts: {
      pendingVerification,
      unverified: { observations: unverifiedCounts[0], conditions: unverifiedCounts[1], allergies: unverifiedCounts[2], medications: unverifiedCounts[3] },
      activeShares: activeShares.length,
      unreadNotifications,
    },
    activeShares: activeShares.map((s) => ({ id: String(s._id), doctorName: s.doctorName, label: s.label, expiresAt: s.expiresAt, documentCount: s.documents.length, includeAll: s.includeAll })),
    appointments: upcomingAppointments.map((a) => ({ id: String(a._id), title: a.title, providerName: a.providerName, dateTime: a.dateTime, reason: a.reason, reminder: a.reminder })),
    medicationReminders: medications.filter((m) => m.frequency).slice(0, 10).map((m) => ({ id: String(m._id), name: m.name, strength: m.strength, frequency: m.frequency })),
    alerts: {
      duplicateTests: duplicateSummary,
      medication: medicationSummary,
    },
  };
}

/**
 * Emergency medical card. Only includes the sections the patient enabled, and
 * always surfaces what is missing/unverified. No permanent public access is
 * created - the QR flow uses a short-lived, revocable share.
 */
async function getEmergencyCard(patientId) {
  const profile = await PatientProfile.findOne({ user: patientId }).lean();
  if (!profile) return null;
  const settings = profile.emergencyCard || {};
  const scope = { patient: patientId, deletedAt: null };

  const [conditions, allergies, medications, recentResults] = await Promise.all([
    settings.shareConditions ? Condition.find(scope).sort({ onsetDate: -1 }).limit(20).lean() : [],
    settings.shareAllergies ? AllergyIntolerance.find(scope).limit(20).lean() : [],
    settings.shareMedications ? MedicationStatement.find({ ...scope, status: 'active' }).limit(30).lean() : [],
    settings.shareRecentResults ? Observation.find({ ...scope, value: { $ne: null } }).sort({ date: -1 }).limit(10).lean() : [],
  ]);

  const patientProfileAllergies = settings.shareAllergies ? (profile.allergies || []) : [];
  const allAllergies = [
    ...patientProfileAllergies.map((a) => ({ substance: a.substance, reaction: a.reaction, severity: a.severity, source: 'patient', verification: a.verification })),
    ...allergies.map((a) => ({ substance: a.substance, reaction: a.reaction, severity: a.severity, source: a.source, verification: a.verification })),
  ];

  const missing = [];
  if (!allAllergies.length) missing.push('No allergies recorded - this does not mean there are none.');
  if (!conditions.length && settings.shareConditions) missing.push('No conditions recorded.');
  if (!medications.length && settings.shareMedications) missing.push('No current medications recorded.');
  const unverified = [...conditions, ...allergies, ...medications].filter((r) => r.verification === 'unverified').length;
  if (unverified) missing.push(`${unverified} item(s) are unverified or machine-extracted.`);

  return {
    enabled: Boolean(settings.enabled),
    settings,
    patientName: null,
    bloodGroup: profile.bloodGroup,
    conditions: conditions.map((c) => ({ name: c.name, status: c.status, verification: c.verification })),
    allergies: allAllergies,
    medications: medications.map((m) => ({ name: m.name, strength: m.strength, frequency: m.frequency, status: m.status })),
    emergencyContacts: settings.shareEmergencyContact ? (profile.emergencyContacts || []) : [],
    recentResults: recentResults.map((o) => ({ testName: o.testName, value: o.value, unit: o.unit, date: o.date, referenceRange: o.referenceRange })),
    missing,
    lastUpdatedAt: new Date().toISOString(),
    disclaimer: 'Informational only. Not a substitute for a full medical record and may be incomplete. Emergency access requires the device/service to be online.',
  };
}

module.exports = { getDashboard, getEmergencyCard };
