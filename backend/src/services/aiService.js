'use strict';

const { Observation, Condition, AllergyIntolerance, MedicationStatement, Encounter } = require('../models');
const retrieval = require('./retrievalService');
const ai = require('../ai');
const auditService = require('./auditService');

/**
 * Answer a question strictly from the patient's own records using RAG:
 * retrieve -> ground -> generate -> attach citations.
 * The patient scope is enforced here; a patient can only ever query their own data.
 */
async function ask(patientId, question, { req = null, topK = 8, documentIds = null } = {}) {
  const corpus = await retrieval.buildCorpus(patientId, { documentIds });
  const sources = retrieval.rank(question, corpus, { topK });
  const provider = ai.getProvider();

  let result;
  try {
    result = await provider.answer({ question, sources, patientName: null });
  } catch (err) {
    // Cloud provider failure must be recoverable: fall back to local grounding.
    const local = require('../ai/localProvider');
    result = await local.answer({ question, sources });
    result.uncertainty = { ...result.uncertainty, level: 'high', reason: `The configured AI provider failed (${err.message}); an offline grounded answer was produced instead.` };
  }

  await auditService.record(req, {
    action: 'ai.question_answered', patient: patientId,
    metadata: { usedSources: result.usedSources, provider: result.provider, retrieved: sources.length },
  });

  return {
    question,
    answer: result.answer,
    citations: result.citations,
    uncertainty: result.uncertainty,
    provider: result.provider,
    model: result.model,
    retrievedCount: sources.length,
    grounded: true,
    disclaimer: 'Answers are generated only from your stored records and are not medical advice.',
  };
}

/**
 * Build a structured, source-linked medical summary of the patient's records.
 */
async function medicalSummary(patientId, { req = null } = {}) {
  const scope = { patient: patientId, deletedAt: null };
  const [observations, conditions, allergies, medications, encounters] = await Promise.all([
    Observation.find(scope).sort({ date: -1 }).limit(200).lean(),
    Condition.find(scope).sort({ onsetDate: -1 }).limit(100).lean(),
    AllergyIntolerance.find(scope).limit(100).lean(),
    MedicationStatement.find(scope).sort({ startDate: -1 }).limit(200).lean(),
    Encounter.find(scope).sort({ date: -1 }).limit(100).lean(),
  ]);

  const asChunk = (kind, r, label, date, extra = {}) => ({
    id: `${kind}:${r._id}`,
    recordId: String(r._id),
    kind,
    label,
    date,
    providerName: r.providerName,
    verification: r.verification,
    source: r.source,
    documentId: r.sourceDocument ? String(r.sourceDocument) : null,
    documentName: null,
    ...extra,
  });

  const records = {
    observations: observations.map((o) => asChunk('observation', o, o.testName, o.date, {
      value: o.value, valueString: o.valueString, unit: o.unit, referenceRange: o.referenceRange, abnormal: o.abnormal,
      text: `${o.testName} ${o.value ?? ''} ${o.unit || ''}`.trim(),
    })),
    conditions: conditions.map((c) => asChunk('condition', c, c.name, c.onsetDate, { text: c.name })),
    allergies: allergies.map((a) => asChunk('allergy', a, a.substance, a.onsetDate, { reaction: a.reaction, severity: a.severity, text: a.substance })),
    medications: medications.map((m) => asChunk('medication', m, m.name, m.startDate, { status: m.status, strength: m.strength, frequency: m.frequency, text: `${m.name} ${m.strength || ''}`.trim() })),
    encounters: encounters.map((e) => asChunk('encounter', e, (e.diagnosis || []).join(', ') || e.type, e.date, { encounterType: e.type, diagnosis: e.diagnosis, text: `${e.type} ${(e.diagnosis || []).join(', ')}` })),
  };

  const provider = ai.getProvider();
  const summary = await provider.summarize({ records });

  await auditService.record(req, { action: 'ai.summary_generated', patient: patientId, metadata: { provider: summary.provider } });

  return {
    ...summary,
    counts: {
      conditions: records.conditions.length,
      allergies: records.allergies.length,
      medications: records.medications.length,
      observations: records.observations.length,
      encounters: records.encounters.length,
    },
  };
}

module.exports = { ask, medicalSummary };
