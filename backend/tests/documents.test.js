'use strict';

const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

before(h.connect);
after(h.disconnect);
beforeEach(h.clearDatabase);

const LAB_TEXT = [
  'Northlake Diagnostic Laboratory',
  'Laboratory Results',
  'Date: 12 Mar 2026',
  'Specimen: Fasting blood',
  'HbA1c 7.4 % (4.0 - 5.6) H',
  'Fasting Glucose 132 mg/dL (70 - 100) H',
  'TSH 2.1 mIU/L (0.4 - 4.0)',
].join('\n');

test('rejects unsupported file types', async () => {
  const u = await h.register('patient');
  const res = await h.request(h.app).post('/api/documents')
    .set('Authorization', `Bearer ${u.accessToken}`)
    .attach('file', Buffer.from('MZ...'), { filename: 'evil.exe', contentType: 'application/x-msdownload' });
  assert.equal(res.status, 400);
});

test('rejects an empty upload', async () => {
  const u = await h.register('patient');
  const res = await h.request(h.app).post('/api/documents').set('Authorization', `Bearer ${u.accessToken}`);
  assert.equal(res.status, 400);
});

test('uploads a report, extracts structured data, and links it to a document', async () => {
  const u = await h.register('patient');
  const res = await h.request(h.app).post('/api/documents')
    .set('Authorization', `Bearer ${u.accessToken}`)
    .field('category', 'laboratory')
    .field('providerName', 'Northlake Diagnostic Laboratory')
    .field('eventDate', '2026-03-12')
    .attach('file', Buffer.from(LAB_TEXT), { filename: 'lab.txt', contentType: 'text/plain' });
  assert.equal(res.status, 201);
  assert.equal(res.body.data.extraction.status, 'extracted');
  const doc = res.body.data.document;
  assert.equal(doc.extractionStatus, 'extracted');

  const detail = await h.request(h.app).get(`/api/documents/${doc.id}`).set('Authorization', `Bearer ${u.accessToken}`);
  const obs = detail.body.data.extracted.observations;
  assert.ok(obs.length >= 3, 'at least three observations extracted');
  const hba1c = obs.find((o) => /hba1c/i.test(o.testName));
  assert.ok(hba1c, 'HbA1c extracted');
  assert.equal(hba1c.value, 7.4);
  assert.equal(hba1c.unit, '%');
  assert.match(hba1c.referenceRange, /4\.0/);
  assert.equal(hba1c.verification, 'unverified');
  assert.equal(hba1c.source, 'ai-extracted');
  assert.equal(String(hba1c.sourceDocument), doc.id);
});

test('patient can correct extracted fields then mark them verified', async () => {
  const u = await h.register('patient');
  const up = await h.request(h.app).post('/api/documents')
    .set('Authorization', `Bearer ${u.accessToken}`)
    .field('category', 'laboratory')
    .attach('file', Buffer.from(LAB_TEXT), { filename: 'lab.txt', contentType: 'text/plain' });
  const docId = up.body.data.document.id;
  const detail = await h.request(h.app).get(`/api/documents/${docId}`).set('Authorization', `Bearer ${u.accessToken}`);
  const obs = detail.body.data.extracted.observations[0];
  const res = await h.request(h.app).patch(`/api/records/observation/${obs._id}/verify`)
    .set('Authorization', `Bearer ${u.accessToken}`)
    .send({ verification: 'verified', corrections: { valueString: 'corrected by patient' } });
  assert.equal(res.status, 200);
  assert.equal(res.body.data.verification, 'verified');
  assert.equal(res.body.data.valueString, 'corrected by patient');
});

test('extraction never invents a date when none is present', async () => {
  const u = await h.register('patient');
  const noDate = 'Northlake Diagnostic Laboratory\nLaboratory Results\nSodium 140 mmol/L';
  const res = await h.request(h.app).post('/api/documents')
    .set('Authorization', `Bearer ${u.accessToken}`)
    .field('category', 'laboratory')
    .attach('file', Buffer.from(noDate), { filename: 'nodate.txt', contentType: 'text/plain' });
  assert.equal(res.status, 201);
  const doc = res.body.data.document;
  assert.equal(doc.eventDate, null);
  const detail = await h.request(h.app).get(`/api/documents/${doc.id}`).set('Authorization', `Bearer ${u.accessToken}`);
  const obs = detail.body.data.extracted.observations[0];
  assert.equal(obs.value, 140);
  assert.equal(obs.date, null, 'no date must be invented');
});

test('manual record entry creates patient-verified records', async () => {
  const u = await h.register('patient');
  const res = await h.request(h.app).post('/api/records/manual')
    .set('Authorization', `Bearer ${u.accessToken}`)
    .send({ kind: 'allergy', data: { substance: 'Penicillin', reaction: 'Rash', severity: 'moderate' } });
  assert.equal(res.status, 201);
  assert.equal(res.body.data.source, 'patient');
  assert.equal(res.body.data.verification, 'verified');
});

test('patients cannot access another patient\'s documents (isolation)', async () => {
  const a = await h.register('patient');
  const b = await h.register('patient');
  const up = await h.request(h.app).post('/api/documents')
    .set('Authorization', `Bearer ${a.accessToken}`)
    .field('category', 'laboratory')
    .attach('file', Buffer.from(LAB_TEXT), { filename: 'lab.txt', contentType: 'text/plain' });
  const docId = up.body.data.document.id;

  const listB = await h.request(h.app).get('/api/documents').set('Authorization', `Bearer ${b.accessToken}`);
  assert.equal(listB.body.data.length, 0, 'patient B sees no documents');

  const getB = await h.request(h.app).get(`/api/documents/${docId}`).set('Authorization', `Bearer ${b.accessToken}`);
  assert.equal(getB.status, 404);

  const fileB = await h.request(h.app).get(`/api/documents/${docId}/file`).set('Authorization', `Bearer ${b.accessToken}`);
  assert.equal(fileB.status, 404);
});

test('protected document file can be downloaded by its owner only', async () => {
  const a = await h.register('patient');
  const up = await h.request(h.app).post('/api/documents')
    .set('Authorization', `Bearer ${a.accessToken}`)
    .field('category', 'laboratory')
    .attach('file', Buffer.from(LAB_TEXT), { filename: 'lab.txt', contentType: 'text/plain' });
  const docId = up.body.data.document.id;
  const res = await h.request(h.app).get(`/api/documents/${docId}/file`).set('Authorization', `Bearer ${a.accessToken}`);
  assert.equal(res.status, 200);
  assert.match(res.headers['content-type'], /text\/plain/);
});

test('extracted records expose the client `id` the review screen verifies with', async () => {
  const u = await h.register('patient');
  const up = await h.request(h.app).post('/api/documents')
    .set('Authorization', `Bearer ${u.accessToken}`)
    .field('category', 'laboratory')
    .attach('file', Buffer.from(LAB_TEXT), { filename: 'lab.txt', contentType: 'text/plain' });
  assert.equal(up.status, 201);
  const docId = up.body.data.document.id;

  const detail = await h.request(h.app).get(`/api/documents/${docId}`).set('Authorization', `Bearer ${u.accessToken}`);
  const extracted = detail.body.data.extracted;
  assert.ok(extracted.observations.length > 0);

  // The UI builds PATCH /api/records/:kind/:id/verify from `id`. Without it the
  // request collapses to /records/<kind>//verify and returns "Route not found".
  for (const [kind, rows] of Object.entries(extracted)) {
    for (const row of rows) {
      assert.ok(row.id, `${kind} record is missing id`);
      assert.equal(String(row.id), String(row._id), `${kind} id must match _id`);
    }
  }

  const obs = extracted.observations[0];
  const res = await h.request(h.app).patch(`/api/records/observation/${obs.id}/verify`)
    .set('Authorization', `Bearer ${u.accessToken}`)
    .send({ verification: 'verified' });
  assert.equal(res.status, 200, 'verification using the client id must succeed');
  assert.equal(res.body.data.verification, 'verified');
});
