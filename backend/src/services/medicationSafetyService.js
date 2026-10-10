'use strict';

const fs = require('fs');
const config = require('../config');
const { MedicationStatement } = require('../models');
const { normalizeDrugName, strengthValue, dosageForm } = require('../utils/clinical');
const logger = require('../utils/logger');

/**
 * Medication safety service.
 *
 * Two independent checks:
 *  1. Duplicate/therapeutic-duplication detection across providers, based on
 *     normalized ingredient names + overlapping active periods.
 *  2. Drug-drug interaction lookup against a curated, versioned rules dataset.
 *
 * SAFETY: the rules engine never invents an interaction. If the dataset cannot
 * be loaded the checker reports `available: false` and returns no findings
 * rather than fabricating clinical results. Interaction output is strictly
 * informational and always requires professional review.
 */

let datasetCache = null;
let datasetError = null;

function loadDataset() {
  if (datasetCache !== null || datasetError) return datasetCache;
  if (!config.interactionDataset) {
    datasetError = 'No interaction dataset is configured (INTERACTION_DATASET is empty).';
    return null;
  }
  try {
    const raw = fs.readFileSync(config.interactionDataset, 'utf8');
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed.interactions)) throw new Error('dataset missing `interactions` array');
    const index = new Map();
    for (const rule of parsed.interactions) {
      const a = normalizeDrugName(rule.a);
      const b = normalizeDrugName(rule.b);
      const key = [a, b].sort().join('|');
      index.set(key, { ...rule, a, b });
    }
    datasetCache = { meta: parsed.meta || {}, index };
    return datasetCache;
  } catch (err) {
    datasetError = `Failed to load interaction dataset: ${err.message}`;
    logger.warn(datasetError);
    return null;
  }
}

function isAvailable() {
  return loadDataset() !== null;
}

function datasetInfo() {
  const ds = loadDataset();
  if (!ds) return { available: false, reason: datasetError };
  return {
    available: true,
    name: ds.meta.name,
    version: ds.meta.version,
    updated: ds.meta.updated,
    ruleCount: ds.index.size,
    sources: ds.meta.sources,
    disclaimer: ds.meta.disclaimer,
  };
}

/** Active medications for a patient, normalized for comparison. */
async function activeMedications(patientId) {
  const meds = await MedicationStatement.find({ patient: patientId, deletedAt: null }).lean();
  return meds.map((m) => ({
    raw: m,
    id: String(m._id),
    name: m.name,
    normalized: m.normalizedName || normalizeDrugName(m.name),
    genericName: m.genericName,
    strength: m.strength,
    form: m.form || dosageForm(m.name),
    status: m.status,
    startDate: m.startDate,
    endDate: m.endDate,
    providerName: m.providerName,
    sourceDocument: m.sourceDocument,
    source: m.source,
    verification: m.verification,
  }));
}

/** Whether a medication is currently active (explicit status or open date range). */
function isActiveNow(med, now = new Date()) {
  if (med.status === 'active') return true;
  if (med.status === 'discontinued' || med.status === 'completed') return false;
  // status unknown -> infer from dates
  const started = !med.startDate || new Date(med.startDate) <= now;
  const notEnded = !med.endDate || new Date(med.endDate) >= now;
  return started && notEnded;
}

function rangesOverlap(a, b) {
  const aStart = a.startDate ? new Date(a.startDate).getTime() : -Infinity;
  const aEnd = a.endDate ? new Date(a.endDate).getTime() : Infinity;
  const bStart = b.startDate ? new Date(b.startDate).getTime() : -Infinity;
  const bEnd = b.endDate ? new Date(b.endDate).getTime() : Infinity;
  return aStart <= bEnd && bStart <= aEnd;
}

/**
 * Detect potential therapeutic duplication: two records for the same normalized
 * ingredient that are concurrently active (or both currently active).
 */
function detectDuplicateMedications(meds) {
  const findings = [];
  const byNorm = new Map();
  for (const m of meds) {
    if (!byNorm.has(m.normalized)) byNorm.set(m.normalized, []);
    byNorm.get(m.normalized).push(m);
  }
  for (const [norm, group] of byNorm.entries()) {
    if (group.length < 2) continue;
    const activeGroup = group.filter((m) => isActiveNow(m));
    const pool = activeGroup.length >= 2 ? activeGroup : group;
    for (let i = 0; i < pool.length; i += 1) {
      for (let j = i + 1; j < pool.length; j += 1) {
        const a = pool[i]; const b = pool[j];
        const concurrent = activeGroup.length >= 2 ? true : rangesOverlap(a, b);
        const sameStrength = a.strength && b.strength && strengthValue(a.strength) && strengthValue(b.strength)
          ? strengthValue(a.strength).value === strengthValue(b.strength).value
          : null;
        const differentProvider = (a.providerName || '') !== (b.providerName || '');
        let reason = `Two records refer to the same ingredient ("${norm}")`;
        if (concurrent) reason += ' and are both active at the same time';
        if (differentProvider) reason += ` from different providers (${a.providerName || 'unknown'} / ${b.providerName || 'unknown'})`;
        if (sameStrength === true) reason += ' at the same strength - this may be a duplicate entry';
        else if (sameStrength === false) reason += ' at different strengths - verify whether this is intentional';
        findings.push({
          type: 'duplicate_medication',
          severity: sameStrength === true && concurrent ? 'moderate' : 'low',
          confidence: concurrent ? (differentProvider ? 0.8 : 0.9) : 0.55,
          normalized: norm,
          reason,
          medications: [medicationRef(a), medicationRef(b)],
          recommendation: 'Requires professional review. Do not stop or change any medicine without your prescriber.',
        });
      }
    }
  }
  return findings;
}

function medicationRef(m) {
  return {
    id: m.id,
    name: m.name,
    strength: m.strength,
    status: m.status,
    providerName: m.providerName || null,
    startDate: m.startDate || null,
    endDate: m.endDate || null,
    sourceDocument: m.sourceDocument || null,
    source: m.source,
    verification: m.verification,
  };
}

/** Look up pair-wise interactions among all medications of the patient. */
function detectInteractions(meds) {
  const ds = loadDataset();
  if (!ds) return null;

  // Consider currently-active (or inferred-active) plus status-unknown meds.
  const relevant = meds.filter((m) => isActiveNow(m) || m.status === 'unknown');
  const findings = [];
  for (let i = 0; i < relevant.length; i += 1) {
    for (let j = i + 1; j < relevant.length; j += 1) {
      const a = relevant[i]; const b = relevant[j];
      if (a.normalized === b.normalized) continue;
      const key = [a.normalized, b.normalized].sort().join('|');
      const rule = ds.index.get(key);
      if (!rule) continue;
      findings.push({
        type: 'drug_interaction',
        severity: rule.severity,
        confidence: 0.9,
        ruleKey: key,
        title: `${rule.a} + ${rule.b}`,
        effect: rule.effect,
        mechanism: rule.mechanism,
        management: rule.management,
        source: rule.source,
        medications: [medicationRef(a), medicationRef(b)],
        recommendation: 'Requires professional review. Do not start, stop or change any medicine based on this alert.',
      });
    }
  }
  // Sort by severity
  const order = { major: 0, moderate: 1, low: 2, minor: 3 };
  findings.sort((x, y) => (order[x.severity] ?? 9) - (order[y.severity] ?? 9));
  return findings;
}

/**
 * Full medication safety report for a patient.
 * @returns {{checkerAvailable:boolean, checkerReason?:string, dataset:object, duplicates:Array, interactions:Array|null, generatedAt:string, disclaimer:string}}
 */
async function report(patientId) {
  const meds = await activeMedications(patientId);
  const duplicates = detectDuplicateMedications(meds);
  const interactions = detectInteractions(meds);
  return {
    checkerAvailable: isAvailable(),
    checkerReason: isAvailable() ? undefined : datasetError,
    dataset: datasetInfo(),
    medicationCount: meds.length,
    activeCount: meds.filter((m) => isActiveNow(m)).length,
    duplicates,
    interactions,
    generatedAt: new Date().toISOString(),
    disclaimer: 'Medication alerts are informational only and require review by a qualified professional. This system never changes or discontinues a medicine.',
  };
}

function _resetDataset() { datasetCache = null; datasetError = null; }

module.exports = {
  report,
  detectDuplicateMedications,
  detectInteractions,
  isActiveNow,
  isAvailable,
  datasetInfo,
  activeMedications,
  _resetDataset,
};
