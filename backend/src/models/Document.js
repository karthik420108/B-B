'use strict';
const mongoose = require('mongoose');

const DOCUMENT_CATEGORIES = [
  'prescription',
  'laboratory',
  'imaging',
  'discharge_summary',
  'consultation_note',
  'vaccination',
  'other',
];

const DOCUMENT_SOURCES = ['upload', 'camera', 'gallery', 'manual', 'api'];
const EXTRACTION_STATUS = ['pending', 'processing', 'extracted', 'failed', 'manual'];

/**
 * A stored medical document (the original artifact) plus its provenance and
 * extraction state. Extracted clinical facts are stored as separate FHIR-ish
 * resources that reference this document.
 */
const documentSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    uploadedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    originalName: { type: String, required: true },
    /** Opaque storage key. Raw filesystem paths are never exposed over the API. */
    storageKey: { type: String, required: true },
    mimeType: { type: String, required: true },
    size: { type: Number, required: true },
    sha256: { type: String, index: true },
    category: { type: String, enum: DOCUMENT_CATEGORIES, default: 'other', index: true },
    provider: { type: mongoose.Schema.Types.ObjectId, ref: 'Provider', index: true },
    providerName: { type: String, trim: true },
    eventDate: Date,
    eventDateEstimated: { type: Boolean, default: false },
    source: { type: String, enum: DOCUMENT_SOURCES, default: 'upload' },
    pageCount: { type: Number, default: 0 },
    tags: { type: [String], default: [] },
    extractionStatus: { type: String, enum: EXTRACTION_STATUS, default: 'pending', index: true },
    extractionError: { type: String },
    extractedAt: Date,
    /** Raw text recovered from the document (PDF text layer or OCR). */
    rawText: { type: String, select: false },
    textSource: { type: String, enum: ['pdf-text', 'ocr', 'none'] },
    notes: { type: String },
    deletedAt: { type: Date, index: true },
  },
  { timestamps: true }
);

documentSchema.index({ patient: 1, eventDate: -1 });
documentSchema.index({ patient: 1, category: 1, eventDate: -1 });
documentSchema.index({ originalName: 'text', providerName: 'text' });

documentSchema.methods.toClient = function toClient() {
  return {
    id: this._id,
    patient: this.patient,
    originalName: this.originalName,
    mimeType: this.mimeType,
    size: this.size,
    category: this.category,
    provider: this.provider,
    providerName: this.providerName,
    eventDate: this.eventDate || null,
    eventDateEstimated: this.eventDateEstimated,
    source: this.source,
    pageCount: this.pageCount,
    tags: this.tags,
    extractionStatus: this.extractionStatus,
    extractionError: this.extractionError,
    textSource: this.textSource,
    notes: this.notes,
    createdAt: this.createdAt,
    updatedAt: this.updatedAt,
    fileUrl: `/api/documents/${this._id}/file`,
  };
};

module.exports = mongoose.model('Document', documentSchema);
module.exports.DOCUMENT_CATEGORIES = DOCUMENT_CATEGORIES;
module.exports.DOCUMENT_SOURCES = DOCUMENT_SOURCES;
module.exports.EXTRACTION_STATUS = EXTRACTION_STATUS;
