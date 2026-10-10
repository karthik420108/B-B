'use strict';

const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');
const { Observation, Condition, AllergyIntolerance, MedicationStatement, Encounter } = require('../src/models');
const { normalizeTestName, normalizeDrugName } = require('../src/utils/clinical');

before(h.connect);
after(h.disconnect);
beforeEach(h.clearDatabase);

async function seedPatientData(userId) {
  await Observation.create([
    { patient: userId, testName: 'HbA1c', normalizedTestName: normalizeTestName('HbA1c'), value: 7.6, unit: '%', referenceRange: '4.0 - 5.6', date: new Date('2026-01-16'), providerName: 'Northlake Lab', source: 'ai-extracted', verification: 'verified' },
    { patient: userId, testName: 'HbA1c', normalizedTestName: normalizeTestName('HbA1c'), value: 7.1, unit: '%', referenceRange: '4.0 - 5.6', date: new Date('2026-04-02'), providerName: 'Northlake Lab', source: 'ai-extracted', verification: 'verified' },
    { patient: userId, testName: 'Fasting Glucose', normalizedTestName: normalizeTestName('Fasting Glucose'), value: 138, unit: 'mg/dL', date: new Date('2026-01-16'), providerName: 'Northlake Lab' },
    { patient: userId, testName: 'Fasting Glucose', normalizedTestName: normalizeTestName('Fasting Glucose'), value: 121, unit: 'mg/dL', date: new Date('2026-04-02'), providerName: 'Northlake Lab' },
  ]);
  await Condition.create({ patient: userId, name: 'Type 2 Diabetes Mellitus', normalizedName: 'type 2 diabetes mellitus', onsetDate: new Date('2026-01-15'), status: 'active', source: 'clinician', verification: 'verified' });
  await AllergyIntolerance.create({ patient: userId, substance: 'Sulfa drugs', normalizedSubstance: 'sulfa drugs', reaction: 'hives', severity: 'moderate', source: 'ai-extracted', verification: 'verified' });
  await MedicationStatement.create([
    { patient: userId, name: 'Warfarin 5 mg', normalizedName: normalizeDrugName('Warfarin 5 mg'), strength: '5 mg', status: 'active', startDate: new Date('2026-05-12'), providerName: 'Riverside City Hospital', verification: 'verified' },
    { patient: userId, name: 'Ibuprofen 400 mg', normalizedName: normalizeDrugName('Ibuprofen 400 mg'), strength: '400 mg', status: 'active', startDate: new Date('2026-06-05'), providerName: 'GreenCross Pharmacy', verification: 'verified' },
  ]);
  await Encounter.create({ patient: userId, type: 'discharge', date: new Date('2026-05-12'), providerName: 'Riverside City Hospital', diagnosis: ['Atrial Fibrillation'] });
}

test('timeline is sorted by event date descending and includes multiple providers', async () => {
  const u = await h.register('patient');
  await seedPatientData(u.user.id);
  const res = await h.request(h.app).get('/api/records/timeline').set('Authorization', `Bearer ${u.accessToken}`);
  assert.equal(res.status, 200);
  const items = res.body.data.items.filter((i) => !i.dateUnknown);
  for (let i = 1; i < items.length; i += 1) {
    assert.ok(new Date(items[i - 1].date) >= new Date(items[i].date), 'must be sorted desc by event date');
  }
  assert.ok(new Set(items.map((i) => i.providerName)).size >= 2);
  assert.ok(items.some((i) => i.kind === 'observation'));
  assert.ok(items.some((i) => i.kind === 'medication'));
  assert.ok(items.some((i) => i.kind === 'condition'));
});

test('unknown-date records are flagged and grouped, not silently dated', async () => {
  const u = await h.register('patient');
  await Observation.create({ patient: u.user.id, testName: 'Potassium', normalizedTestName: 'potassium', value: 4.1, unit: 'mmol/L', date: null });
  const res = await h.request(h.app).get('/api/records/timeline').set('Authorization', `Bearer ${u.accessToken}`);
  const undated = res.body.data.items.filter((i) => i.dateUnknown);
  assert.ok(undated.some((i) => /potassium/i.test(i.title)));
  assert.equal(res.body.data.counts.undated >= 1, true);
});

test('detects repeated tests within the configured window with reasons and confidence', async () => {
  const u = await h.register('patient');
  await seedPatientData(u.user.id);
  const res = await h.request(h.app).get('/api/records/duplicates/tests?windowDays=200').set('Authorization', `Bearer ${u.accessToken}`);
  assert.equal(res.status, 200);
  const findings = res.body.data.findings;
  assert.ok(findings.length >= 2, 'HbA1c and glucose both repeat');
  assert.ok(findings.every((f) => f.reason && typeof f.confidence === 'number'));
  assert.ok(findings.every((f) => f.current && f.previous));
  assert.match(findings[0].recommendation, /review/i);
});

test('repeated-test detection respects the comparison window', async () => {
  const u = await h.register('patient');
  await seedPatientData(u.user.id);
  const narrow = await h.request(h.app).get('/api/records/duplicates/tests?windowDays=10').set('Authorization', `Bearer ${u.accessToken}`);
  const wide = await h.request(h.app).get('/api/records/duplicates/tests?windowDays=200').set('Authorization', `Bearer ${u.accessToken}`);
  assert.ok(wide.body.data.total > narrow.body.data.total, 'a wider window finds more');
});

test('medication safety flags a validated interaction and requires professional review', async () => {
  const u = await h.register('patient');
  await seedPatientData(u.user.id);
  const res = await h.request(h.app).get('/api/records/medications/safety').set('Authorization', `Bearer ${u.accessToken}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.data.checkerAvailable, true);
  const hit = res.body.data.interactions.find((i) => /warfarin/i.test(i.title));
  assert.ok(hit, 'warfarin interaction present');
  assert.equal(hit.severity, 'major');
  assert.match(hit.effect, /bleeding/i);
  assert.match(hit.recommendation, /professional review/i);
});

test('medication safety flags therapeutic duplication of the same ingredient', async () => {
  const u = await h.register('patient');
  await MedicationStatement.create([
    { patient: u.user.id, name: 'Metformin 500 mg', normalizedName: normalizeDrugName('Metformin 500 mg'), strength: '500 mg', status: 'active', providerName: 'Clinic A' },
    { patient: u.user.id, name: 'Metformin 500 mg', normalizedName: normalizeDrugName('Metformin 500 mg'), strength: '500 mg', status: 'active', providerName: 'Pharmacy B' },
  ]);
  const res = await h.request(h.app).get('/api/records/medications/safety').set('Authorization', `Bearer ${u.accessToken}`);
  assert.ok(res.body.data.duplicates.length >= 1);
  assert.match(res.body.data.duplicates[0].reason, /same ingredient/i);
});

test('drug-name normalization maps brand names to generics safely', () => {
  assert.equal(normalizeDrugName('Coumadin 5 mg'), 'warfarin');
  assert.equal(normalizeDrugName('Glucophage'), 'metformin');
  assert.equal(normalizeDrugName('Tylenol 500mg'), 'paracetamol');
  assert.equal(normalizeDrugName('Metformin Hydrochloride 500 mg'), 'metformin');
});

test('AI answers are grounded, cited and state when data is missing', async () => {
  const u = await h.register('patient');
  await seedPatientData(u.user.id);

  const answer = await h.request(h.app).post('/api/ai/ask').set('Authorization', `Bearer ${u.accessToken}`).send({ question: 'What was my latest HbA1c result?' });
  assert.equal(answer.status, 200);
  assert.match(answer.body.data.answer, /hba1c/i);
  assert.ok(answer.body.data.citations.length > 0, 'must cite sources');
  assert.ok(answer.body.data.citations.every((c) => c.kind && (c.documentId || c.recordId)));
  assert.equal(answer.body.data.grounded, true);

  const missing = await h.request(h.app).post('/api/ai/ask').set('Authorization', `Bearer ${u.accessToken}`).send({ question: 'What was my last brain MRI result?' });
  assert.match(missing.body.data.answer, /could not find|not found|no information|no matching/i);
  assert.equal(missing.body.data.uncertainty.missing, true);
});

test('AI question answering is scoped to the requesting patient only', async () => {
  const a = await h.register('patient');
  const b = await h.register('patient');
  await seedPatientData(a.user.id);
  const res = await h.request(h.app).post('/api/ai/ask').set('Authorization', `Bearer ${b.accessToken}`).send({ question: 'What was my latest HbA1c result?' });
  assert.equal(res.status, 200);
  assert.match(res.body.data.answer, /could not find|no information|no matching/i, 'patient B must not see patient A data');
  assert.equal(res.body.data.citations.length, 0);
});

test('AI summary is source-linked, timestamped and labelled as not advice', async () => {
  const u = await h.register('patient');
  await seedPatientData(u.user.id);
  const res = await h.request(h.app).post('/api/ai/summary').set('Authorization', `Bearer ${u.accessToken}`);
  assert.equal(res.status, 200);
  assert.ok(res.body.data.citations.length > 0);
  assert.ok(res.body.data.generatedAt);
  assert.match(res.body.data.disclaimer, /not|reference/i);
  assert.ok(Array.isArray(res.body.data.missing));
});
