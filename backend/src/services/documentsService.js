'use strict';

const crypto = require('crypto');
const { Document, Observation, Condition, AllergyIntolerance, MedicationStatement, Encounter, Provider } = require('../models');
const { getStorage } = require('../storage');
const { badRequest, notFound, forbidden } = require('../utils/errors');
const { parsePagination } = require('../utils/http');
const { sha256 } = require('../utils/crypto');
const auditService = require('./auditService');
const notificationService = require('./notificationService');
const { DOCUMENT_CATEGORIES } = require('../models/Document');
const logger = require('../utils/logger');

const ALLOWED_MIME = [
  'application/pdf',
  'image/png', 'image/jpeg', 'image/jpg', 'image/webp', 'image/tiff', 'image/bmp',
  'text/plain',
];

function assertFile(file) {
  if (!file) throw badRequest('No file was provided.');
  if (!ALLOWED_MIME.includes(file.mimetype)) {
    throw badRequest(`Unsupported file type "${file.mimetype}". Allowed: PDF, PNG, JPEG, WEBP, TIFF, BMP, text.`);
  }
}

/** Create a document record from an uploaded/created file. */
async function createDocument(actor, file, metadata = {}, { req = null, extract = true } = {}) {
  assertFile(file);
  const storage = getStorage();
  const hash = sha256(file.buffer);
  const ext = (file.originalname.match(/\.[a-z0-9]+$/i) || [''])[0];
  const key = `patients/${actor._id}/${Date.now()}-${crypto.randomUUID()}${ext}`;
  await storage.save(file.buffer, { key, mimeType: file.mimetype });

  let providerId = metadata.provider || null;
  let providerName = metadata.providerName || null;
  if (providerName && !providerId) {
    const existing = await Provider.findOne({ name: new RegExp(`^${String(providerName).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') });
    if (existing) { providerId = existing._id; providerName = existing.name; }
  }

  const doc = await Document.create({
    patient: actor._id,
    uploadedBy: actor._id,
    originalName: metadata.originalName || file.originalname,
    storageKey: key,
    mimeType: file.mimetype,
    size: file.size || file.buffer.length,
    sha256: hash,
    category: DOCUMENT_CATEGORIES.includes(metadata.category) ? metadata.category : 'other',
    provider: providerId || undefined,
    providerName: providerName || undefined,
    eventDate: metadata.eventDate ? new Date(metadata.eventDate) : undefined,
    eventDateEstimated: Boolean(metadata.eventDateEstimated),
    source: metadata.source || 'upload',
    tags: Array.isArray(metadata.tags) ? metadata.tags.slice(0, 20).map((t) => String(t).slice(0, 40)) : [],
    notes: metadata.notes ? String(metadata.notes).slice(0, 2000) : undefined,
    extractionStatus: metadata.manual ? 'manual' : 'pending',
  });

  await auditService.record(req, { action: 'document.uploaded', patient: actor._id, entityType: 'Document', entityId: doc._id, metadata: { kind: 'document' } });

  // Duplicate content warning (same patient, same hash, different record).
  const dupeCount = await Document.countDocuments({ patient: actor._id, sha256: hash, _id: { $ne: doc._id }, deletedAt: null });
  if (dupeCount > 0) {
    await notificationService.notify(actor._id, { type: 'document', title: 'Possible duplicate document', body: 'You uploaded a document with identical content to an earlier one.', refType: 'Document', refId: doc._id });
  }

  let extraction = null;
  if (extract && !metadata.manual) {
    // Run extraction synchronously so the demo/API returns structured data
    // immediately. Failures are isolated and never break the upload.
    try {
      // eslint-disable-next-line global-require
      const extractionService = require('./extractionService');
      extraction = await extractionService.runExtraction(doc._id, { req });
    } catch (err) {
      logger.warn('Inline extraction failed: %s', err.message);
      extraction = { status: 'failed', error: 'Extraction failed; you can retry from the document view.' };
    }
  }

  const fresh = await Document.findById(doc._id);
  return { document: fresh.toClient(), extraction, duplicate: dupeCount > 0 };
}

/** Build a Mongo filter from query parameters. */
function documentFilter(patientId, query = {}) {
  const filter = { patient: patientId, deletedAt: null };
  if (query.category && DOCUMENT_CATEGORIES.includes(query.category)) filter.category = query.category;
  if (query.provider) filter.provider = query.provider;
  if (query.extractionStatus) filter.extractionStatus = query.extractionStatus;
  if (query.from || query.to) {
    filter.eventDate = {};
    if (query.from) filter.eventDate.$gte = new Date(query.from);
    if (query.to) filter.eventDate.$lte = new Date(query.to);
  }
  if (query.q) {
    const rx = new RegExp(String(query.q).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
    filter.$or = [{ originalName: rx }, { providerName: rx }, { tags: rx }, { notes: rx }];
  }
  return filter;
}

async function listDocuments(patientId, query = {}) {
  const { page, limit, skip } = parsePagination(query);
  const filter = documentFilter(patientId, query);
  const sortField = ['eventDate', 'createdAt', 'originalName', 'category'].includes(query.sort) ? query.sort : 'eventDate';
  const sortDir = query.order === 'asc' ? 1 : -1;
  const [items, total] = await Promise.all([
    Document.find(filter).sort({ [sortField]: sortDir, createdAt: -1 }).skip(skip).limit(limit),
    Document.countDocuments(filter),
  ]);
  return { items: items.map((d) => d.toClient()), total, page, limit };
}

async function getDocument(patientId, id, { includeText = false } = {}) {
  const query = Document.findOne({ _id: id, patient: patientId, deletedAt: null });
  if (includeText) query.select('+rawText');
  const doc = await query;
  if (!doc) throw notFound('Document not found');
  return doc;
}

async function readDocumentFile(patientId, id) {
  if (!patientId) throw forbidden('A patient scope is required to read this file.');
  const doc = await getDocument(patientId, id);
  const storage = getStorage();
  const buffer = await storage.read(doc.storageKey);
  return { doc, buffer };
}

async function updateDocument(patientId, id, patch = {}, { req = null } = {}) {
  const doc = await getDocument(patientId, id);
  const before = doc.toClient();
  if (patch.originalName !== undefined) {
    const name = String(patch.originalName).trim();
    if (name.length < 1) throw badRequest('Name cannot be empty.');
    doc.originalName = name.slice(0, 250);
  }
  if (patch.category !== undefined) {
    if (!DOCUMENT_CATEGORIES.includes(patch.category)) throw badRequest('Invalid category.');
    doc.category = patch.category;
  }
  if (patch.eventDate !== undefined) {
    if (patch.eventDate === null || patch.eventDate === '') { doc.eventDate = undefined; doc.eventDateEstimated = false; }
    else {
      const d = new Date(patch.eventDate);
      if (Number.isNaN(d.getTime())) throw badRequest('Invalid event date.');
      doc.eventDate = d;
      doc.eventDateEstimated = Boolean(patch.eventDateEstimated);
    }
  }
  if (patch.providerName !== undefined) doc.providerName = String(patch.providerName).slice(0, 160) || undefined;
  if (patch.tags !== undefined) doc.tags = Array.isArray(patch.tags) ? patch.tags.slice(0, 20).map((t) => String(t).slice(0, 40)) : [];
  if (patch.notes !== undefined) doc.notes = String(patch.notes).slice(0, 2000);
  if (patch.guidelineConfirmed !== undefined) { /* no-op placeholder for explicit validation */ }
  await doc.save();
  await auditService.record(req, { action: 'document.updated', patient: patientId, entityType: 'Document', entityId: doc._id, metadata: { fields: Object.keys(patch) } });
  return { before, after: doc.toClient() };
}

/** Soft-delete a document and its auto-extracted children. */
async function deleteDocument(patientId, id, { req = null } = {}) {
  const doc = await getDocument(patientId, id);
  const now = new Date();
  doc.deletedAt = now;
  await doc.save();
  await Promise.all([
    Observation.updateMany({ sourceDocument: doc._id, patient: patientId }, { deletedAt: now }),
    Condition.updateMany({ sourceDocument: doc._id, patient: patientId }, { deletedAt: now }),
    AllergyIntolerance.updateMany({ sourceDocument: doc._id, patient: patientId }, { deletedAt: now }),
    MedicationStatement.updateMany({ sourceDocument: doc._id, patient: patientId }, { deletedAt: now }),
    Encounter.updateMany({ sourceDocument: doc._id, patient: patientId }, { deletedAt: now }),
    // Remove the document from any active shares so it can never be seen again.
    (async () => {
      const { ShareGrant } = require('../models');
      await ShareGrant.updateMany({ patient: patientId }, { $pull: { documents: doc._id } });
    })(),
  ]);
  await auditService.record(req, { action: 'document.deleted', patient: patientId, entityType: 'Document', entityId: doc._id });
  return { ok: true };
}

module.exports = {
  createDocument, listDocuments, getDocument, readDocumentFile, updateDocument, deleteDocument,
  documentFilter, ALLOWED_MIME,
};
