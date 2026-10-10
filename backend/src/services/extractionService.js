'use strict';

const mongoose = require('mongoose');
const {
  Document, ExtractionJob, Observation, Condition, AllergyIntolerance,
  MedicationStatement, Encounter, Provider,
} = require('../models');
const { getStorage } = require('../storage');
const pdf = require('./extraction/pdf');
const ocr = require('./extraction/ocr');
const { extractStructured } = require('./extraction/structuredExtractor');
const { validateExtraction } = require('./extraction/schema');
const { normalizeTestName, normalizeDrugName, extractStrength, dosageForm } = require('../utils/clinical');
const notificationService = require('./notificationService');
const auditService = require('./auditService');
const logger = require('../utils/logger');

const IMAGE_MIME = ['image/png', 'image/jpeg', 'image/jpg', 'image/webp', 'image/tiff', 'image/bmp'];

/**
 * Recover text from a stored document using the appropriate path:
 * PDF text layer -> PDF OCR -> image OCR.
 */
async function recoverText(buffer, mimeType) {
  if (mimeType === 'application/pdf') return pdf.extractPdfText(buffer);
  if (IMAGE_MIME.includes(mimeType)) return pdf.extractImageText(buffer);
  if (mimeType.startsWith('text/')) {
    return { text: buffer.toString('utf8'), source: 'pdf-text', pageCount: 1, ocrConfidence: null, warnings: [] };
  }
  return { text: '', source: 'none', pageCount: 0, ocrConfidence: null, warnings: [`Unsupported MIME type for text extraction: ${mimeType}`] };
}

/** Find or create a provider by name (fictional flag respected). */
async function resolveProvider(name, patientId) {
  if (!name) return { providerId: null, providerName: null };
  const existing = await Provider.findOne({ name: new RegExp(`^${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') });
  if (existing) return { providerId: existing._id, providerName: existing.name };
  const created = await Provider.create({ name, type: 'other', fictional: false, createdBy: patientId });
  return { providerId: created._id, providerName: created.name };
}

/**
 * Persist validated structured extraction as FHIR-ish resources, all linked to
 * the source document and marked `ai-extracted` + `unverified`.
 */
async function persistExtraction(document, validated, { providerId, providerName }) {
  const patient = document.patient;
  const eventDate = (validated.eventDate ? new Date(validated.eventDate) : document.eventDate) || null;
  const dateEstimated = validated.eventDateEstimated ?? document.eventDateEstimated ?? false;
  const base = {
    patient,
    source: 'ai-extracted',
    verification: 'unverified',
    sourceDocument: document._id,
    provider: providerId || undefined,
    providerName: providerName || document.providerName || undefined,
  };

  const stats = { observations: 0, conditions: 0, allergies: 0, medications: 0, encounters: 0 };

  // Encounter (one per document, when it looks like a clinical event)
  if (validated.conditions.length || validated.documentType === 'consultation_note' || validated.documentType === 'discharge_summary') {
    await Encounter.create({
      ...base,
      type: validated.documentType === 'discharge_summary' ? 'discharge'
        : validated.documentType === 'consultation_note' ? 'consultation' : 'other',
      date: eventDate,
      dateEstimated,
      diagnosis: validated.conditions.map((c) => c.name),
    });
    stats.encounters += 1;
  }

  for (const o of validated.observations) {
    await Observation.create({
      ...base,
      testName: o.testName,
      normalizedTestName: normalizeTestName(o.testName),
      value: o.value,
      unit: o.unit || undefined,
      referenceRange: o.referenceRange || undefined,
      abnormal: o.abnormal,
      date: eventDate,
      dateEstimated,
      confidence: 0.7,
    });
    stats.observations += 1;
  }

  for (const c of validated.conditions) {
    await Condition.create({
      ...base,
      name: c.name,
      normalizedName: c.name.toLowerCase(),
      onsetDate: eventDate,
      status: 'unknown',
      confidence: 0.6,
    });
    stats.conditions += 1;
  }

  for (const a of validated.allergies) {
    await AllergyIntolerance.create({
      ...base,
      substance: a.substance,
      normalizedSubstance: a.substance.toLowerCase(),
      reaction: a.reaction || undefined,
      severity: a.severity,
      onsetDate: eventDate,
      confidence: 0.6,
    });
    stats.allergies += 1;
  }

  for (const m of validated.medications) {
    await MedicationStatement.create({
      ...base,
      name: m.name,
      normalizedName: normalizeDrugName(m.name),
      strength: m.strength || extractStrength(m.name) || undefined,
      dose: m.dose || undefined,
      frequency: m.frequency || undefined,
      route: m.route || undefined,
      form: m.form || dosageForm(m.name) || undefined,
      startDate: eventDate,
      status: 'unknown',
      confidence: 0.6,
    });
    stats.medications += 1;
  }

  return stats;
}

/**
 * Run the full extraction pipeline for a document. Idempotent: a document is
 * only extracted once unless `force` is set (used by the retry endpoint, which
 * first clears previously auto-extracted child resources).
 */
async function runExtraction(documentId, { force = false, req = null } = {}) {
  const doc = await Document.findById(documentId);
  if (!doc || doc.deletedAt) return { status: 'failed', error: 'Document not found' };

  if (doc.extractionStatus === 'extracted' && !force) {
    return { status: 'skipped', reason: 'already extracted' };
  }
  if (doc.extractionStatus === 'manual' && !force) {
    return { status: 'skipped', reason: 'manual document' };
  }

  const job = await ExtractionJob.create({ document: doc._id, patient: doc.patient, status: 'running', startedAt: new Date(), attempts: 1 });
  doc.extractionStatus = 'processing';
  await doc.save();

  try {
    if (force) {
      // Remove prior auto-extracted children so retry does not duplicate data.
      await Promise.all([
        Observation.deleteMany({ sourceDocument: doc._id, source: 'ai-extracted' }),
        Condition.deleteMany({ sourceDocument: doc._id, source: 'ai-extracted' }),
        AllergyIntolerance.deleteMany({ sourceDocument: doc._id, source: 'ai-extracted' }),
        MedicationStatement.deleteMany({ sourceDocument: doc._id, source: 'ai-extracted' }),
        Encounter.deleteMany({ sourceDocument: doc._id, source: 'ai-extracted' }),
      ]);
    }

    const storage = getStorage();
    const buffer = await storage.read(doc.storageKey);
    const recovered = await recoverText(buffer, doc.mimeType);

    if (!recovered.text || recovered.text.trim().length < 3) {
      doc.extractionStatus = 'failed';
      doc.extractionError = recovered.warnings.join(' ') || 'No text could be recovered from the document.';
      doc.textSource = recovered.source;
      doc.pageCount = recovered.pageCount || doc.pageCount;
      await doc.save();
      await ExtractionJob.findByIdAndUpdate(job._id, { status: 'failed', lastError: doc.extractionError, finishedAt: new Date() });
      await notificationService.notify(doc.patient, {
        type: 'extraction_failed',
        title: 'Document could not be processed',
        body: 'Text extraction failed. You can retry or enter the details manually.',
        refType: 'Document', refId: doc._id,
      });
      return { status: 'failed', error: doc.extractionError, warnings: recovered.warnings };
    }

    doc.rawText = recovered.text;
    doc.textSource = recovered.source;
    doc.pageCount = recovered.pageCount || doc.pageCount;

    const raw = extractStructured(recovered.text);
    let validated;
    try {
      validated = validateExtraction(raw);
    } catch (validationError) {
      doc.extractionStatus = 'failed';
      doc.extractionError = `Extraction output failed schema validation: ${validationError.message}`;
      await doc.save();
      await ExtractionJob.findByIdAndUpdate(job._id, { status: 'failed', lastError: doc.extractionError, finishedAt: new Date() });
      return { status: 'failed', error: doc.extractionError };
    }

    // Metadata resolution: prefer explicit document metadata, else inferred.
    const providerName = doc.providerName || validated.providerName;
    const { providerId, providerName: resolvedName } = await resolveProvider(providerName, doc.patient);
    if (providerId) { doc.provider = providerId; doc.providerName = resolvedName; }
    if (!doc.eventDate && validated.eventDate) {
      doc.eventDate = new Date(validated.eventDate);
      doc.eventDateEstimated = validated.eventDateEstimated ?? false;
    }
    if (!doc.category || doc.category === 'other') doc.category = validated.documentType;

    const stats = await persistExtraction(doc, validated, { providerId, providerName: resolvedName });

    doc.extractionStatus = 'extracted';
    doc.extractedAt = new Date();
    doc.extractionError = undefined;
    await doc.save();

    await ExtractionJob.findByIdAndUpdate(job._id, {
      status: 'succeeded',
      finishedAt: new Date(),
      stats: { pageCount: doc.pageCount, textChars: recovered.text.length, ...stats },
    });

    await notificationService.notify(doc.patient, {
      type: 'document',
      title: 'Document processed',
      body: 'Information was extracted and is ready for your review.',
      refType: 'Document', refId: doc._id,
    });
    await auditService.record(req, {
      action: 'document.extracted', patient: doc.patient, entityType: 'Document', entityId: doc._id,
      metadata: { textSource: recovered.source, pageCount: doc.pageCount },
    });

    return {
      status: 'extracted',
      stats,
      warnings: recovered.warnings,
      reviewNotes: validated.reviewNotes,
      textSource: recovered.source,
      ocrConfidence: recovered.ocrConfidence,
    };
  } catch (err) {
    logger.error('Extraction pipeline error: %s', err.message);
    doc.extractionStatus = 'failed';
    doc.extractionError = 'Unexpected error during extraction. You can retry.';
    await doc.save().catch(() => {});
    await ExtractionJob.findByIdAndUpdate(job._id, { status: 'failed', lastError: err.message, finishedAt: new Date() }).catch(() => {});
    return { status: 'failed', error: doc.extractionError };
  }
}

/** Recover text only (no persistence) - used by the "preview extraction" flow. */
async function previewText(buffer, mimeType) {
  return recoverText(buffer, mimeType);
}

module.exports = { runExtraction, recoverText, previewText, persistExtraction, IMAGE_MIME, resolveProvider };
