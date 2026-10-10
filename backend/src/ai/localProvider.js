'use strict';

const { fmtDate, tokenize: tokenizeLocal } = require('../services/retrievalService');

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

function detectIntents(q, history = []) {
  // Follow-ups carry little vocabulary ("what about the previous report?"), so
  // intent detection also considers the doctor's earlier questions. Only prior
  // question text is used - never the previous answer.
  const context = Array.isArray(history)
    ? history.filter((m) => m && m.role === 'doctor').map((m) => String(m.content || '')).join(' ')
    : '';
  const s = `${q} ${context}`.toLowerCase();
  const intents = new Set();
  if (/\b(medication|medicine|drug|prescri|tablet|capsule|dose)\b/.test(s)) intents.add('medications');
  if (/\b(allerg|intoleran|reaction)\b/.test(s)) intents.add('allergies');
  if (/\b(visit|admission|admitted|hospital|encounter|discharge|consult)\b/.test(s)) intents.add('visits');
  if (/\b(condition|diagnos|diagnos(?:es|is)|problem|disease|illness)\b/.test(s)) intents.add('conditions');
  if (/\b(trend|over time|history of|progression|series)\b/.test(s)) intents.add('trend');
  if (/\b(compare|comparison|versus|vs\.?|difference between|changed|previous|earlier|prior|six months|both)\b/.test(s)) intents.add('compare');
  if (/\b(summar|overview|medical history|full history|prepare.*(new|another) doctor|handover)\b/.test(s)) intents.add('summary');
  if (/\b(result|level|value|glucose|sugar|hb|hemoglobin|haemoglobin|cholesterol|tsh|t3|t4|creatinine|alt|ast|blood|test|measurement|reading)\b/.test(s)) intents.add('labs');
  if (/\b(repeat|repeated|duplicate|redundant)\b/.test(s)) intents.add('duplicates');
  if (/\b(missing|gap|unverified|incomplete|absent)\b/.test(s)) intents.add('missing');
  if (/\b(extract|document|scan|letter|summary of the (file|document)|readable|illegible|unreadable)\b/.test(s)) intents.add('documents');
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
 * @param {boolean} [params.isDoctor=false]
 * @param {string} [params.patientName]
 * @param {Array} [params.history] prior turns (doctor questions only are used)
 * @returns {Promise<{answer:string, citations:Array, uncertainty:object, provider:string, model:string, usedSources:number}>}
 */
async function answer({ question, sources, isDoctor = false, patientName = null, history = [] }) {
  const tracker = makeCitationTracker();
  const intents = detectIntents(question, history);
  const lines = [];
  const caveats = [];

  const labs = sources.filter(looksLikeLab);
  const meds = sources.filter((s) => s.kind === 'medication');
  const allergies = sources.filter((s) => s.kind === 'allergy');
  const encounters = sources.filter((s) => s.kind === 'encounter');
  const conditions = sources.filter((s) => s.kind === 'condition');
  const documents = sources.filter((s) => s.kind === 'document');

  // A follow-up with almost no vocabulary of its own inherits the prior intent
  // so "what about the previous report?" still reads as a compare question.
  const bareFollowUp = tokenizeLocal(question).length <= 3 && Array.isArray(history) && history.length > 0;
  if (bareFollowUp && intents.size === 0) {
    for (const prev of history.filter((m) => m && m.role === 'doctor').slice(-1)) {
      for (const i of detectIntents(String(prev.content || ''), [])) intents.add(i);
    }
  }

  if (sources.length === 0) {
    const emptyMsg = isDoctor
      ? `No relevant records were found in this patient's authorized share regarding "${question}". This patient may not have shared the relevant documents, or the information has not been recorded.`
      : `I could not find any information in your records that relates to "${question}". `
        + 'This may mean the relevant record has not been uploaded yet, or it is stored under different wording. '
        + 'I have not found evidence either way, so I cannot answer this from your documents.';
    return {
      answer: emptyMsg,
      citations: [],
      uncertainty: { level: 'high', reason: 'No matching records were retrieved from authorized scope.', missing: true },
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
      lines.push('Here is a comparison based on the values documented in the records:');
      for (const [, group] of grouped) {
        const sorted = group.slice().sort(byDateAsc);
        const latest = sorted[sorted.length - 1];
        const previous = sorted[sorted.length - 2];
        if (!previous) {
          lines.push(`- ${latest.label}: only one result is on file - ${formatObservation(latest)} ${tracker.cite(latest)} (no earlier value to compare against).`);
          continue;
        }
        // Every dated value is listed so the full comparison is verifiable.
        const series = sorted.map((s) => `${formatObservation(s)} ${tracker.cite(s)} on ${fmtDate(s.date)}`);
        const delta = latest.value != null && previous.value != null ? latest.value - previous.value : null;
        const dir = delta == null ? '' : delta > 0 ? `an increase of ${Math.abs(delta).toFixed(2)}` : delta < 0 ? `a decrease of ${Math.abs(delta).toFixed(2)}` : 'no change';
        lines.push(`- ${latest.label}: ${series.join('; ')}.`);
        lines.push(`  Change from the previous result (${fmtDate(previous.date)} to ${fmtDate(latest.date)}): ${dir || 'recorded change'}. Values from different laboratories or methods are not necessarily comparable - verify against the source reports.`);
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

  // ---- Repeated / duplicate tests ----
  if (intents.has('duplicates')) {
    const grouped = new Map();
    for (const l of labs) {
      const key = l.normalized || l.label.toLowerCase();
      if (!grouped.has(key)) grouped.set(key, []);
      grouped.get(key).push(l);
    }
    const repeated = [...grouped.entries()].filter(([, grp]) => grp.length > 1);
    if (repeated.length > 0) {
      lines.push('Potentially repeated tests found in available records:');
      for (const [, grp] of repeated) {
        const sorted = grp.slice().sort(byDateAsc);
        const instances = sorted.map((s) => `${formatObservation(s)} ${tracker.cite(s)} (${fmtDate(s.date)})`);
        lines.push(`- ${sorted[0].label}: ${sorted.length} recorded instances: ${instances.join('; ')}.`);
      }
    } else {
      lines.push('No repeated or duplicate tests were found among the available records.');
    }
  }

  // ---- Missing information ----
  if (intents.has('missing')) {
    lines.push('Assessment of missing, unverified, or gap information:');
    const missingDomains = [];
    if (labs.length === 0) missingDomains.push('laboratory results');
    if (meds.length === 0) missingDomains.push('medications');
    if (allergies.length === 0) missingDomains.push('allergies');
    if (conditions.length === 0) missingDomains.push('diagnosed conditions');
    if (missingDomains.length > 0) {
      lines.push(`- No recorded information found for: ${missingDomains.join(', ')}.`);
    }
    const unverifiedItems = sources.filter((s) => s.verification === 'unverified' || s.source === 'ai-extracted');
    if (unverifiedItems.length > 0) {
      lines.push(`- ${unverifiedItems.length} record(s) are machine-extracted or pending clinician verification: ${unverifiedItems.slice(0, 5).map((u) => `${u.label} ${tracker.cite(u)}`).join(', ')}.`);
    } else {
      lines.push('- All available records have been verified.');
    }
  }

  // ---- Summary intent: pull everything together ----
  if (intents.has('summary') && lines.length === 0) {
    lines.push(isDoctor ? `Clinical summary of available records${patientName ? ` for ${patientName}` : ''}:` : 'Here is a summary drawn from your records:');
    if (conditions.length) lines.push(`- Conditions: ${conditions.map((c) => `${c.label} ${tracker.cite(c)}`).join(', ')}.`);
    if (allergies.length) lines.push(`- Allergies: ${allergies.map((a) => `${a.label} ${tracker.cite(a)}`).join(', ')}.`);
    if (meds.length) lines.push(`- Medications: ${meds.slice(0, 10).map((m) => `${m.label} ${tracker.cite(m)}`).join(', ')}.`);
    if (encounters.length) lines.push(`- Visits: ${encounters.slice(0, 10).map((e) => `${fmtDate(e.date)} at ${e.providerName || 'unknown provider'} ${tracker.cite(e)}`).join('; ')}.`);
    if (labs.length) lines.push(`- Recent results: ${labs.slice(0, 8).map((l) => `${l.label} ${l.value ?? ''}${l.unit ? ` ${l.unit}` : ''} (${fmtDate(l.date)}) ${tracker.cite(l)}`).join('; ')}.`);
  }

  // ---- Source documents (recovered text passages) ----
  if (documents.length && (intents.has('documents') || intents.has('summary') || intents.size === 0 || lines.length === 0)) {
    const byDoc = new Map();
    for (const d of documents) {
      if (!byDoc.has(d.documentId || d.documentName)) byDoc.set(d.documentId || d.documentName, []);
      byDoc.get(d.documentId || d.documentName).push(d);
    }
    if (intents.has('documents') || intents.has('summary') || lines.length === 0) {
      lines.push('Relevant passages recovered from the shared documents:');
      for (const [, group] of byDoc) {
        const head = group[0];
        const excerpt = group
          .map((g) => String(g.text || '').replace(/^From document [^:]+: /, ''))
          .join(' … ')
          .slice(0, 700);
        lines.push(`- ${head.documentName}${head.date ? ` (${fmtDate(head.date)})` : ''}: ${excerpt} ${tracker.cite(head)}`);
      }
      if (!intents.has('documents') && !intents.has('summary') && lines.length === 1) {
        caveats.push('Your question did not match a specific category, so I listed the closest matching document passages.');
      }
    }
  }

  // ---- Timeline of events ----
  if (intents.has('summary') || intents.has('trend') || /\btimeline\b/i.test(question)) {
    const timeline = [...labs, ...meds, ...conditions, ...allergies, ...encounters]
      .filter((s) => s.date)
      .sort(byDateAsc);
    if (timeline.length) {
      lines.push('Timeline of recorded events (oldest to newest):');
      for (const ev of timeline.slice(0, 20)) {
        lines.push(`- ${fmtDate(ev.date)}: ${ev.label}${ev.kind === 'observation' && ev.value != null ? ` = ${ev.value}${ev.unit ? ` ${ev.unit}` : ''}` : ''} (${ev.kind}) ${tracker.cite(ev)}`);
      }
    }
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
  answer += isDoctor
    ? '\n\nGrounded in authorized patient records covered by active share grant. Clinical decision-making remains with the attending physician.'
    : '\n\nThis is a summary of your own records, not medical advice. Please confirm anything important with a clinician.';

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
