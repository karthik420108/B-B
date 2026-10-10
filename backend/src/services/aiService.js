'use strict';

const { Observation, Condition, AllergyIntolerance, MedicationStatement, Encounter, DoctorConversation } = require('../models');
const retrieval = require('./retrievalService');
const ai = require('../ai');
const auditService = require('./auditService');
const { forbidden } = require('../utils/errors');

/** How many prior turns are replayed into retrieval + generation as context. */
const HISTORY_TURNS = 4;

/**
 * A short, deterministic gloss of the recent turns used to enrich retrieval for
 * follow-up questions ("what about the previous report?"). Only question text
 * is used - never the previous answer - so context cannot smuggle in claims.
 */
function historyQuery(history) {
  if (!Array.isArray(history) || history.length === 0) return '';
  return history
    .slice(-HISTORY_TURNS)
    .map((m) => (m && m.role === 'doctor' ? String(m.content || '') : ''))
    .filter(Boolean)
    .join(' ')
    .slice(0, 400);
}

/**
 * Answer a question strictly from the patient's own records using RAG:
 * retrieve -> ground -> generate -> attach citations.
 * The patient scope is enforced here; a patient can only ever query their own data.
 */
async function ask(patientId, question, { req = null, topK = 8, documentIds = null } = {}) {
  const { chunks: corpus, coverage } = await retrieval.buildCorpus(patientId, { documentIds });
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
    coverage,
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

/**
 * Doctor-facing question answering, strictly bounded to records authorized by
 * an active share.
 *
 * Supports multi-turn conversation scoped to (grant, doctor). The caller is
 * responsible for re-validating the grant on every request; this function only
 * ever reads records inside the supplied grant's scope.
 *
 * @param {Array<{role:string,content:string}>} [options.history] prior turns
 */
async function askDoctor(patientId, question, {
  req = null, topK = 8, grant, allowedIds = null, doctorUser = null, history = null,
} = {}) {
  const documentIds = grant.includeAll ? null : allowedIds;
  const permissions = {
    observations: grant.includeObservations,
    timeline: grant.includeTimeline,
    allergies: grant.includeAllergies,
    medications: grant.includeMedications,
  };
  const { chunks: corpus, coverage } = await retrieval.buildCorpus(patientId, { documentIds, permissions });

  // Follow-ups like "what about the previous report?" carry little vocabulary
  // of their own, so retrieval is enriched with the doctor's earlier questions.
  const priorTerms = historyQuery(history);
  const retrievalQuery = priorTerms ? `${question} ${priorTerms}` : question;
  let sources = retrieval.rank(retrievalQuery, corpus, { topK });
  if (priorTerms && sources.length === 0) sources = retrieval.rank(question, corpus, { topK });

  const provider = ai.getProvider();

  let result;
  try {
    result = await provider.answer({
      question, sources, isDoctor: true, patientName: grant.patientName || null, history: history || [],
    });
  } catch (err) {
    const local = require('../ai/localProvider');
    result = await local.answer({
      question, sources, isDoctor: true, patientName: grant.patientName || null, history: history || [],
    });
    result.uncertainty = { ...result.uncertainty, level: 'high', reason: `The configured AI provider failed (${err.message}); an offline grounded answer was produced instead.` };
  }

  // Unreadable files are reported, never silently treated as analysed.
  if (coverage && coverage.unreadable && coverage.unreadable.length) {
    const names = coverage.unreadable.map((u) => u.documentName).slice(0, 5).join(', ');
    const note = `${coverage.unreadable.length} file(s) could not be analysed because no readable text could be recovered: ${names}. Any answer below is based only on the ${coverage.documentsWithText} readable file(s).`;
    result.answer = `${result.answer}\n\n[Limitation] ${note}`;
    result.uncertainty = {
      ...(result.uncertainty || { level: 'low' }),
      level: 'high',
      reason: [result.uncertainty && result.uncertainty.reason, note].filter(Boolean).join(' '),
    };
  }

  await auditService.record(req, {
    action: 'ai.doctor_question_answered',
    patient: patientId,
    actor: doctorUser?._id,
    actorRole: 'doctor',
    entityType: 'ShareGrant',
    entityId: grant._id,
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
    coverage,
    grounded: true,
    disclaimer: 'Grounded in authorized patient records covered by active share grant. Clinical decision-making remains with the attending physician.',
  };
}

/**
 * Conversation persistence scoped to (grant, doctor). Access is never implied
 * by a stored thread - routes re-validate the grant before calling these.
 */
async function loadConversation(grant, doctorUser) {
  const doc = await DoctorConversation.findOne({ grant: grant._id, doctor: doctorUser._id }).lean();
  return doc && Array.isArray(doc.messages) ? doc.messages : [];
}

async function appendConversation(grant, doctorUser, patientId, question, answer) {
  const cited = (Array.isArray(answer.citations) ? answer.citations : [])
    .map((c) => c.documentName || c.label || c.sourceId)
    .filter(Boolean)
    .slice(0, 10);

  await DoctorConversation.findOneAndUpdate(
    { grant: grant._id, doctor: doctorUser._id },
    {
      $set: { patient: patientId, lastQuestionAt: new Date() },
      $push: {
        messages: {
          $each: [
            { role: 'doctor', content: String(question).slice(0, 1000), at: new Date() },
            { role: 'assistant', content: String(answer.answer || '').slice(0, 4000), citations: cited, at: new Date() },
          ],
        },
      },
    },
    { upsert: true, setDefaultsOnInsert: true }
  );

  // Trim on the document so we do not grow unbounded. (Best-effort.)
  const doc = await DoctorConversation.findOne({ grant: grant._id, doctor: doctorUser._id });
  if (doc && typeof doc.trimMessages === 'function' && doc.messages.length > 12) {
    doc.trimMessages(12);
    await doc.save().catch(() => {});
  }
}

async function resetConversation(grant, doctorUser) {
  await DoctorConversation.deleteOne({ grant: grant._id, doctor: doctorUser._id });
}

/**
 * End-to-end doctor ask flow shared by the grant-id and token routes.
 * The caller must already have authenticated the doctor AND re-validated the
 * grant (status/expiry/doctor binding). This adds:
 *  - scope enforcement for explicitly requested files,
 *  - conversation load/persist scoped to (grant, doctor).
 */
async function answerDoctorQuestion({ req, grant, doctorUser, allowedIds, body }) {
  let focusIds = null;
  if (Array.isArray(body.documentIds) && body.documentIds.length) {
    const allowed = new Set(allowedIds.map(String));
    const requested = body.documentIds.map(String);
    const outside = requested.filter((id) => !allowed.has(id));
    if (outside.length) {
      await auditService.record(req, {
        action: 'share.denied.file_out_of_scope',
        patient: grant.patient,
        entityType: 'ShareGrant', entityId: grant._id,
        metadata: { requested: requested.length, outside: outside.length },
      });
      throw forbidden('One or more requested files are not included in this share.');
    }
    focusIds = allowedIds.filter((id) => requested.includes(String(id)));
  }

  if (body.resetConversation) await resetConversation(grant, doctorUser);
  const history = await loadConversation(grant, doctorUser);

  const answer = await askDoctor(grant.patient, body.question, {
    req,
    topK: body.topK || 8,
    grant,
    allowedIds: focusIds || allowedIds,
    doctorUser,
    history,
  });

  await appendConversation(grant, doctorUser, grant.patient, body.question, answer).catch(() => {});
  return { ...answer, conversationTurns: history.length };
}

module.exports = {
  ask, askDoctor, medicalSummary, loadConversation, appendConversation, resetConversation,
  answerDoctorQuestion,
};
