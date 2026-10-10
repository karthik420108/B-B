'use strict';

const {
  Observation, Condition, AllergyIntolerance, MedicationStatement, Encounter, Document, ShareGrant,
} = require('../models');
const { badRequest, notFound } = require('../utils/errors');
const { parsePagination } = require('../utils/http');
const { normalizeTestName, normalizeDrugName } = require('../utils/clinical');
const auditService = require('./auditService');

const MODEL_BY_KIND = {
  observation: Observation,
  condition: Condition,
  allergy: AllergyIntolerance,
  medication: MedicationStatement,
  encounter: Encounter,
};

function dateRange(query) {
  const out = {};
  if (query.from || query.to) {
    out.$gte = query.from ? new Date(query.from) : undefined;
    out.$lte = query.to ? new Date(query.to) : undefined;
    Object.keys(out).forEach((k) => out[k] === undefined && delete out[k]);
  }
  return out;
}

function baseFilter(patientId, query = {}) {
  const filter = { patient: patientId, deletedAt: null };
  if (query.verification) filter.verification = query.verification;
  if (query.source) filter.source = query.source;
  if (query.provider) filter.provider = query.provider;
  const dr = dateRange(query);
  return { filter, dr };
}

async function listObservations(patientId, query = {}) {
  const { filter, dr } = baseFilter(patientId, query);
  if (Object.keys(dr).length) filter.date = dr;
  if (query.q) filter.testName = new RegExp(String(query.q).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
  const { page, limit, skip } = parsePagination(query);
  const [items, total] = await Promise.all([
    Observation.find(filter).populate('sourceDocument', 'originalName category').sort({ date: -1 }).skip(skip).limit(limit).lean(),
    Observation.countDocuments(filter),
  ]);
  return { items, total, page, limit };
}

async function listMedications(patientId, query = {}) {
  const { filter, dr } = baseFilter(patientId, query);
  if (query.status) filter.status = query.status;
  if (Object.keys(dr).length) filter.startDate = dr;
  if (query.q) filter.name = new RegExp(String(query.q).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
  const sort = { startDate: -1 };
  const [items, total] = await Promise.all([
    MedicationStatement.find(filter).populate('sourceDocument', 'originalName category').sort(sort).limit(500).lean(),
    MedicationStatement.countDocuments(filter),
  ]);
  return { items, total };
}

async function listConditions(patientId, query = {}) {
  const { filter } = baseFilter(patientId, query);
  const items = await Condition.find(filter).populate('sourceDocument', 'originalName').sort({ onsetDate: -1 }).limit(300).lean();
  return { items, total: items.length };
}

async function listAllergies(patientId, query = {}) {
  const { filter } = baseFilter(patientId, query);
  const items = await AllergyIntolerance.find(filter).populate('sourceDocument', 'originalName').sort({ createdAt: -1 }).limit(200).lean();
  return { items, total: items.length };
}

async function listEncounters(patientId, query = {}) {
  const { filter, dr } = baseFilter(patientId, query);
  if (Object.keys(dr).length) filter.date = dr;
  const items = await Encounter.find(filter).populate('sourceDocument', 'originalName').sort({ date: -1 }).limit(300).lean();
  return { items, total: items.length };
}

/**
 * Build the unified medical timeline across every record type, sorted by the
 * medical EVENT date (not the upload time). Unknown dates are grouped at the end
 * and clearly flagged.
 */
async function buildTimeline(patientId, query = {}) {
  const scope = { patient: patientId, deletedAt: null };
  const dr = dateRange(query);
  const dateField = {};
  if (Object.keys(dr).length) dateField.$or = [
    { date: dr }, { onsetDate: dr }, { startDate: dr },
  ];

  const [observations, conditions, allergies, medications, encounters, documents] = await Promise.all([
    Observation.find({ ...scope, ...dateField }).populate('sourceDocument', 'originalName category').lean(),
    Condition.find({ ...scope, ...dateField }).populate('sourceDocument', 'originalName category').lean(),
    AllergyIntolerance.find({ ...scope, ...dateField }).populate('sourceDocument', 'originalName category').lean(),
    MedicationStatement.find({ ...scope, ...dateField }).populate('sourceDocument', 'originalName category').lean(),
    Encounter.find({ ...scope, ...dateField }).populate('sourceDocument', 'originalName category').lean(),
    Document.find({ ...scope }).select('originalName category eventDate eventDateEstimated providerName extractionStatus createdAt tags').lean(),
  ]);

  const docName = (ref) => (ref && typeof ref === 'object' ? ref.originalName : undefined);
  const items = [];

  for (const o of observations) {
    items.push({
      id: String(o._id), kind: 'observation', category: 'laboratory',
      date: o.date || null, dateEstimated: o.dateEstimated || false, dateUnknown: !o.date,
      title: o.testName,
      subtitle: `${o.value != null ? `${o.value}${o.unit ? ` ${o.unit}` : ''}` : (o.valueString || 'result recorded')}${o.referenceRange ? ` (ref ${o.referenceRange})` : ''}${o.abnormal ? ' • outside reference range' : ''}`,
      providerName: o.providerName, verification: o.verification, source: o.source,
      documentId: o.sourceDocument?._id || null, documentName: docName(o.sourceDocument),
      tags: [],
    });
  }
  for (const c of conditions) {
    items.push({
      id: String(c._id), kind: 'condition', category: 'condition',
      date: c.onsetDate || null, dateEstimated: false, dateUnknown: !c.onsetDate,
      title: c.name, subtitle: `Diagnosis • status ${c.status}`,
      providerName: c.providerName, verification: c.verification, source: c.source,
      documentId: c.sourceDocument?._id || null, documentName: docName(c.sourceDocument), tags: [],
    });
  }
  for (const a of allergies) {
    items.push({
      id: String(a._id), kind: 'allergy', category: 'allergy',
      date: a.onsetDate || null, dateEstimated: false, dateUnknown: !a.onsetDate,
      title: `Allergy: ${a.substance}`,
      subtitle: `${a.reaction || 'reaction not recorded'} • severity ${a.severity}`,
      providerName: a.providerName, verification: a.verification, source: a.source,
      documentId: a.sourceDocument?._id || null, documentName: docName(a.sourceDocument), tags: [],
    });
  }
  for (const m of medications) {
    items.push({
      id: String(m._id), kind: 'medication', category: 'medication',
      date: m.startDate || null, dateEstimated: false, dateUnknown: !m.startDate,
      title: `Medication: ${m.name}`,
      subtitle: `${m.strength || ''} ${m.frequency || ''} • status ${m.status}`.trim(),
      providerName: m.providerName, verification: m.verification, source: m.source,
      documentId: m.sourceDocument?._id || null, documentName: docName(m.sourceDocument), tags: [],
    });
  }
  for (const e of encounters) {
    items.push({
      id: String(e._id), kind: 'encounter', category: e.type === 'discharge' ? 'discharge_summary' : 'consultation_note',
      date: e.date || null, dateEstimated: e.dateEstimated || false, dateUnknown: !e.date,
      title: e.type === 'discharge' ? 'Hospital discharge' : `${e.type.replace(/_/g, ' ')}`,
      subtitle: (e.diagnosis && e.diagnosis.length ? e.diagnosis.join(', ') : e.reason) || 'No diagnosis recorded',
      providerName: e.providerName, verification: e.verification, source: e.source,
      documentId: e.sourceDocument?._id || null, documentName: docName(e.sourceDocument), tags: [],
    });
  }
  for (const d of documents) {
    items.push({
      id: String(d._id), kind: 'document', category: d.category,
      date: d.eventDate || null, dateEstimated: d.eventDateEstimated || false, dateUnknown: !d.eventDate,
      title: d.originalName,
      subtitle: `Document • ${d.extractionStatus}`,
      providerName: d.providerName, verification: null, source: 'document',
      documentId: d._id, documentName: d.originalName, tags: d.tags || [],
    });
  }

  // Filters on aggregated items.
  let filtered = items;
  if (query.kind) filtered = filtered.filter((i) => i.kind === query.kind);
  if (query.category) filtered = filtered.filter((i) => i.category === query.category);
  if (query.providerName) filtered = filtered.filter((i) => (i.providerName || '') === query.providerName);
  if (query.q) {
    const rx = new RegExp(String(query.q).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
    filtered = filtered.filter((i) => rx.test(i.title) || rx.test(i.subtitle || ''));
  }

  const dated = filtered.filter((i) => !i.dateUnknown).sort((a, b) => new Date(b.date) - new Date(a.date));
  const undated = filtered.filter((i) => i.dateUnknown).sort((a, b) => (a.title || '').localeCompare(b.title || ''));

  return {
    items: [...dated, ...undated],
    counts: { total: filtered.length, dated: dated.length, undated: undated.length },
    providers: [...new Set(items.map((i) => i.providerName).filter(Boolean))].sort(),
    categories: [...new Set(items.map((i) => i.category).filter(Boolean))].sort(),
  };
}

/** Full-text-ish search across the patient's own records. */
async function search(patientId, q, { limit = 30 } = {}) {
  if (!q || String(q).trim().length < 2) throw badRequest('Enter at least 2 characters to search.');
  const rx = new RegExp(String(q).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
  const scope = { patient: patientId, deletedAt: null };
  const [observations, conditions, allergies, medications, encounters, documents] = await Promise.all([
    Observation.find({ ...scope, testName: rx }).limit(limit).lean(),
    Condition.find({ ...scope, name: rx }).limit(limit).lean(),
    AllergyIntolerance.find({ ...scope, substance: rx }).limit(limit).lean(),
    MedicationStatement.find({ ...scope, name: rx }).limit(limit).lean(),
    Encounter.find({ ...scope, $or: [{ diagnosis: rx }, { reason: rx }] }).limit(limit).lean(),
    Document.find({ ...scope, $or: [{ originalName: rx }, { providerName: rx }, { tags: rx }] }).limit(limit).lean(),
  ]);
  return {
    query: q,
    results: {
      observations: observations.map((o) => ({ id: o._id, testName: o.testName, value: o.value, unit: o.unit, date: o.date, providerName: o.providerName, sourceDocument: o.sourceDocument })),
      conditions: conditions.map((c) => ({ id: c._id, name: c.name, onsetDate: c.onsetDate, sourceDocument: c.sourceDocument })),
      allergies: allergies.map((a) => ({ id: a._id, substance: a.substance, reaction: a.reaction, severity: a.severity })),
      medications: medications.map((m) => ({ id: m._id, name: m.name, strength: m.strength, status: m.status, startDate: m.startDate, sourceDocument: m.sourceDocument })),
      encounters: encounters.map((e) => ({ id: e._id, type: e.type, date: e.date, diagnosis: e.diagnosis, providerName: e.providerName })),
      documents: documents.map((d) => ({ id: d._id, originalName: d.originalName, category: d.category, eventDate: d.eventDate })),
    },
    total: observations.length + conditions.length + allergies.length + medications.length + encounters.length + documents.length,
  };
}

/** Correct extracted fields and/or change verification status. */
async function verifyRecord(patientId, kind, id, { verification, corrections = {} } = {}, { req = null } = {}) {
  const Model = MODEL_BY_KIND[kind];
  if (!Model) throw badRequest('Unknown record type.');
  const record = await Model.findOne({ _id: id, patient: patientId, deletedAt: null });
  if (!record) throw notFound('Record not found');

  const allowed = new Set(['testName', 'value', 'valueString', 'unit', 'referenceRange', 'specimen', 'date',
    'name', 'onsetDate', 'status', 'substance', 'reaction', 'severity', 'strength', 'dose', 'frequency',
    'route', 'form', 'startDate', 'endDate', 'prescriber', 'reason', 'diagnosis', 'type', 'notes']);

  for (const [key, value] of Object.entries(corrections)) {
    if (!allowed.has(key)) continue;
    if (['date', 'onsetDate', 'startDate', 'endDate'].includes(key)) {
      record[key] = value ? new Date(value) : undefined;
    } else {
      record[key] = value;
    }
  }
  if (kind === 'observation' && (corrections.testName !== undefined || !record.normalizedTestName)) {
    record.normalizedTestName = normalizeTestName(record.testName);
  }
  if (kind === 'medication' && (corrections.name !== undefined || !record.normalizedName)) {
    record.normalizedName = normalizeDrugName(record.name);
  }
  if (corrections.verification === 'verified' || verification) {
    record.verification = verification || corrections.verification;
    // A patient confirming an extracted value makes it patient-authoritative.
    if (record.verification === 'verified') record.source = record.source === 'ai-extracted' ? 'ai-extracted' : record.source;
  }
  await record.save();
  await auditService.record(req, { action: 'record.verified', patient: patientId, entityType: kind, entityId: record._id, metadata: { verification: record.verification } });
  return record.toObject();
}

/**
 * Add a record manually (patient-entered). Creates clinical resources directly
 * with source='patient' and verification='verified'.
 */
async function addManualRecord(patientId, payload = {}, { req = null } = {}) {
  const kind = payload.kind;
  const data = payload.data || {};
  const base = { patient: patientId, source: 'patient', verification: 'verified', providerName: data.providerName || undefined };
  let created;
  if (kind === 'observation') {
    if (!data.testName) throw badRequest('testName is required.');
    created = await Observation.create({ ...base, testName: data.testName, normalizedTestName: normalizeTestName(data.testName), value: data.value ?? null, valueString: data.valueString, unit: data.unit, referenceRange: data.referenceRange, date: data.date ? new Date(data.date) : new Date() });
  } else if (kind === 'condition') {
    if (!data.name) throw badRequest('name is required.');
    created = await Condition.create({ ...base, name: data.name, normalizedName: data.name.toLowerCase(), status: data.status || 'active', onsetDate: data.onsetDate ? new Date(data.onsetDate) : undefined });
  } else if (kind === 'allergy') {
    if (!data.substance) throw badRequest('substance is required.');
    created = await AllergyIntolerance.create({ ...base, substance: data.substance, normalizedSubstance: data.substance.toLowerCase(), reaction: data.reaction, severity: data.severity || 'unknown' });
  } else if (kind === 'medication') {
    if (!data.name) throw badRequest('name is required.');
    created = await MedicationStatement.create({ ...base, name: data.name, normalizedName: normalizeDrugName(data.name), genericName: data.genericName, strength: data.strength, dose: data.dose, frequency: data.frequency, route: data.route, form: data.form, status: data.status || 'active', startDate: data.startDate ? new Date(data.startDate) : new Date(), prescriber: data.prescriber });
  } else if (kind === 'encounter') {
    created = await Encounter.create({ ...base, type: data.type || 'consultation', date: data.date ? new Date(data.date) : new Date(), reason: data.reason, diagnosis: data.diagnosis || [] });
  } else {
    throw badRequest('Unsupported record kind. Use observation, condition, allergy, medication or encounter.');
  }
  await auditService.record(req, { action: 'record.manual_added', patient: patientId, entityType: kind, entityId: created._id });
  return created.toObject();
}

/** Numeric series for charts (glucose, BP, thyroid, ...). */
async function chartSeries(patientId, { testName } = {}) {
  const filter = { patient: patientId, deletedAt: null, value: { $ne: null } };
  if (testName) filter.normalizedTestName = normalizeTestName(testName);
  const observations = await Observation.find(filter).sort({ date: 1 }).lean();
  const grouped = new Map();
  for (const o of observations) {
    const key = `${o.normalizedTestName || normalizeTestName(o.testName)}|${o.unit || ''}`;
    if (!grouped.has(key)) grouped.set(key, { testName: o.testName, unit: o.unit || null, referenceRange: o.referenceRange || null, points: [] });
    const g = grouped.get(key);
    g.points.push({ date: o.date, value: o.value, referenceRange: o.referenceRange || null, abnormal: o.abnormal, documentId: o.sourceDocument || null });
  }
  return {
    series: [...grouped.values()].filter((s) => s.points.length >= 1),
    note: 'Values are shown exactly as recorded with their original units and reference ranges. No disease is inferred from these charts.',
  };
}

module.exports = {
  listObservations, listMedications, listConditions, listAllergies, listEncounters,
  buildTimeline, search, verifyRecord, addManualRecord, chartSeries, MODEL_BY_KIND,
};
