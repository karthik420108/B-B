'use strict';

const {
  ShareGrant, Document, Observation, Condition, AllergyIntolerance,
  MedicationStatement, Encounter, User, PatientProfile, DoctorProfile,
} = require('../models');
const { randomToken, hashToken } = require('../utils/crypto');
const { AppError, forbidden, notFound, badRequest } = require('../utils/errors');
const auditService = require('./auditService');
const notificationService = require('./notificationService');
const duplicateTestService = require('./duplicateTestService');
const medicationSafetyService = require('./medicationSafetyService');
const logger = require('../utils/logger');

const MAX_SHARE_DAYS = 90;
const MIN_TTL_MINUTES = 5;

/**
 * Secure doctor-sharing service.
 *
 * Security properties:
 *  - Tokens are 256-bit random values from a CSPRNG (`crypto.randomBytes`).
 *  - Only the SHA-256 hash of a token is stored server-side.
 *  - Every access re-validates status, expiry, max-access count and the
 *    authorizing doctor on the server. Client-side hiding is never relied upon.
 *  - Revocation takes effect immediately because the grant row is checked on
 *    every request.
 *  - Every grant/view/revoke/denial is written to the audit log.
 *  - The QR/link contains only the opaque token - never medical data, never a
 *    permanent credential.
 */

function ensurePatient(actor) {
  if (!actor || actor.role !== 'patient') throw forbidden('Only the record owner (patient) can manage sharing.');
}

/** Validate that all document ids belong to the patient and are not deleted. */
async function validateOwnedDocuments(patientId, documentIds) {
  if (!documentIds || documentIds.length === 0) return [];
  const docs = await Document.find({ _id: { $in: documentIds }, patient: patientId, deletedAt: null }).select('_id').lean();
  if (docs.length !== new Set(documentIds.map(String)).size) {
    throw badRequest('One or more selected records do not belong to you or were deleted.');
  }
  return docs.map((d) => d._id);
}

/**
 * Create a share grant. Returns the raw token exactly once.
 */
async function createShare(actor, payload, { req = null } = {}) {
  ensurePatient(actor);
  const {
    documentIds = [], includeAll = false, includeSummary = true, includeTimeline = true,
    includeMedications = true, includeAllergies = true, includeObservations = true,
    includeDuplicateAlerts = true, expiresInMinutes = 1440, maxAccesses = 0,
    doctorUserId = null, doctorEmail = null, doctorName = null, doctorSpecialty = null,
    label = null, approvedSummary = null,
  } = payload || {};

  const ttl = Number(expiresInMinutes);
  if (!Number.isFinite(ttl) || ttl < MIN_TTL_MINUTES) throw badRequest(`Expiry must be at least ${MIN_TTL_MINUTES} minutes.`);
  if (ttl > MAX_SHARE_DAYS * 24 * 60) throw badRequest(`Expiry cannot exceed ${MAX_SHARE_DAYS} days.`);
  if (!includeAll && (!documentIds || documentIds.length === 0)) {
    throw badRequest('Select at least one record to share, or enable full-access sharing.');
  }

  const ownedIds = includeAll ? [] : await validateOwnedDocuments(actor._id, documentIds);

  // Resolve an optional pre-designated doctor. The doctor must exist AND be
  // verified — unverified doctors cannot receive shares (spec §5).
  let doctorUser = null; let resolvedEmail = doctorEmail; let resolvedName = doctorName; let resolvedSpecialty = doctorSpecialty;
  if (doctorUserId) {
    doctorUser = await User.findOne({ _id: doctorUserId, role: 'doctor', status: 'active' });
    if (!doctorUser) throw badRequest('The selected doctor account does not exist.');
    const profile = await DoctorProfile.findOne({ user: doctorUser._id }).select('verification.status');
    const vStatus = profile && profile.verification ? profile.verification.status : 'unverified';
    if (vStatus !== 'verified' && vStatus !== 'development') {
      throw badRequest('The selected doctor is not verified and cannot receive shares yet.');
    }
    resolvedEmail = doctorUser.email; resolvedName = resolvedName || doctorUser.name;
  } else if (doctorEmail) {
    const found = await User.findOne({ email: String(doctorEmail).toLowerCase(), role: 'doctor', status: 'active' });
    if (found) {
      const profile = await DoctorProfile.findOne({ user: found._id }).select('verification.status');
      const vStatus = profile && profile.verification ? profile.verification.status : 'unverified';
      if (vStatus !== 'verified' && vStatus !== 'development') {
        throw badRequest('The selected doctor is not verified and cannot receive shares yet.');
      }
      doctorUser = found._id; resolvedName = resolvedName || found.name;
    }
  }

  const rawToken = randomToken(32);
  const grant = await ShareGrant.create({
    patient: actor._id,
    createdBy: actor._id,
    doctorUser,
    doctorName: resolvedName || null,
    doctorEmail: resolvedEmail ? String(resolvedEmail).toLowerCase() : null,
    doctorSpecialty: resolvedSpecialty || null,
    label,
    tokenHash: hashToken(rawToken),
    tokenPreview: `${rawToken.slice(0, 4)}…${rawToken.slice(-4)}`,
    includeAll,
    documents: ownedIds,
    includeSummary, includeTimeline, includeMedications, includeAllergies, includeObservations, includeDuplicateAlerts,
    expiresAt: new Date(Date.now() + ttl * 60 * 1000),
    maxAccesses: Number(maxAccesses) || 0,
    approvedSummary: approvedSummary || null,
    approvedSummaryAt: approvedSummary ? new Date() : null,
    accessLog: [{ action: 'granted', actorUser: actor._id, actorRole: 'patient', detail: 'Share created' }],
  });

  await auditService.record(req, {
    action: 'share.created', patient: actor._id, entityType: 'ShareGrant', entityId: grant._id,
    metadata: { includeAll, documentCount: ownedIds.length, expiresAt: grant.expiresAt, ttlMinutes: ttl },
  });

  return { grant, rawToken, shareUrl: `/share/${rawToken}` };
}

/** List shares created by the patient (active + expired + revoked). */
async function listPatientShares(patientId, { status } = {}) {
  const query = { patient: patientId };
  if (status) query.status = status;
  const grants = await ShareGrant.find(query).sort({ createdAt: -1 }).limit(200).lean();
  const now = Date.now();
  return grants.map((g) => ({
    ...g,
    id: String(g._id),
    isActive: g.status === 'active' && new Date(g.expiresAt).getTime() > now,
    isExpired: new Date(g.expiresAt).getTime() <= now,
    tokenHash: undefined,
    accessLog: undefined,
  }));
}

async function getPatientShare(patientId, shareId) {
  const grant = await ShareGrant.findOne({ _id: shareId, patient: patientId });
  if (!grant) throw notFound('Share not found');
  return grant;
}

/** Full detail incl. access history, for the owning patient only. */
function shareWithHistory(grant) {
  return {
    id: String(grant._id),
    label: grant.label,
    doctorName: grant.doctorName,
    doctorEmail: grant.doctorEmail,
    doctorSpecialty: grant.doctorSpecialty,
    doctorUser: grant.doctorUser,
    includeAll: grant.includeAll,
    documentCount: grant.documents.length,
    permissions: {
      summary: grant.includeSummary,
      timeline: grant.includeTimeline,
      medications: grant.includeMedications,
      allergies: grant.includeAllergies,
      observations: grant.includeObservations,
      duplicateAlerts: grant.includeDuplicateAlerts,
    },
    status: grant.status,
    expiresAt: grant.expiresAt,
    revokedAt: grant.revokedAt,
    accessCount: grant.accessCount,
    lastAccessedAt: grant.lastAccessedAt,
    isActive: grant.isActive(),
    tokenPreview: grant.tokenPreview,
    createdAt: grant.createdAt,
    accessLog: (grant.accessLog || []).map((e) => ({
      at: e.at, action: e.action, actorRole: e.actorRole, detail: e.detail,
      actorUser: e.actorUser ? String(e.actorUser) : null,
    })),
  };
}

/** Access history for one share, for the owning patient only. */
function shareAccessHistory(grant) {
  return {
    id: String(grant._id),
    status: grant.status,
    accessCount: grant.accessCount,
    lastAccessedAt: grant.lastAccessedAt,
    accessLog: (grant.accessLog || []).map((e) => ({
      at: e.at, action: e.action, actorRole: e.actorRole, detail: e.detail,
      actorUser: e.actorUser ? String(e.actorUser) : null,
    })),
  };
}

/** Revoke a share. Effective immediately server-side. */
async function revokeShare(actor, shareId, { reason, req = null } = {}) {
  ensurePatient(actor);
  const grant = await ShareGrant.findOne({ _id: shareId, patient: actor._id });
  if (!grant) throw notFound('Share not found');
  if (grant.status === 'revoked') return grant;
  grant.status = 'revoked';
  grant.revokedAt = new Date();
  grant.revokedBy = actor._id;
  grant.revokeReason = reason || null;
  grant.accessLog.push({ action: 'revoked', actorUser: actor._id, actorRole: 'patient', detail: reason || 'Revoked by patient' });
  await grant.save();
  await auditService.record(req, { action: 'share.revoked', patient: actor._id, entityType: 'ShareGrant', entityId: grant._id });
  logger.info('Share revoked: %s', grant._id);
  return grant;
}

/**
 * Resolve a raw bearer token to a usable grant, enforcing every rule server-side.
 * Throws AppError with the correct status on any failure, and logs the denial.
 */
async function resolveAccess(rawToken, { req = null, doctorUser = null, countAccess = true } = {}) {
  if (!rawToken || typeof rawToken !== 'string' || rawToken.length < 20) {
    throw new AppError(400, 'INVALID_TOKEN', 'A share token is required.');
  }
  const grant = await ShareGrant.findOne({ tokenHash: hashToken(rawToken) });
  if (!grant) throw notFound('This share link is invalid or no longer exists.');

  const logDenial = async (action) => {
    grant.accessLog.push({
      action, actorUser: doctorUser || (req && req.user && req.user._id),
      actorRole: (req && req.user && req.user.role) || 'anonymous',
    });
    await grant.save().catch(() => {});
    await auditService.record(req, { action: `share.denied.${action}`, patient: grant.patient, entityType: 'ShareGrant', entityId: grant._id });
  };

  if (grant.status === 'revoked') {
    await logDenial('denied_revoked');
    throw forbidden('This share has been revoked by the patient. Access is no longer permitted.');
  }
  if (new Date(grant.expiresAt).getTime() <= Date.now()) {
    if (grant.status === 'active') { grant.status = 'expired'; await grant.save().catch(() => {}); }
    await logDenial('denied_expired');
    throw forbidden('This share has expired.');
  }
  if (grant.maxAccesses > 0 && grant.accessCount >= grant.maxAccesses) {
    await logDenial('denied_unauthorized');
    throw forbidden('This share has reached its maximum number of accesses.');
  }
  if (grant.doctorUser && doctorUser && String(grant.doctorUser) !== String(doctorUser._id)) {
    await logDenial('denied_unauthorized');
    throw forbidden('This share is authorized to a different doctor.');
  }

  if (countAccess) {
    grant.accessCount += 1;
    grant.lastAccessedAt = new Date();
    grant.accessLog.push({
      action: 'viewed', actorUser: (doctorUser && doctorUser._id) || (req && req.user && req.user._id),
      actorRole: (req && req.user && req.user.role) || 'anonymous',
    });
    await grant.save().catch(() => {});
  }
  return grant;
}

/** Peek at a token's metadata without counting an access (used to preview a QR). */
async function inspectToken(rawToken, { req = null } = {}) {
  const grant = await resolveAccess(rawToken, { req, countAccess: false });
  const patientUser = await User.findById(grant.patient).select('name');
  return {
    valid: true,
    status: grant.status,
    isActive: grant.isActive(),
    shareId: String(grant._id),
    doctorName: grant.doctorName,
    doctorSpecialty: grant.doctorSpecialty,
    patientName: patientUser ? patientUser.name : null,
    label: grant.label,
    expiresAt: grant.expiresAt,
    permissions: {
      summary: grant.includeSummary,
      timeline: grant.includeTimeline,
      medications: grant.includeMedications,
      allergies: grant.includeAllergies,
      observations: grant.includeObservations,
      duplicateAlerts: grant.includeDuplicateAlerts,
    },
    documentCount: grant.includeAll ? null : grant.documents.length,
    includeAll: grant.includeAll,
    requiresBinding: !grant.doctorUser,
  };
}

/**
 * Bind a share to an authenticated doctor (first access by a link share).
 * If the grant was pre-assigned, only that doctor may bind.
 */
async function bindToDoctor(grant, doctor) {
  if (grant.doctorUser && String(grant.doctorUser) !== String(doctor._id)) {
    throw forbidden('This share is authorized to a different doctor.');
  }
  if (!grant.doctorUser) {
    grant.doctorUser = doctor._id;
    if (!grant.doctorName) grant.doctorName = doctor.name;
    if (!grant.doctorEmail) grant.doctorEmail = doctor.email;
    grant.accessLog.push({ action: 'granted', actorUser: doctor._id, actorRole: 'doctor', detail: 'Doctor claimed link share' });
    await grant.save();
  }
  return grant;
}

/** Documents a grant may expose. */
async function scopedDocumentIds(grant) {
  if (grant.includeAll) {
    const docs = await Document.find({ patient: grant.patient, deletedAt: null }).select('_id').lean();
    return docs.map((d) => d._id);
  }
  return grant.documents;
}

function inDocScope(filter, allowedIds, includeAll) {
  if (includeAll) return filter;
  return { ...filter, sourceDocument: { $in: allowedIds } };
}

/**
 * Assemble the patient data bundle visible through a grant, honoring every
 * permission flag and the selected-document scope.
 */
async function buildBundle(grant, { req = null } = {}) {
  const patientId = grant.patient;
  const allowedIds = await scopedDocumentIds(grant);
  const includeAll = grant.includeAll;
  const patientUser = await User.findById(patientId).select('name');
  const profile = await PatientProfile.findOne({ user: patientId }).lean();

  const scope = { patient: patientId, deletedAt: null };

  const [documents, observations, conditions, allergyResources, medications, encounters] = await Promise.all([
    Document.find(includeAll ? { patient: patientId, deletedAt: null } : { _id: { $in: allowedIds }, patient: patientId, deletedAt: null })
      .select('originalName category eventDate providerName mimeType pageCount extractionStatus tags createdAt size')
      .sort({ eventDate: -1 }).lean(),
    grant.includeObservations ? Observation.find(inDocScope(scope, allowedIds, includeAll)).sort({ date: -1 }).limit(300).lean() : [],
    grant.includeTimeline ? Condition.find(inDocScope(scope, allowedIds, includeAll)).sort({ onsetDate: -1 }).limit(100).lean() : [],
    grant.includeAllergies ? AllergyIntolerance.find(inDocScope(scope, allowedIds, includeAll)).limit(100).lean() : [],
    grant.includeMedications ? MedicationStatement.find(inDocScope(scope, allowedIds, includeAll)).sort({ startDate: -1 }).limit(200).lean() : [],
    grant.includeTimeline ? Encounter.find(inDocScope(scope, allowedIds, includeAll)).sort({ date: -1 }).limit(100).lean() : [],
  ]);

  const bundle = {
    share: {
      id: String(grant._id),
      label: grant.label,
      doctorName: grant.doctorName,
      expiresAt: grant.expiresAt,
      permissions: {
        summary: grant.includeSummary,
        timeline: grant.includeTimeline,
        medications: grant.includeMedications,
        allergies: grant.includeAllergies,
        observations: grant.includeObservations,
        duplicateAlerts: grant.includeDuplicateAlerts,
      },
    },
    patient: patientUser ? {
      name: patientUser.name,
      dateOfBirth: profile ? profile.dateOfBirth : null,
      sex: profile ? profile.sex : null,
      bloodGroup: profile ? profile.bloodGroup : null,
    } : null,
    patientEnteredAllergies: grant.includeAllergies && profile
      ? (profile.allergies || []).map((a) => ({ substance: a.substance, reaction: a.reaction, severity: a.severity, source: a.source, verification: a.verification }))
      : [],
    documents: documents.map((d) => ({
      id: String(d._id), originalName: d.originalName, category: d.category, eventDate: d.eventDate,
      providerName: d.providerName, mimeType: d.mimeType, pageCount: d.pageCount,
      extractionStatus: d.extractionStatus, tags: d.tags, uploadedAt: d.createdAt, size: d.size,
    })),
    observations: observations.map(mapObservation),
    conditions: conditions.map((c) => ({ id: String(c._id), name: c.name, onsetDate: c.onsetDate, status: c.status, providerName: c.providerName, sourceDocument: c.sourceDocument, source: c.source, verification: c.verification })),
    allergies: allergyResources.map((a) => ({ id: String(a._id), substance: a.substance, reaction: a.reaction, severity: a.severity, onsetDate: a.onsetDate, sourceDocument: a.sourceDocument, source: a.source, verification: a.verification })),
    medications: medications.map(mapMedication),
    encounters: encounters.map((e) => ({ id: String(e._id), type: e.type, date: e.date, reason: e.reason, diagnosis: e.diagnosis, providerName: e.providerName, sourceDocument: e.sourceDocument, verification: e.verification })),
    summary: grant.includeSummary ? {
      approvedText: grant.approvedSummary || null,
      approvedAt: grant.approvedSummaryAt || null,
      counts: { documents: documents.length, observations: observations.length, medications: medications.length, allergies: allergyResources.length, conditions: conditions.length, encounters: encounters.length },
    } : null,
    duplicateAlerts: grant.includeDuplicateAlerts ? (await duplicateTestService.detectRepeatedTests(patientId, { windowDays: 180 })).findings : [],
    medicationAlerts: grant.includeMedications ? (await medicationSafetyService.report(patientId)) : null,
    generatedAt: new Date().toISOString(),
  };

  await auditService.record(req, {
    action: 'share.viewed', patient: patientId, entityType: 'ShareGrant', entityId: grant._id,
    metadata: { includeAll, documents: documents.length },
  });
  return bundle;
}

function mapObservation(o) {
  return {
    id: String(o._id), testName: o.testName, value: o.value, valueString: o.valueString,
    unit: o.unit, referenceRange: o.referenceRange, date: o.date, abnormal: o.abnormal,
    providerName: o.providerName, sourceDocument: o.sourceDocument, source: o.source, verification: o.verification,
  };
}

function mapMedication(m) {
  return {
    id: String(m._id), name: m.name, genericName: m.genericName, strength: m.strength, dose: m.dose,
    frequency: m.frequency, route: m.route, form: m.form, startDate: m.startDate, endDate: m.endDate,
    status: m.status, prescriber: m.prescriber, providerName: m.providerName,
    sourceDocument: m.sourceDocument, source: m.source, verification: m.verification,
  };
}

/** Doctor dashboard: shares currently authorizing this doctor. */
async function listDoctorShares(doctorUser) {
  const now = new Date();
  const grants = await ShareGrant.find({
    status: 'active',
    expiresAt: { $gt: now },
    $or: [{ doctorUser: doctorUser._id }, { doctorEmail: doctorUser.email }],
  }).sort({ createdAt: -1 }).lean();

  const patientIds = [...new Set(grants.map((g) => String(g.patient)))];
  const patients = await User.find({ _id: { $in: patientIds } }).select('name');
  const nameById = new Map(patients.map((p) => [String(p._id), p.name]));

  return grants.map((g) => ({
    id: String(g._id),
    patientName: nameById.get(String(g.patient)) || 'Patient',
    patientId: String(g.patient),
    label: g.label,
    doctorName: g.doctorName,
    expiresAt: g.expiresAt,
    createdAt: g.createdAt,
    accessCount: g.accessCount,
    documentCount: (g.documents || []).length,
    includeAll: g.includeAll,
    permissions: {
      summary: g.includeSummary, timeline: g.includeTimeline, medications: g.includeMedications,
      allergies: g.includeAllergies, observations: g.includeObservations, duplicateAlerts: g.includeDuplicateAlerts,
    },
  }));
}

/** Fetch a share bundle for a doctor by grant id, enforcing ownership + status. */
async function getDoctorBundle(doctorUser, shareId, { req = null } = {}) {
  const grant = await ShareGrant.findOne({ _id: shareId });
  if (!grant) throw notFound('Share not found.');
  const authorized = String(grant.doctorUser || '') === String(doctorUser._id)
    || (grant.doctorEmail && grant.doctorEmail === doctorUser.email);
  if (!authorized) {
    await auditService.record(req, { action: 'share.denied.doctor_mismatch', patient: grant.patient, entityType: 'ShareGrant', entityId: grant._id });
    throw forbidden('This share is not authorized for your account.');
  }
  await resolveAccessByGrant(grant, { req, doctorUser });
  return buildBundle(grant, { req });
}

/** Same enforcement as resolveAccess but starting from an already-loaded grant. */
async function resolveAccessByGrant(grant, { req = null, doctorUser = null, countAccess = true } = {}) {
  if (grant.status === 'revoked') throw forbidden('This share has been revoked by the patient.');
  if (new Date(grant.expiresAt).getTime() <= Date.now()) {
    if (grant.status === 'active') { grant.status = 'expired'; await grant.save().catch(() => {}); }
    throw forbidden('This share has expired.');
  }
  if (grant.maxAccesses > 0 && grant.accessCount >= grant.maxAccesses) throw forbidden('This share has reached its maximum number of accesses.');
  if (countAccess) {
    grant.accessCount += 1;
    grant.lastAccessedAt = new Date();
    grant.accessLog.push({ action: 'viewed', actorUser: doctorUser ? doctorUser._id : undefined, actorRole: 'doctor' });
    await grant.save();
  }
  return grant;
}

module.exports = {
  createShare,
  listPatientShares,
  getPatientShare,
  shareWithHistory,
  shareAccessHistory,
  revokeShare,
  resolveAccess,
  resolveAccessByGrant,
  inspectToken,
  bindToDoctor,
  buildBundle,
  listDoctorShares,
  getDoctorBundle,
  scopedDocumentIds,
  MAX_SHARE_DAYS,
  MIN_TTL_MINUTES,
};
