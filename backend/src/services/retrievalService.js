'use strict';

const {
  Observation, Condition, AllergyIntolerance, MedicationStatement, Encounter, Document,
} = require('../models');
const { normalizeTestName, normalizeDrugName } = require('../utils/clinical');

/**
 * Retrieval layer for RAG.
 *
 * Builds a corpus of small, source-attributed chunks from the patient's own
 * records and ranks them against a natural-language question using a bag-of-
 * words TF-IDF style scorer with clinical-aware boosts (exact normalized test /
 * drug name match, recency when the question asks for "latest").
 *
 * Two chunk families are produced:
 *  1. Structured clinical facts (observations, conditions, allergies,
 *     medications, encounters) that were extracted from documents.
 *  2. Document text passages - the recovered text (PDF text layer or OCR) of
 *     every in-scope document, split into overlapping passages so that notes,
 *     discharge summaries and reports that did not yield structured facts are
 *     still searchable and citable.
 *
 * Documents whose text could not be recovered are reported back as
 * `coverage.unreadable` so callers can state honestly that those files were
 * not analysed instead of pretending they were.
 *
 * This runs entirely locally - no embeddings service, no document upload to a
 * third party. A cloud provider can be swapped in via the AI provider adapter.
 */

const STOPWORDS = new Set([
  'the', 'a', 'an', 'and', 'or', 'of', 'to', 'in', 'on', 'for', 'is', 'are', 'was',
  'were', 'my', 'me', 'i', 'you', 'your', 'what', 'whats', 'which', 'show', 'list',
  'give', 'all', 'any', 'from', 'with', 'last', 'latest', 'recent', 'most', 'have',
  'has', 'had', 'do', 'does', 'did', 'about', 'please', 'can', 'could', 'would',
  'tell', 'result', 'results', 'test', 'tests', 'report', 'reports', 'record',
  'records', 'history', 'currently', 'current', 'over', 'time', 'when', 'how',
  'this', 'that', 'these', 'those', 'there', 'here', 'it', 'its', 'been', 'be',
  'am', 'is', 'it', 'we', 'our', 'us', 'they', 'them', 'their', 'document',
  'documents', 'file', 'files', 'note', 'notes', 'page', 'pages',
]);

function tokenize(text) {
  return String(text || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s.%-]/g, ' ')
    .split(/\s+/)
    .map((t) => t.trim())
    .filter((t) => t.length > 1 && !STOPWORDS.has(t));
}

function fmtDate(d) {
  if (!d) return 'date not recorded';
  const dt = new Date(d);
  if (Number.isNaN(dt.getTime())) return 'date not recorded';
  return dt.toISOString().slice(0, 10);
}

/**
 * Split recovered document text into overlapping passages so long reports are
 * retrievable at a useful granularity and each passage can cite a page window.
 */
function chunkDocumentText(text, { maxChars = 1200, overlap = 150 } = {}) {
  const clean = String(text || '').replace(/\r\n/g, '\n').trim();
  if (!clean) return [];

  // Prefer splitting on blank lines / section breaks, then fall back to size.
  const paragraphs = clean.split(/\n{2,}/);
  const chunks = [];
  let buffer = '';
  for (const para of paragraphs) {
    if ((buffer + '\n\n' + para).trim().length > maxChars && buffer) {
      chunks.push(buffer.trim());
      buffer = para.length > overlap ? para.slice(-overlap) + '\n\n' + para : para;
    } else {
      buffer = buffer ? `${buffer}\n\n${para}` : para;
    }
  }
  if (buffer.trim()) chunks.push(buffer.trim());

  return chunks.filter((c) => c.length > 0);
}

/**
 * Build retrievable chunks for a patient. Each chunk keeps a reference to the
 * underlying record or source document so answers can cite evidence.
 *
 * @returns {Promise<{chunks: Array, coverage: {documentsInScope: number, documentsWithText: number, unreadable: Array}}>}
 */
async function buildCorpus(patientId, { documentIds = null, permissions = null } = {}) {
  const scope = { patient: patientId, deletedAt: null };
  const docFilter = documentIds ? { sourceDocument: { $in: documentIds } } : {};

  const docScope = documentIds
    ? { _id: { $in: documentIds }, patient: patientId, deletedAt: null }
    : { patient: patientId, deletedAt: null };

  const [observations, conditions, allergies, medications, encounters, documents] = await Promise.all([
    permissions && permissions.observations === false
      ? []
      : Observation.find({ ...scope, ...docFilter }).populate('sourceDocument', 'originalName category eventDate').lean(),
    permissions && permissions.timeline === false
      ? []
      : Condition.find({ ...scope, ...docFilter }).populate('sourceDocument', 'originalName category eventDate').lean(),
    permissions && permissions.allergies === false
      ? []
      : AllergyIntolerance.find({ ...scope, ...docFilter }).populate('sourceDocument', 'originalName category eventDate').lean(),
    permissions && permissions.medications === false
      ? []
      : MedicationStatement.find({ ...scope, ...docFilter }).populate('sourceDocument', 'originalName category eventDate').lean(),
    permissions && permissions.timeline === false
      ? []
      : Encounter.find({ ...scope, ...docFilter }).populate('sourceDocument', 'originalName category eventDate').lean(),
    Document.find(docScope).select('+rawText originalName category eventDate providerName extractionStatus extractionError textSource pageCount').lean(),
  ]);

  const chunks = [];

  for (const o of observations) {
    chunks.push({
      id: `observation:${o._id}`,
      recordId: String(o._id),
      kind: 'observation',
      label: o.testName,
      normalized: o.normalizedTestName || normalizeTestName(o.testName),
      date: o.date,
      providerName: o.providerName,
      verification: o.verification,
      source: o.source,
      documentId: o.sourceDocument?._id ? String(o.sourceDocument._id) : null,
      documentName: o.sourceDocument?.originalName || null,
      value: o.value,
      unit: o.unit,
      referenceRange: o.referenceRange,
      abnormal: o.abnormal,
      text: `Lab test ${o.testName}${o.value != null ? ` result ${o.value}${o.unit ? ` ${o.unit}` : ''}` : ''}${o.referenceRange ? ` reference range ${o.referenceRange}` : ''} on ${fmtDate(o.date)} at ${o.providerName || 'unknown provider'}.`,
    });
  }

  for (const c of conditions) {
    chunks.push({
      id: `condition:${c._id}`,
      recordId: String(c._id),
      kind: 'condition',
      label: c.name,
      normalized: c.normalizedName || c.name.toLowerCase(),
      date: c.onsetDate,
      providerName: c.providerName,
      verification: c.verification,
      source: c.source,
      documentId: c.sourceDocument?._id ? String(c.sourceDocument._id) : null,
      documentName: c.sourceDocument?.originalName || null,
      text: `Diagnosis ${c.name} recorded on ${fmtDate(c.onsetDate)} at ${c.providerName || 'unknown provider'}.`,
    });
  }

  for (const a of allergies) {
    chunks.push({
      id: `allergy:${a._id}`,
      recordId: String(a._id),
      kind: 'allergy',
      label: a.substance,
      normalized: a.normalizedSubstance || a.substance.toLowerCase(),
      date: a.onsetDate,
      providerName: a.providerName,
      verification: a.verification,
      source: a.source,
      documentId: a.sourceDocument?._id ? String(a.sourceDocument._id) : null,
      documentName: a.sourceDocument?.originalName || null,
      reaction: a.reaction,
      severity: a.severity,
      text: `Allergy to ${a.substance}${a.reaction ? ` with reaction ${a.reaction}` : ''} (severity ${a.severity}) noted ${fmtDate(a.onsetDate)}.`,
    });
  }

  for (const m of medications) {
    chunks.push({
      id: `medication:${m._id}`,
      recordId: String(m._id),
      kind: 'medication',
      label: m.name,
      normalized: m.normalizedName || normalizeDrugName(m.name),
      date: m.startDate,
      endDate: m.endDate,
      status: m.status,
      providerName: m.providerName,
      verification: m.verification,
      source: m.source,
      documentId: m.sourceDocument?._id ? String(m.sourceDocument._id) : null,
      documentName: m.sourceDocument?.originalName || null,
      text: `Medication ${m.name}${m.strength ? ` ${m.strength}` : ''}${m.frequency ? ` ${m.frequency}` : ''}, status ${m.status}, started ${fmtDate(m.startDate)}${m.prescriber ? ` prescribed by ${m.prescriber}` : ''} at ${m.providerName || 'unknown provider'}.`,
    });
  }

  for (const e of encounters) {
    chunks.push({
      id: `encounter:${e._id}`,
      recordId: String(e._id),
      kind: 'encounter',
      label: e.diagnosis && e.diagnosis.length ? e.diagnosis.join(', ') : e.type,
      normalized: (e.diagnosis || []).join(' ').toLowerCase(),
      date: e.date,
      providerName: e.providerName,
      verification: e.verification,
      source: e.source,
      documentId: e.sourceDocument?._id ? String(e.sourceDocument._id) : null,
      documentName: e.sourceDocument?.originalName || null,
      encounterType: e.type,
      reason: e.reason,
      diagnosis: e.diagnosis || [],
      text: `${e.type} encounter on ${fmtDate(e.date)} at ${e.providerName || 'unknown provider'}${e.diagnosis && e.diagnosis.length ? ` with diagnoses ${e.diagnosis.join(', ')}` : ''}${e.reason ? ` (reason: ${e.reason})` : ''}.`,
    });
  }

  // ---- Document text passages (covers notes/reports without structured facts) ----
  const unreadable = [];
  let documentsWithText = 0;

  for (const d of documents) {
    const docId = String(d._id);
    const base = {
      kind: 'document',
      date: d.eventDate || d.createdAt,
      providerName: d.providerName,
      documentId: docId,
      documentName: d.originalName,
      category: d.category,
      verification: 'unverified',
      source: 'document-text',
    };

    const hasText = typeof d.rawText === 'string' && d.rawText.trim().length > 3;
    if (!hasText) {
      // Honest reporting: an unreadable file is not silently treated as analysed.
      if (d.extractionStatus === 'failed' || d.extractionStatus === 'pending' || d.extractionStatus === 'processing') {
        unreadable.push({
          documentId: docId,
          documentName: d.originalName,
          category: d.category,
          status: d.extractionStatus,
          reason: d.extractionError || 'No readable text could be recovered from this file (it may be a scan without a usable text layer).',
        });
      }
      continue;
    }
    documentsWithText += 1;

    const passages = chunkDocumentText(d.rawText);
    passages.forEach((passage, idx) => {
      chunks.push({
        ...base,
        id: `document:${docId}:${idx}`,
        recordId: docId,
        label: `${d.originalName} (passage ${idx + 1})`,
        passageIndex: idx,
        passageCount: passages.length,
        text: `From document ${d.originalName} (${d.category || 'uncategorised'}, ${fmtDate(base.date)})${d.providerName ? ` at ${d.providerName}` : ''}: ${passage}`,
      });
    });
  }

  const coverage = {
    documentsInScope: documents.length,
    documentsWithText,
    unreadable,
  };

  return { chunks, coverage };
}

/** Compute IDF across the corpus. */
function buildIdf(chunks) {
  const df = new Map();
  for (const c of chunks) {
    const terms = new Set(tokenize(c.text));
    for (const t of terms) df.set(t, (df.get(t) || 0) + 1);
  }
  const N = Math.max(1, chunks.length);
  const idf = new Map();
  for (const [t, n] of df.entries()) idf.set(t, Math.log((N + 1) / (n + 1)) + 1);
  return idf;
}

/**
 * Questions that ask for an overview rather than a specific fact. Ranking by
 * keyword overlap cannot answer these (there is no rare term to match), so the
 * ranker falls back to a date-spread sample of the corpus instead of
 * returning nothing.
 */
const BROAD_PATTERNS = [
  /\bsummar(y|ise|ize|izing)\b/i,
  /\bmedical history\b/i,
  /\bfull history\b/i,
  /\boverview\b/i,
  /\btimeline\b/i,
  /\bimportant (events|findings|information)\b/i,
  /\bwhat (is|are) (this patient|the patient)s? (history|background|file)\b/i,
  /\bacross (all|the) (reports|records|documents|files|results)\b/i,
  /\brecurring\b/i,
  /\bsignificant changes?\b/i,
];

function isBroadQuestion(query) {
  return BROAD_PATTERNS.some((re) => re.test(String(query || '')));
}

/**
 * A date-spread sample used for broad questions: newest records first, but
 * interleaving kinds so the sample is not 8 lab values.
 */
function diverseSample(chunks, topK) {
  const byKind = new Map();
  for (const c of chunks) {
    if (!byKind.has(c.kind)) byKind.set(c.kind, []);
    byKind.get(c.kind).push(c);
  }
  for (const list of byKind.values()) list.sort((a, b) => new Date(b.date || 0) - new Date(a.date || 0));

  const out = [];
  let added = true;
  let depth = 0;
  while (out.length < topK && added) {
    added = false;
    for (const list of byKind.values()) {
      if (list[depth]) { out.push(list[depth]); added = true; }
      if (out.length >= topK) break;
    }
    depth += 1;
  }
  return out.map((c) => ({ ...c, score: 0.5 }));
}

/**
 * Rank chunks against a question.
 * @returns {Array<chunk & { score: number }>}
 */
function rank(query, chunks, { topK = 8 } = {}) {
  if (!chunks.length) return [];
  const idf = buildIdf(chunks);
  const qTerms = tokenize(query);
  const qNorm = qTerms.join(' ');
  const wantsLatest = /\b(latest|last|most recent|current|newest|recent)\b/i.test(query);

  const scored = chunks.map((c) => {
    const terms = tokenize(`${c.label} ${c.label} ${c.text} ${c.normalized || ''}`);
    const tf = new Map();
    for (const t of terms) tf.set(t, (tf.get(t) || 0) + 1);
    let score = 0;
    for (const qt of qTerms) {
      if (tf.has(qt)) score += (1 + Math.log(tf.get(qt))) * (idf.get(qt) || 1);
    }
    // No topical overlap: leave at 0 so irrelevant records are never returned.
    // Boosts (normalized-name match, recency) must only apply to topical hits,
    // otherwise "last brain MRI" would retrieve every dated record.
    if (score === 0) return { ...c, score: 0 };
    // Clinical-aware boosts.
    if (c.normalized && qNorm.includes(c.normalized)) score += 6;
    for (const qt of qTerms) {
      if (c.normalized && (c.normalized === qt || c.normalized.includes(qt) || qt.includes(c.normalized))) score += 2;
    }
    if (wantsLatest && c.date) {
      const ageDays = (Date.now() - new Date(c.date).getTime()) / 86400000;
      score += Math.max(0, 4 - ageDays / 120); // newer records score higher
    }
    return { ...c, score: Math.round(score * 100) / 100 };
  });

  const hits = scored
    .filter((s) => s.score > 0)
    .sort((a, b) => (b.score - a.score) || (new Date(b.date || 0) - new Date(a.date || 0)))
    .slice(0, topK);

  // Broad overview questions rarely share vocabulary with the records. When
  // nothing ranks, return a representative sample rather than "no records".
  if (hits.length === 0 && isBroadQuestion(query)) {
    return diverseSample(chunks, topK);
  }
  return hits;
}

module.exports = { buildCorpus, rank, tokenize, fmtDate, chunkDocumentText, isBroadQuestion };
