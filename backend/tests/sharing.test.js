'use strict';

const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');
const { Document, ShareGrant, Observation } = require('../src/models');
const { hashToken } = require('../src/utils/crypto');

before(h.connect);
after(h.disconnect);
beforeEach(h.clearDatabase);

async function patientWithDocs() {
  const patient = await h.register('patient');
  const docs = [];
  for (let i = 0; i < 3; i += 1) {
    // eslint-disable-next-line no-await-in-loop
    const up = await h.request(h.app).post('/api/documents')
      .set('Authorization', `Bearer ${patient.accessToken}`)
      .field('category', 'laboratory')
      .field('providerName', `Provider ${i}`)
      .attach('file', Buffer.from(`Provider ${i}\nLaboratory Results\nSodium 14${i} mmol/L`), { filename: `d${i}.txt`, contentType: 'text/plain' });
    docs.push(up.body.data.document);
  }
  return { patient, docs };
}

/** Register a doctor and mark them verified (share mechanics are tested elsewhere). */
async function verifiedDoctor() {
  const doctor = await h.register('doctor');
  const { DoctorProfile } = require('../src/models');
  await DoctorProfile.updateOne(
    { user: doctor.user.id },
    { $set: { verification: { status: 'verified', method: 'test', verifiedAt: new Date() } } },
  );
  return doctor;
}

test('share tokens are high-entropy and stored only as hashes', async () => {
  const { patient, docs } = await patientWithDocs();
  const res = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ documentIds: [docs[0].id], expiresInMinutes: 60 });
  assert.equal(res.status, 201);
  const token = res.body.data.token;
  assert.ok(token.length >= 40, 'token is long/random');
  // The raw token must not be persisted.
  const stored = await ShareGrant.findOne({ patient: patient.user.id }).select('+tokenHash').lean();
  assert.ok(stored.tokenHash);
  assert.equal(stored.tokenHash, hashToken(token));
  assert.notEqual(stored.tokenHash, token);
  assert.ok(!JSON.stringify(stored).includes(token), 'raw token must not be stored');
});

test('a doctor sees ONLY the records included in the active share', async () => {
  const { patient, docs } = await patientWithDocs();
  const doctor = await verifiedDoctor();
  const share = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ documentIds: [docs[0].id], includeAll: false, includeMedications: false, expiresInMinutes: 120 });
  const token = share.body.data.token;

  const bundle = await h.request(h.app).post(`/api/share/${token}/claim`).send({}).set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(bundle.status, 200);
  assert.equal(bundle.body.data.documents.length, 1);
  assert.equal(bundle.body.data.documents[0].id, docs[0].id);
  // The 2nd document must not be visible via the file endpoint.
  const forbidden = await h.request(h.app).get(`/api/share/${token}/documents/${docs[1].id}/file`).set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(forbidden.status, 403);
  const allowed = await h.request(h.app).get(`/api/share/${token}/documents/${docs[0].id}/file`).set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(allowed.status, 200);
});

test('a different doctor cannot use a share bound to another doctor', async () => {
  const { patient, docs } = await patientWithDocs();
  const d1 = await verifiedDoctor();
  const d2 = await verifiedDoctor();
  const share = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ documentIds: [docs[0].id], doctorUserId: d1.user.id, expiresInMinutes: 120 });
  const token = share.body.data.token;

  const ok = await h.request(h.app).post(`/api/share/${token}/claim`).send({}).set('Authorization', `Bearer ${d1.accessToken}`);
  assert.equal(ok.status, 200);
  const denied = await h.request(h.app).get(`/api/share/${token}/bundle`).set('Authorization', `Bearer ${d2.accessToken}`);
  assert.equal(denied.status, 403);
});

test('unauthenticated access to a share bundle is rejected', async () => {
  const { patient, docs } = await patientWithDocs();
  const share = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ documentIds: [docs[0].id], expiresInMinutes: 60 });
  const res = await h.request(h.app).get(`/api/share/${share.body.data.token}/bundle`);
  assert.equal(res.status, 401);
});

test('patients cannot share records they do not own', async () => {
  const a = await patientWithDocs();
  const b = await h.register('patient');
  const res = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${b.accessToken}`)
    .send({ documentIds: [a.docs[0].id], expiresInMinutes: 60 });
  assert.equal(res.status, 400);
});

test('revocation takes effect immediately server-side and is audited', async () => {
  const { patient, docs } = await patientWithDocs();
  const doctor = await verifiedDoctor();
  const share = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ documentIds: [docs[0].id], expiresInMinutes: 120 });
  const token = share.body.data.token;
  const shareId = share.body.data.share.id;

  await h.request(h.app).post(`/api/share/${token}/claim`).send({}).set('Authorization', `Bearer ${doctor.accessToken}`);
  const before = await h.request(h.app).get(`/api/share/${token}/bundle`).set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(before.status, 200);

  const revoke = await h.request(h.app).post(`/api/shares/${shareId}/revoke`).set('Authorization', `Bearer ${patient.accessToken}`).send({ reason: 'no longer needed' });
  assert.equal(revoke.status, 200);
  assert.equal(revoke.body.data.status, 'revoked');

  const after = await h.request(h.app).get(`/api/share/${token}/bundle`).set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(after.status, 403, 'access denied after revocation');

  const audit = await h.request(h.app).get('/api/audit').set('Authorization', `Bearer ${patient.accessToken}`);
  const actions = audit.body.data.items.map((a) => a.action);
  assert.ok(actions.includes('share.created'));
  assert.ok(actions.includes('share.revoked'));
  assert.ok(actions.includes('share.viewed'));
});

test('expired shares are denied and re-validated on every access', async () => {
  const { patient, docs } = await patientWithDocs();
  const doctor = await verifiedDoctor();
  const share = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ documentIds: [docs[0].id], expiresInMinutes: 60 });
  const token = share.body.data.token;
  await h.request(h.app).post(`/api/share/${token}/claim`).send({}).set('Authorization', `Bearer ${doctor.accessToken}`);
  // Force expiry in the database.
  await ShareGrant.updateOne({ _id: share.body.data.share.id }, { $set: { expiresAt: new Date(Date.now() - 1000) } });
  const res = await h.request(h.app).get(`/api/share/${token}/bundle`).set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(res.status, 403);
});

test('max-access limit is enforced', async () => {
  const { patient, docs } = await patientWithDocs();
  const doctor = await verifiedDoctor();
  const share = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ documentIds: [docs[0].id], expiresInMinutes: 120, maxAccesses: 1 });
  const token = share.body.data.token;
  const first = await h.request(h.app).post(`/api/share/${token}/claim`).send({}).set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(first.status, 200);
  const second = await h.request(h.app).get(`/api/share/${token}/bundle`).set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(second.status, 403);
});

test('share access history is visible to the owning patient', async () => {
  const { patient, docs } = await patientWithDocs();
  const doctor = await verifiedDoctor();
  const share = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ documentIds: [docs[0].id], expiresInMinutes: 120, doctorName: 'Dr. Who' });
  await h.request(h.app).post(`/api/share/${share.body.data.token}/claim`).send({}).set('Authorization', `Bearer ${doctor.accessToken}`);
  const detail = await h.request(h.app).get(`/api/shares/${share.body.data.share.id}`).set('Authorization', `Bearer ${patient.accessToken}`);
  assert.equal(detail.status, 200);
  const acts = detail.body.data.accessLog.map((a) => a.action);
  assert.ok(acts.includes('granted'));
  assert.ok(acts.includes('viewed'));
});

test('shares cannot be created without selecting records', async () => {
  const patient = await h.register('patient');
  const res = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`).send({ documentIds: [], includeAll: false });
  assert.equal(res.status, 400);
});

test('unverified doctors cannot access patient records (claim, bundle, file, list)', async () => {
  const { patient, docs } = await patientWithDocs();
  const doctor = await h.register('doctor'); // self-registered => unverified
  const share = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ documentIds: [docs[0].id], expiresInMinutes: 120 });
  const token = share.body.data.token;

  const claim = await h.request(h.app).post(`/api/share/${token}/claim`).send({}).set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(claim.status, 403, 'unverified doctor must not claim a share');

  const bundle = await h.request(h.app).get(`/api/share/${token}/bundle`).set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(bundle.status, 403, 'unverified doctor must not fetch the bundle');

  const file = await h.request(h.app).get(`/api/share/${token}/documents/${docs[0].id}/file`).set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(file.status, 403, 'unverified doctor must not download files');

  const list = await h.request(h.app).get('/api/doctor/shares').set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(list.status, 403, 'unverified doctor must not list shares');
});

test('development verification workflow grants access only after approval', async () => {
  const { patient, docs } = await patientWithDocs();
  const doctor = await h.register('doctor');
  const share = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ documentIds: [docs[0].id], expiresInMinutes: 120 });
  const token = share.body.data.token;

  // The verify endpoint is locked down without the dev key.
  process.env.DOCTOR_VERIFY_KEY = 'dev-verify-key-123';
  try {
    const noKey = await h.request(h.app).post('/api/doctor/verify').send({ email: doctor.email }).set('Authorization', `Bearer ${doctor.accessToken}`);
    assert.equal(noKey.status, 403, 'verify endpoint must require the key');

    const wrongKey = await h.request(h.app).post('/api/doctor/verify').send({ email: doctor.email }).set('Authorization', `Bearer ${doctor.accessToken}`).set('X-Doctor-Verify-Key', 'wrong');
    assert.equal(wrongKey.status, 403, 'verify endpoint must reject a wrong key');

    const ok = await h.request(h.app).post('/api/doctor/verify').send({ email: doctor.email }).set('Authorization', `Bearer ${doctor.accessToken}`).set('X-Doctor-Verify-Key', 'dev-verify-key-123');
    assert.equal(ok.status, 200);
    assert.equal(ok.body.data.status, 'verified');

    // Now the same doctor can claim the share.
    const claim = await h.request(h.app).post(`/api/share/${token}/claim`).send({}).set('Authorization', `Bearer ${doctor.accessToken}`);
    assert.equal(claim.status, 200);
    assert.equal(claim.body.data.documents.length, 1);
  } finally {
    delete process.env.DOCTOR_VERIFY_KEY;
  }
});

test('doctor verification status is returned at login', async () => {
  const doctor = await h.register('doctor');
  const res = await h.login(doctor.email, doctor.password);
  assert.equal(res.user.doctorVerification, 'unverified');
});

test('inspectToken returns status and isActive', async () => {
  const { patient, docs } = await patientWithDocs();
  const share = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ documentIds: [docs[0].id], expiresInMinutes: 60 });
  const inspect = await h.request(h.app).get(`/api/share/${share.body.data.token}/inspect`);
  assert.equal(inspect.status, 200);
  assert.equal(inspect.body.data.valid, true);
  assert.equal(inspect.body.data.status, 'active');
  assert.equal(inspect.body.data.isActive, true);
});

test('doctor can stream document file by shareId within scope, denied out of scope or revoked', async () => {
  const { patient, docs } = await patientWithDocs();
  const doctor = await verifiedDoctor();
  const share = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ documentIds: [docs[0].id, docs[1].id], includeAll: false, expiresInMinutes: 60, doctorUserId: doctor.user.id });
  const shareId = share.body.data.share.id;

  // Stream shared document
  const fileRes = await h.request(h.app).get(`/api/doctor/shares/${shareId}/documents/${docs[0].id}/file`).set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(fileRes.status, 200);

  // Unshared document (docs[2]) must be denied
  const unsharedRes = await h.request(h.app).get(`/api/doctor/shares/${shareId}/documents/${docs[2].id}/file`).set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(unsharedRes.status, 403);

  // Revoke share
  await h.request(h.app).post(`/api/shares/${shareId}/revoke`).set('Authorization', `Bearer ${patient.accessToken}`).send({ reason: 'testing' });

  // Stream after revoke must be denied
  const revokedRes = await h.request(h.app).get(`/api/doctor/shares/${shareId}/documents/${docs[0].id}/file`).set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(revokedRes.status, 403);
});

test('doctor AI assistant answers grounded in authorized scope and denies access when revoked', async () => {
  const { patient, docs } = await patientWithDocs();
  const doctor = await verifiedDoctor();
  const share = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ documentIds: [docs[0].id, docs[1].id], includeAll: false, expiresInMinutes: 60, doctorUserId: doctor.user.id });
  const shareId = share.body.data.share.id;
  const token = share.body.data.token;

  // Doctor AI query via shareId
  const aiRes = await h.request(h.app).post(`/api/doctor/shares/${shareId}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'What are the sodium test results?' });
  assert.equal(aiRes.status, 200);
  assert.equal(aiRes.body.data.grounded, true);
  assert.ok(aiRes.body.data.answer.includes('Sodium'));
  assert.ok(aiRes.body.data.citations.length > 0);

  // Citations only refer to shared documents
  const citedDocIds = aiRes.body.data.citations.map((c) => c.documentId).filter(Boolean);
  assert.ok(!citedDocIds.includes(docs[2].id), 'unshared doc must not be cited');

  // Token-based doctor AI query
  const tokenAiRes = await h.request(h.app).post(`/api/share/${token}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'Summarize the available medical history.' });
  assert.equal(tokenAiRes.status, 200);

  // Different doctor cannot query
  const otherDoctor = await verifiedDoctor();
  const diffDoctorRes = await h.request(h.app).post(`/api/doctor/shares/${shareId}/ai/ask`)
    .set('Authorization', `Bearer ${otherDoctor.accessToken}`)
    .send({ question: 'What are the test results?' });
  assert.equal(diffDoctorRes.status, 403);

  // Revoke share
  await h.request(h.app).post(`/api/shares/${shareId}/revoke`).set('Authorization', `Bearer ${patient.accessToken}`).send({ reason: 'revoked' });

  // Denied after revocation
  const revokedAi = await h.request(h.app).post(`/api/doctor/shares/${shareId}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'What are the test results?' });
  assert.equal(revokedAi.status, 403);
});

test('doctor can retrieve their identification QR info', async () => {
  const doctor = await verifiedDoctor();
  const res = await h.request(h.app).get('/api/doctor/me/qr').set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.data.type, 'doctor');
  assert.equal(res.body.data.doctorId, doctor.user.id);
  assert.equal(res.body.data.name, doctor.user.name);
  assert.equal(res.body.data.verification, 'verified');
});
