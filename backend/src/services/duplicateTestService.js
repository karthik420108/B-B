'use strict';

const { Observation, Document } = require('../models');
const { normalizeTestName } = require('../utils/clinical');

/**
 * Detect potentially repeated diagnostic tests.
 *
 * Distinguishes:
 *   - duplicate DOCUMENT uploads (the same file imported twice) - detected by
 *     content hash, with no clinical meaning; and
 *   - genuinely REPEATED TESTS (similar test performed more than once, possibly
 *     at different providers within a configurable window).
 *
 * This service only flags for review. Repetition is often clinically
 * appropriate, so it never deletes records or declares a test unnecessary.
 */

const SEVERITY_BY_CONFIDENCE = (c) => (c >= 0.85 ? 'high' : c >= 0.6 ? 'moderate' : 'low');

function daysApart(a, b) {
  if (!a || !b) return null;
  return Math.abs(new Date(a).getTime() - new Date(b).getTime()) / 86400000;
}

function obsRef(o) {
  return {
    id: String(o._id),
    testName: o.testName,
    value: o.value,
    valueString: o.valueString || null,
    unit: o.unit || null,
    referenceRange: o.referenceRange || null,
    date: o.date || null,
    dateEstimated: o.dateEstimated || false,
    providerName: o.providerName || null,
    specimen: o.specimen || null,
    sourceDocument: o.sourceDocument || null,
    verification: o.verification,
    source: o.source,
  };
}

/**
 * @param {string} patientId
 * @param {{ windowDays?: number }} options
 */
async function detectRepeatedTests(patientId, { windowDays = 45 } = {}) {
  const observations = await Observation.find({ patient: patientId, deletedAt: null })
    .sort({ date: -1 })
    .lean();

  const findings = [];
  for (let i = 0; i < observations.length; i += 1) {
    for (let j = i + 1; j < observations.length; j += 1) {
      const a = observations[i];
      const b = observations[j];
      const an = a.normalizedTestName || normalizeTestName(a.testName);
      const bn = b.normalizedTestName || normalizeTestName(b.testName);
      if (!an || an !== bn) continue;

      const gap = daysApart(a.date, b.date);
      const withinWindow = gap == null ? true : gap <= windowDays;
      // Only repeated tests INSIDE the chosen comparison window are reported;
      // older repeats would otherwise flood the list with low-signal pairs.
      if (!withinWindow) continue;
      // Same source document => it's the same record, not a repeat.
      const sameDocument = a.sourceDocument && b.sourceDocument
        && String(a.sourceDocument) === String(b.sourceDocument);
      if (sameDocument) continue;

      const sameValue = a.value != null && b.value != null && a.value === b.value;
      const sameUnit = (a.unit || null) === (b.unit || null);
      const differentProvider = (a.providerName || '') !== (b.providerName || '') && a.providerName && b.providerName;

      let confidence = 0.5;
      const reasons = [`Same standardized test name ("${an}").`];
      if (gap != null) {
        reasons.push(`Results are ${Math.round(gap)} day(s) apart${withinWindow ? ` (within the ${windowDays}-day comparison window)` : ' (outside the comparison window)'}.`);
        if (withinWindow) confidence += 0.2;
      } else {
        reasons.push('One or both dates are missing.');
      }
      if (sameValue && sameUnit) { confidence += 0.25; reasons.push('Both results report the same value and unit - this may be a duplicate import.'); }
      if (differentProvider) { confidence += 0.1; reasons.push(`Performed at different providers (${a.providerName} / ${b.providerName}).`); }

      let kind = 'repeated_test';
      if (sameValue && sameUnit && differentProvider === false && withinWindow && gap != null && gap <= 3) {
        kind = 'possible_duplicate_upload';
        reasons.push('Values, units and dates are near-identical, which often indicates the same report uploaded twice.');
      }
      confidence = Math.min(0.95, Math.round(confidence * 100) / 100);

      findings.push({
        id: `${an}:${String(b._id)}:${String(a._id)}`,
        kind,
        normalizedTestName: an,
        confidence,
        severity: SEVERITY_BY_CONFIDENCE(confidence),
        gapDays: gap == null ? null : Math.round(gap),
        withinWindow,
        reason: reasons.join(' '),
        current: obsRef(b),
        previous: obsRef(a),
        recommendation: 'Requires review. Repeated testing can be clinically appropriate - this is a prompt to check, not a recommendation to skip a test.',
      });
    }
  }

  findings.sort((x, y) => y.confidence - x.confidence);
  // Cap output to keep payloads reasonable.
  const limited = findings.slice(0, 100);

  return {
    windowDays,
    total: findings.length,
    returned: limited.length,
    findings: limited,
    generatedAt: new Date().toISOString(),
    disclaimer: 'Flags potential repetition for human review only. No record is deleted and no test is declared unnecessary.',
  };
}

/**
 * Detect duplicate document uploads for a patient (same content hash).
 */
async function detectDuplicateDocuments(patientId) {
  const docs = await Document.find({ patient: patientId, deletedAt: null, sha256: { $ne: null } })
    .select('originalName sha256 category eventDate providerName size createdAt')
    .lean();
  const byHash = new Map();
  for (const d of docs) {
    if (!byHash.has(d.sha256)) byHash.set(d.sha256, []);
    byHash.get(d.sha256).push(d);
  }
  const groups = [];
  for (const [hash, group] of byHash.entries()) {
    if (group.length > 1) {
      groups.push({
        hash,
        confidence: 0.98,
        reason: `${group.length} documents have identical content (same SHA-256). They are almost certainly the same file imported more than once.`,
        documents: group.map((d) => ({
          id: String(d._id), originalName: d.originalName, category: d.category,
          eventDate: d.eventDate, providerName: d.providerName, size: d.size, uploadedAt: d.createdAt,
        })),
      });
    }
  }
  return { total: groups.length, groups };
}

module.exports = { detectRepeatedTests, detectDuplicateDocuments, daysApart };
