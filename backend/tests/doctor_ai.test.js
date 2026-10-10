'use strict';

const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');
const { DoctorProfile, Document, ShareGrant, DoctorConversation } = require('../src/models');

before(h.connect);
after(h.disconnect);
beforeEach(h.clearDatabase);

/** Register a doctor and mark them verified (share mechanics are tested elsewhere). */
async function verifiedDoctor() {
  const doctor = await h.register('doctor');
  await DoctorProfile.updateOne(
    { user: doctor.user.id },
    { $set: { verification: { status: 'verified', method: 'test', verifiedAt: new Date() } } },
  );
  return doctor;
}

/**
 * Build a patient with dated lab reports carrying real HbA1c values so
 * cross-date comparison questions have documented evidence to work from.
 */
async function patientWithDatedReports() {
  const patient = await h.register('patient');
  const reports = [
    { date: '2026-01-15', hba1c: '8.1', name: 'lab-hba1c-jan.txt' },
    { date: '2026-04-20', hba1c: '7.4', name: 'lab-hba1c-apr.txt' },
    { date: '2026-07-25', hba1c: '6.9', name: 'lab-hba1c-jul.txt' },
  ];
  const docs = [];
  for (const r of reports) {
    // eslint-disable-next-line no-await-in-loop
    const res = await h.request(h.app).post('/api/documents')
      .set('Authorization', `Bearer ${patient.accessToken}`)
      .field('category', 'laboratory')
      .field('providerName', 'Northlake Diagnostic Laboratory')
      .field('eventDate', r.date)
      .attach('file', Buffer.from(`Northlake Diagnostic Laboratory\nHbA1c ${r.hba1c} % (4.0 - 5.6) H\nFasting Glucose 1${r.hba1c.slice(0, 1)}0 mg/dL`), { filename: r.name, contentType: 'text/plain' });
    assert.equal(res.status, 201);
    docs.push({ ...res.body.data.document, expectedHba1c: r.hba1c, reportDate: r.date });
  }
  return { patient, docs };
}

/** Create an all-documents share bound to the given doctor. */
async function shareAll(patient, doctor) {
  const res = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ includeAll: true, expiresInMinutes: 60, doctorUserId: doctor.user.id });
  assert.equal(res.status, 201);
  return { shareId: res.body.data.share.id, token: res.body.data.token };
}

test('doctor AI summarizes a patient history grounded in the actual shared records', async () => {
  const { patient, docs } = await patientWithDatedReports();
  const doctor = await verifiedDoctor();
  const { shareId } = await shareAll(patient, doctor);

  const res = await h.request(h.app).post(`/api/doctor/shares/${shareId}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'Summarize this patient\'s medical history.' });

  assert.equal(res.status, 200);
  assert.equal(res.body.data.grounded, true);
  // The summary must cite real evidence from the shared documents.
  assert.ok(res.body.data.citations.length > 0, 'summary must cite sources');
  assert.ok(res.body.data.answer.includes('HbA1c'), 'summary should surface the documented lab test');
  // Coverage reporting must be present so unreadable files are visible.
  assert.ok(res.body.data.coverage, 'coverage must be reported');
  assert.equal(res.body.data.coverage.documentsInScope, docs.length);
});

test('cross-date comparison uses the documented values and cites each source document', async () => {
  const { patient, docs } = await patientWithDatedReports();
  const doctor = await verifiedDoctor();
  const { shareId } = await shareAll(patient, doctor);

  const res = await h.request(h.app).post(`/api/doctor/shares/${shareId}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'Compare the latest HbA1c result with the previous reports.' });

  assert.equal(res.status, 200);
  const answer = res.body.data.answer;
  // Documented values and dates must appear, in the right direction.
  assert.ok(answer.includes('8.1'), 'earliest documented HbA1c must appear');
  assert.ok(answer.includes('6.9'), 'latest documented HbA1c must appear');
  assert.ok(/decrease/i.test(answer), 'documented downward trend must be described');
  // Citations must reference the source documents so the doctor can verify.
  const citedDocIds = new Set(res.body.data.citations.map((c) => c.documentId).filter(Boolean));
  for (const d of docs) assert.ok(citedDocIds.has(d.id), `report ${d.originalName} must be citable`);
});

test('follow-up questions keep the same patient context and never another patient', async () => {
  const { patient: p1, docs: d1 } = await patientWithDatedReports();
  const doctor = await verifiedDoctor();
  const { shareId: s1 } = await shareAll(p1, doctor);

  // Ask a first question, then a bare follow-up with almost no vocabulary.
  await h.request(h.app).post(`/api/doctor/shares/${s1}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'What are the HbA1c results over time?' });
  const followUp = await h.request(h.app).post(`/api/doctor/shares/${s1}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'What about the previous report?' });

  assert.equal(followUp.status, 200);
  assert.ok(followUp.body.data.conversationTurns >= 2, 'conversation history must be replayed');

  // A second patient's thread must be entirely separate.
  const { patient: p2 } = await patientWithDatedReports();
  const { shareId: s2 } = await shareAll(p2, doctor);
  const conv1 = await h.request(h.app).get(`/api/doctor/shares/${s1}/ai/conversation`)
    .set('Authorization', `Bearer ${doctor.accessToken}`);
  const conv2 = await h.request(h.app).get(`/api/doctor/shares/${s2}/ai/conversation`)
    .set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.ok(conv1.body.data.messages.length >= 4, 'first patient thread stored');
  assert.equal(conv2.body.data.messages.length, 0, 'second patient thread must start empty');
  assert.equal(conv1.body.data.patient, String(p1.user.id));
  assert.equal(conv2.body.data.patient, String(p2.user.id));
  assert.ok(d1.length > 0);
});

test('doctor can open a cited source document and out-of-scope files are refused', async () => {
  const { patient, docs } = await patientWithDatedReports();
  const doctor = await verifiedDoctor();

  // Share only the first two reports.
  const res = await h.request(h.app).post('/api/shares').set('Authorization', `Bearer ${patient.accessToken}`)
    .send({ documentIds: [docs[0].id, docs[1].id], includeAll: false, expiresInMinutes: 60, doctorUserId: doctor.user.id });
  const shareId = res.body.data.share.id;

  const ask = await h.request(h.app).post(`/api/doctor/shares/${shareId}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'What are the HbA1c results?' });
  assert.equal(ask.status, 200);
  // Every cited document must be inside the share scope.
  for (const c of ask.body.data.citations) {
    if (c.documentId) assert.ok([docs[0].id, docs[1].id].includes(c.documentId), 'citation must be in scope');
  }

  // Opening an in-scope source file works.
  const openOk = await h.request(h.app).get(`/api/doctor/shares/${shareId}/documents/${docs[0].id}/file`)
    .set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(openOk.status, 200);

  // Opening an out-of-scope file is refused.
  const openNo = await h.request(h.app).get(`/api/doctor/shares/${shareId}/documents/${docs[2].id}/file`)
    .set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(openNo.status, 403);

  // Explicitly asking the AI to focus on an out-of-scope file is refused.
  const askNo = await h.request(h.app).post(`/api/doctor/shares/${shareId}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'What does the July report say?', documentIds: [docs[2].id] });
  assert.equal(askNo.status, 403);
});

test('a different patient\'s file id cannot be reached through another doctor\'s grant', async () => {
  const { patient: p1 } = await patientWithDatedReports();
  const { patient: p2, docs: d2 } = await patientWithDatedReports();
  const doctor = await verifiedDoctor();
  const { shareId } = await shareAll(p1, doctor);

  // Probe with another patient's document id.
  const res = await h.request(h.app).post(`/api/doctor/shares/${shareId}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'What does this document say?', documentIds: [d2[0].id] });
  assert.equal(res.status, 403);

  const fileRes = await h.request(h.app).get(`/api/doctor/shares/${shareId}/documents/${d2[0].id}/file`)
    .set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.ok(fileRes.status === 403 || fileRes.status === 404, 'cross-patient file access must be denied');
  assert.ok(p2.user.id);
});

test('revocation blocks subsequent AI questions, follow-ups, conversation and file access', async () => {
  const { patient, docs } = await patientWithDatedReports();
  const doctor = await verifiedDoctor();
  const { shareId } = await shareAll(patient, doctor);

  const first = await h.request(h.app).post(`/api/doctor/shares/${shareId}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'What are the HbA1c results?' });
  assert.equal(first.status, 200);

  await h.request(h.app).post(`/api/shares/${shareId}/revoke`)
    .set('Authorization', `Bearer ${patient.accessToken}`).send({ reason: 'revoked' });

  const after = await h.request(h.app).post(`/api/doctor/shares/${shareId}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'What about the previous report?' });
  assert.equal(after.status, 403);

  const conv = await h.request(h.app).get(`/api/doctor/shares/${shareId}/ai/conversation`)
    .set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(conv.status, 403, 'conversation retrieval must also be denied');

  const file = await h.request(h.app).get(`/api/doctor/shares/${shareId}/documents/${docs[0].id}/file`)
    .set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(file.status, 403);
});

test('an unverified doctor cannot use the patient-history AI at all', async () => {
  const { patient } = await patientWithDatedReports();
  const unverified = await h.register('doctor');
  const { shareId } = await shareAll(patient, await verifiedDoctor());

  const res = await h.request(h.app).post(`/api/doctor/shares/${shareId}/ai/ask`)
    .set('Authorization', `Bearer ${unverified.accessToken}`)
    .send({ question: 'Summarize this patient\'s medical history.' });
  assert.ok(res.status === 403 || res.status === 401, 'unverified doctor must be blocked');
});

test('unreadable documents are reported as not analysed, never silently ignored', async () => {
  const { patient, docs } = await patientWithDatedReports();
  const doctor = await verifiedDoctor();

  // Add a document whose extraction failed (no readable text).
  await Document.updateOne(
    { _id: docs[2].id },
    { $set: { extractionStatus: 'failed', extractionError: 'No text could be recovered (image-only scan).', rawText: null, textSource: 'none' } },
  );

  const { shareId } = await shareAll(patient, doctor);
  const res = await h.request(h.app).post(`/api/doctor/shares/${shareId}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'Summarize this patient\'s medical history.' });

  assert.equal(res.status, 200);
  assert.equal(res.body.data.coverage.unreadable.length, 1);
  assert.equal(res.body.data.coverage.unreadable[0].documentId, docs[2].id);
  assert.match(res.body.data.answer, /could not be analysed/i, 'answer must disclose the unreadable file');
  assert.equal(res.body.data.uncertainty.level, 'high');
});

test('a question with no supporting evidence returns an explicit insufficient-information answer', async () => {
  const { patient } = await patientWithDatedReports();
  const doctor = await verifiedDoctor();
  const { shareId } = await shareAll(patient, doctor);

  const res = await h.request(h.app).post(`/api/doctor/shares/${shareId}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'What was the patient\'s last brain MRI result?' });

  assert.equal(res.status, 200);
  assert.equal(res.body.data.citations.length, 0, 'no evidence means no citations');
  assert.equal(res.body.data.uncertainty.missing, true);
  assert.match(res.body.data.answer, /no relevant records|could not find/i);
});

test('resetting the conversation clears only that doctor\'s thread for that share', async () => {
  const { patient } = await patientWithDatedReports();
  const doctor = await verifiedDoctor();
  const otherDoctor = await verifiedDoctor();
  const { shareId } = await shareAll(patient, doctor);

  await h.request(h.app).post(`/api/doctor/shares/${shareId}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'What are the HbA1c results?' });

  const cleared = await h.request(h.app).delete(`/api/doctor/shares/${shareId}/ai/conversation`)
    .set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(cleared.status, 200);
  const conv = await h.request(h.app).get(`/api/doctor/shares/${shareId}/ai/conversation`)
    .set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(conv.body.data.messages.length, 0);

  // A different doctor still cannot read this grant's thread.
  const other = await h.request(h.app).get(`/api/doctor/shares/${shareId}/ai/conversation`)
    .set('Authorization', `Bearer ${otherDoctor.accessToken}`);
  assert.equal(other.status, 403);

  assert.equal(await DoctorConversation.countDocuments({}), 0);
});

test('token-based doctor AI follows the same scope, conversation and revocation rules', async () => {
  const { patient, docs } = await patientWithDatedReports();
  const doctor = await verifiedDoctor();
  const { token, shareId } = await shareAll(patient, doctor);

  const ask = await h.request(h.app).post(`/api/share/${token}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'What are the HbA1c results?' });
  assert.equal(ask.status, 200);
  assert.equal(ask.body.data.grounded, true);

  const conv = await h.request(h.app).get(`/api/share/${token}/ai/conversation`)
    .set('Authorization', `Bearer ${doctor.accessToken}`);
  assert.equal(conv.status, 200);
  assert.ok(conv.body.data.messages.length >= 2);

  // Out-of-scope file focus refused via the token route too.
  const focusNo = await h.request(h.app).post(`/api/share/${token}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'Summarize that file.', documentIds: ['ffffffffffffffffffffffff'] });
  assert.equal(focusNo.status, 403);

  await h.request(h.app).post(`/api/shares/${shareId}/revoke`)
    .set('Authorization', `Bearer ${patient.accessToken}`).send({ reason: 'done' });

  const after = await h.request(h.app).post(`/api/share/${token}/ai/ask`)
    .set('Authorization', `Bearer ${doctor.accessToken}`)
    .send({ question: 'What about the previous report?' });
  assert.equal(after.status, 403);
  assert.ok(docs.length === 3);
});

test('a conversation is bound to the doctor who started it', async () => {
  const { patient } = await patientWithDatedReports();
  const doctorA = await verifiedDoctor();
  const doctorB = await verifiedDoctor();
  // Two separate shares so both doctors are legitimately authorized.
  const a = await shareAll(patient, doctorA);
  const b = await shareAll(patient, doctorB);

  await h.request(h.app).post(`/api/doctor/shares/${a.shareId}/ai/ask`)
    .set('Authorization', `Bearer ${doctorA.accessToken}`)
    .send({ question: 'What are the HbA1c results?' });

  // Doctor B cannot read doctor A's thread even on a share they both could use.
  const cross = await h.request(h.app).get(`/api/doctor/shares/${b.shareId}/ai/conversation`)
    .set('Authorization', `Bearer ${doctorB.accessToken}`);
  assert.equal(cross.status, 200);
  assert.equal(cross.body.data.messages.length, 0, 'each doctor has an isolated thread');

  // And doctor B cannot use doctor A's share id at all.
  const hijack = await h.request(h.app).get(`/api/doctor/shares/${a.shareId}/ai/conversation`)
    .set('Authorization', `Bearer ${doctorB.accessToken}`);
  assert.equal(hijack.status, 403);

  // A token bound to A rejects B.
  const tokenB = await h.request(h.app).get(`/api/share/${a.token}/bundle`)
    .set('Authorization', `Bearer ${doctorB.accessToken}`);
  assert.equal(tokenB.status, 403);
});
