'use strict';

const { fmtDate } = require('../services/retrievalService');

/**
 * Local, offline AI provider.
 *
 * This is the default provider. It is a grounded, extractive assistant: every
 * sentence it produces is derived from the retrieved source chunks, and each
 * factual claim is tagged with the source it came from. It does not call any
 * external service and does not hallucinate values - if a record is absent it
 * says so explicitly. This satisfies "retrieve before generating", "associate
 * claims with source documents", "state when information is missing" and
 * "do not invent diagnoses/results/medications" without a network dependency.
 */

const name = 'local';
const model = 'local-grounded-v1';

function byDateDesc(a, b) { return new Date(b.date || 0) - new Date(a.date || 0); }
function byDateAsc(a, b) { return new Date(a.date || 0) - new Date(b.date || 0); }

function makeCitationTracker() {
  const citations = [];
  const index = new Map();
  return {
    cite(src) {
      if (!src) return '';
      if (!index.has(src.id)) {
        index.set(src.id, citations.length + 1);
        citations.push({
          ref: citations.length + 1,
          sourceId: src.id,
          kind: src.kind,
          recordId: src.recordId,
          label: src.label,
          date: src.date || null,
          providerName: src.providerName || null,
          documentId: src.documentId || null,
          documentName: src.documentName || null,
          verification: src.verification || null,
          origin: src.source || null,
        });
      }
      return `[${index.get(src.id)}]`;
    },
    list() { return citations; },
  };
}

function detectIntents(q) {
  const s = q.toLowerCase();
  const intents = new Set();
  if (/\b(medication|medicine|drug|prescri|tablet|capsule|dose)\b/.test(s)) intents.add('medications');
  if (/\b(allerg|intoleran|reaction)\b/.test(s)) intents.add('allergies');
  if (/\b(visit|admission|admitted|hospital|encounter|discharge|consult)\b/.test(s)) intents.add('visits');
  if (/\b(condition|diagnos|diagnos(?:es|is)|problem|disease|illness)\b/.test(s)) intents.add('conditions');
  if (/\b(trend|over time|history of|progression|series)\b/.test(s)) intents.add('trend');
  if (/\b(compare|comparison|versus|vs\.?|difference between|changed)\b/.test(s)) intents.add('compare');
  if (/\b(summar|overview|medical history|full history|prepare.*(new|another) doctor|handover)\b/.test(s)) intents.add('summary');
  if (/\b(result|level|value|glucose|sugar|hb|hemoglobin|haemoglobin|cholesterol|tsh|t3|t4|creatinine|alt|ast|blood|test|measurement|reading)\b/.test(s)) intents.add('labs');
  return intents;
}

function looksLikeLab(src) { return src.kind === 'observation'; }

function formatObservation(src) {
  const val = src.value != null ? `${src.value}${src.unit ? ` ${src.unit}` : ''}` : (src.valueString || 'value not recorded');
  const ref = src.referenceRange ? ` (reference range ${src.referenceRange})` : '';
  const flag = src.abnormal === true ? ' - flagged as outside the reference range' : '';
  return `${src.label}: ${val}${ref}${flag}`;
}

/**
 * @param {object} params
 * @param {string} params.question
 * @param {Array} params.sources ranked chunks
 * @returns {Promise<{answer:string, citations:Array, uncertainty:object, provider:string, model:string, usedSources:number}>}
 */
async function answer({ question, sources }) {
  const tracker = makeCitationTracker();
  const intents = detectIntents(question);
  const lines = [];
  const caveats = [];

  const labs = sources.filter(looksLikeLab);
  const meds = sources.filter((s) => s.kind === 'medication');
  const allergies = sources.filter((s) => s.kind === 'allergy');
  const encounters = sources.filter((s) => s.kind === 'encounter');
  const conditions = sources.filter((s) => s.kind === 'condition');

  if (sources.length === 0) {
    return {
      answer: `I could not find any information in your records that relates to "${question}". `
        + 'This may mean the relevant record has not been uploaded yet, or it is stored under different wording. '
        + 'I have not found evidence either way, so I cannot answer this from your documents.',
      citations: [],
      uncertainty: { level: 'high', reason: 'No matching records were retrieved.', missing: true },
      provider: name, model, usedSources: 0,
    };
  }

  // ---- Lab results ----
  if (labs.length && (intents.has('labs') || intents.has('trend') || intents.has('compare') || intents.size === 0)) {
    const grouped = new Map();
    for (const l of labs) {
      const key = l.normalized || l.label.toLowerCase();
      if (!grouped.has(key)) grouped.set(key, []);
      grouped.get(key).push(l);
    }
    if (intents.has('compare')) {
      lines.push('Here is a comparison based on the values found in your records:');
      for (const [, group] of grouped) {
        const sorted = group.slice().sort(byDateAsc);
        const latest = sorted[sorted.length - 1];
        const previous = sorted[sorted.length - 2];
        if (!previous) {
          lines.push(`- ${latest.label}: only one result is on file - ${formatObservation(latest)} ${tracker.cite(latest)} (no earlier value to compare against).`);
          continue;
        }
        const delta = latest.value != null && previous.value != null ? latest.value - previous.value : null;
        const dir = delta == null ? '' : delta > 0 ? `an increase of ${Math.abs(delta).toFixed(2)}` : delta < 0 ? `a decrease of ${Math.abs(delta).toFixed(2)}` : 'no change';
        lines.push(`- ${latest.label}: ${formatObservation(previous)} ${tracker.cite(previous)} (${fmtDate(previous.date)}) compared with ${formatObservation(latest)} ${tracker.cite(latest)} (${fmtDate(latest.date)}) - ${dir || 'recorded change'}.`);
      }
    } else if (intents.has('trend')) {
      lines.push('Here are the values on file, oldest to newest:');
      for (const [, group] of grouped) {
        const sorted = group.slice().sort(byDateAsc);
        const parts = sorted.map((s) => `${s.value != null ? s.value : 'n/a'}${s.unit ? ` ${s.unit}` : ''} on ${fmtDate(s.date)} ${tracker.cite(s)}`);
        lines.push(`- ${sorted[0].label}: ${parts.join('; ')}.`);
      }
    } else {
      lines.push('From your records:');
      for (const [, group] of grouped) {
        const sorted = group.slice().sort(byDateDesc);
        const latest = sorted[0];
        lines.push(`- ${formatObservation(latest)} ${tracker.cite(latest)} - recorded on ${fmtDate(latest.date)}${latest.providerName ? ` at ${latest.providerName}` : ''}${sorted.length > 1 ? ` (${sorted.length} results on file)` : ''}.`);
      }
    }
  }

  // ---- Medications ----
  if (meds.length && (intents.has('medications') || intents.size === 0)) {
    const active = meds.filter((m) => m.status === 'active');
    const others = meds.filter((m) => m.status !== 'active');
    if (active.length) {
      lines.push('Medications recorded as active:');
      for (const m of active.sort(byDateDesc)) {
        lines.push(`- ${m.label}${m.unit ? ` ${m.unit}` : ''}${m.frequency ? ` ${m.frequency}` : ''}, started ${fmtDate(m.date)}${m.providerName ? ` (${m.providerName})` : ''} ${tracker.cite(m)}.`);
      }
    }
    if (others.length) {
      lines.push('Other medications on file (status not marked active):');
      for (const m of others.sort(byDateDesc)) {
        lines.push(`- ${m.label}, status ${m.status}, recorded ${fmtDate(m.date)} ${tracker.cite(m)}.`);
      }
    }
    if (!meds.length) caveats.push('No medication records were found.');
  }

  // ---- Allergies ----
  if (allergies.length && (intents.has('allergies') || intents.size === 0)) {
    lines.push('Reported allergies:');
    for (const a of allergies) {
      lines.push(`- ${a.label}${a.reaction ? ` - reaction: ${a.reaction}` : ''} (severity ${a.severity || 'unknown'}) ${tracker.cite(a)}${a.source === 'ai-extracted' ? ' - extracted from a document, review recommended' : ''}.`);
    }
  } else if (intents.has('allergies') && allergies.length === 0) {
    caveats.push('No allergy records were found in your wallet.');
  }

  // ---- Conditions ----
  if (conditions.length && (intents.has('conditions') || intents.has('summary'))) {
    lines.push('Conditions / diagnoses on file:');
    for (const c of conditions.slice().sort(byDateDesc)) {
      lines.push(`- ${c.label}, recorded ${fmtDate(c.date)}${c.providerName ? ` at ${c.providerName}` : ''} ${tracker.cite(c)}.`);
    }
  }

  // ---- Visits ----
  if (encounters.length && (intents.has('visits') || intents.has('summary'))) {
    lines.push('Hospital visits and consultations:');
    for (const e of encounters.slice().sort(byDateDesc)) {
      const dx = e.diagnosis && e.diagnosis.length ? ` - ${e.diagnosis.join(', ')}` : '';
      lines.push(`- ${e.encounterType || 'encounter'} on ${fmtDate(e.date)} at ${e.providerName || 'unknown provider'}${dx} ${tracker.cite(e)}.`);
    }
  }

  // ---- Summary intent: pull everything together ----
  if (intents.has('summary') && lines.length === 0) {
    lines.push('Here is a summary drawn from your records:');
    if (conditions.length) lines.push(`- Conditions: ${conditions.map((c) => `${c.label} ${tracker.cite(c)}`).join(', ')}.`);
    if (allergies.length) lines.push(`- Allergies: ${allergies.map((a) => `${a.label} ${tracker.cite(a)}`).join(', ')}.`);
    if (meds.length) lines.push(`- Medications: ${meds.slice(0, 10).map((m) => `${m.label} ${tracker.cite(m)}`).join(', ')}.`);
    if (encounters.length) lines.push(`- Visits: ${encounters.slice(0, 10).map((e) => `${fmtDate(e.date)} at ${e.providerName || 'unknown provider'} ${tracker.cite(e)}`).join('; ')}.`);
    if (labs.length) lines.push(`- Recent results: ${labs.slice(0, 8).map((l) => `${l.label} ${l.value ?? ''}${l.unit ? ` ${l.unit}` : ''} (${fmtDate(l.date)}) ${tracker.cite(l)}`).join('; ')}.`);
  }

  if (lines.length === 0) {
    // Nothing matched an explicit intent - fall back to the top retrieved chunks.
    lines.push('Here are the closest matching records I found:');
    for (const s of sources.slice(0, 5)) {
      lines.push(`- ${s.text} ${tracker.cite(s)}`);
    }
    caveats.push('Your question did not match a specific category, so I have listed the most relevant records instead.');
  }

  let answer = lines.join('\n');

  // Uncertainty handling
  const unverified = sources.filter((s) => s.verification === 'unverified' || s.source === 'ai-extracted').length;
  const uncertaintyLevel = unverified > sources.length / 2 ? 'medium' : 'low';
  const uncertainty = {
    level: uncertaintyLevel,
    reason: unverified ? `${unverified} of ${sources.length} supporting record(s) are unverified or machine-extracted.` : 'All supporting records are verified or patient-entered.',
    missing: false,
  };

  if (caveats.length) answer += `\n\nNote: ${caveats.join(' ')}`;
  answer += '\n\nThis is a summary of your own records, not medical advice. Please confirm anything important with a clinician.';

  return { answer, citations: tracker.list(), uncertainty, provider: name, model, usedSources: sources.length };
}

/**
 * Produce a structured medical summary. Every section is grounded in the input
 * records and carries citations; missing data is explicitly listed.
 */
async function summarize({ records }) {
  const tracker = makeCitationTracker();
  const sections = {
    conditions: [], allergies: [], currentMedications: [], historicalMedications: [],
    labTrends: [], visits: [], recentTreatments: [],
  };

  for (const c of records.conditions || []) {
    sections.conditions.push({ text: `${c.label}`, citation: tracker.cite(c), date: c.date || null, verification: c.verification });
  }
  for (const a of records.allergies || []) {
    sections.allergies.push({ text: `${a.label}${a.reaction ? ` - ${a.reaction}` : ''} (severity ${a.severity || 'unknown'})`, citation: tracker.cite(a), verification: a.verification });
  }
  for (const m of records.medications || []) {
    const entry = { text: `${m.label}${m.strength ? ` ${m.strength}` : ''}${m.frequency ? ` ${m.frequency}` : ''}`, citation: tracker.cite(m), status: m.status, date: m.date || null, verification: m.verification };
    if (m.status === 'active') sections.currentMedications.push(entry);
    else sections.historicalMedications.push(entry);
  }
  for (const o of records.observations || []) {
    sections.labTrends.push({
      text: `${o.label}: ${o.value ?? o.valueString ?? 'n/a'}${o.unit ? ` ${o.unit}` : ''}${o.referenceRange ? ` (ref ${o.referenceRange})` : ''}${o.abnormal ? ' [outside reference range]' : ''} on ${fmtDate(o.date)}`,
      citation: tracker.cite(o), date: o.date || null, verification: o.verification, test: o.label,
    });
  }
  for (const e of records.encounters || []) {
    sections.visits.push({ text: `${e.encounterType || 'encounter'} at ${e.providerName || 'unknown provider'}${e.diagnosis?.length ? ` - ${e.diagnosis.join(', ')}` : ''} on ${fmtDate(e.date)}`, citation: tracker.cite(e), date: e.date || null });
  }

  const missing = [];
  if (!sections.conditions.length) missing.push('No confirmed conditions are recorded.');
  if (!sections.allergies.length) missing.push('No allergies are recorded (this does not mean there are none).');
  if (!sections.currentMedications.length) missing.push('No active medications are recorded.');
  if (!sections.labTrends.length) missing.push('No laboratory results are recorded.');
  const unverifiedCount = (records.observations || []).concat(records.medications || [], records.conditions || [], records.allergies || [])
    .filter((r) => r.verification !== 'verified').length;
  if (unverifiedCount) missing.push(`${unverifiedCount} item(s) are unverified or machine-extracted and should be reviewed.`);

  const generatedAt = new Date().toISOString();
  const narrativeParts = [];
  if (sections.conditions.length) narrativeParts.push(`Recorded conditions: ${sections.conditions.map((c) => c.text).join(', ')}.`);
  if (sections.allergies.length) narrativeParts.push(`Reported allergies: ${sections.allergies.map((a) => a.text).join(', ')}.`);
  if (sections.currentMedications.length) narrativeParts.push(`Current medications: ${sections.currentMedications.map((m) => m.text).join(', ')}.`);
  if (sections.labTrends.length) narrativeParts.push(`Recent laboratory results: ${sections.labTrends.slice(0, 10).map((l) => l.text).join('; ')}.`);
  if (sections.visits.length) narrativeParts.push(`Recent visits: ${sections.visits.slice(0, 8).map((v) => v.text).join('; ')}.`);

  return {
    sections,
    narrative: narrativeParts.join(' '),
    missing,
    citations: tracker.list(),
    generatedAt,
    provider: name,
    model,
    disclaimer: 'This is an automatically generated summary of your stored records for reference and sharing. It is not a diagnosis and not verified medical advice.',
  };
}

module.exports = { name, model, available: true, answer, summarize };
