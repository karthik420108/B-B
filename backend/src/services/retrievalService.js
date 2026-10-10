'use strict';

const {
  Observation, Condition, AllergyIntolerance, MedicationStatement, Encounter,
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
 * Build retrievable chunks for a patient. Each chunk keeps a reference to the
 * underlying record and its source document so answers can cite evidence.
 */
async function buildCorpus(patientId, { documentIds = null } = {}) {
  const scope = { patient: patientId, deletedAt: null };
  const docFilter = documentIds ? { sourceDocument: { $in: documentIds } } : {};

  const [observations, conditions, allergies, medications, encounters] = await Promise.all([
    Observation.find({ ...scope, ...docFilter }).populate('sourceDocument', 'originalName category eventDate').lean(),
    Condition.find({ ...scope, ...docFilter }).populate('sourceDocument', 'originalName category eventDate').lean(),
    AllergyIntolerance.find({ ...scope, ...docFilter }).populate('sourceDocument', 'originalName category eventDate').lean(),
    MedicationStatement.find({ ...scope, ...docFilter }).populate('sourceDocument', 'originalName category eventDate').lean(),
    Encounter.find({ ...scope, ...docFilter }).populate('sourceDocument', 'originalName category eventDate').lean(),
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

  return chunks;
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
 * Rank chunks against a question.
 * @returns {Array<chunk & { score: number }>}
 */
function rank(query, chunks, { topK = 8 } = {}) {
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

  return scored
    .filter((s) => s.score > 0)
    .sort((a, b) => (b.score - a.score) || (new Date(b.date || 0) - new Date(a.date || 0)))
    .slice(0, topK);
}

module.exports = { buildCorpus, rank, tokenize, fmtDate };
