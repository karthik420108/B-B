'use strict';

const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');
const { MedicationSchedule, MedicationDose } = require('../src/models');
const medicationService = require('../src/services/medicationService');

before(h.connect);
after(h.disconnect);
beforeEach(h.clearDatabase);

const DAY = 24 * 60 * 60 * 1000;
const TZ = 'UTC';

const PRESCRIPTION_TEXT = [
  'Riverside Family Clinic',
  'Prescription',
  'Date: 12 Mar 2026',
  'Rx',
  '1. Metformin 500 mg twice daily',
  '2. Amlodipine 5 mg once daily',
  '3. Atorvastatin 20 mg at bedtime',
].join('\n');

function scheduleBody(overrides = {}) {
  const start = new Date();
  const iso = `${start.getUTCFullYear()}-${String(start.getUTCMonth() + 1).padStart(2, '0')}-${String(start.getUTCDate()).padStart(2, '0')}`;
  return {
    name: 'Metformin',
    strength: '500 mg',
    doseInstructions: '1 tablet',
    route: 'oral',
    frequency: 'twice_daily',
    reminderTimes: ['08:00', '20:00'],
    startDate: iso,
    timezone: TZ,
    ...overrides,
  };
}

async function createSchedule(token, overrides = {}) {
  const res = await h.request(h.app).post('/api/medications')
    .set('Authorization', `Bearer ${token}`).send(scheduleBody(overrides));
  return res;
}

async function uploadPrescription(token, text = PRESCRIPTION_TEXT) {
  const res = await h.request(h.app).post('/api/documents')
    .set('Authorization', `Bearer ${token}`)
    .field('category', 'prescription')
    .attach('file', Buffer.from(text), { filename: 'rx.txt', contentType: 'text/plain' });
  return res.body.data.document.id;
}

// ---------------------------------------------------------------------------
// Creation + listing + ownership
// ---------------------------------------------------------------------------

test('creates a manual schedule and lists it for the owner', async () => {
  const u = await h.register('patient');
  const res = await createSchedule(u.accessToken);
  assert.equal(res.status, 201);
  assert.equal(res.body.data.schedule.name, 'Metformin');
  assert.equal(res.body.data.schedule.sourceType, 'MANUAL');
  assert.equal(res.body.data.schedule.confirmed, true);
  assert.ok(res.body.data.dosesCreated >= 1, 'occurrences generated');

  const list = await h.request(h.app).get('/api/medications').set('Authorization', `Bearer ${u.accessToken}`);
  assert.equal(list.status, 200);
  assert.equal(list.body.data.total, 1);
  assert.ok(Array.isArray(list.body.data.items[0].reminderTimes));
});

test('rejects invalid schedule input', async () => {
  const u = await h.register('patient');
  const cases = [
    scheduleBody({ name: '' }),
    scheduleBody({ reminderTimes: ['08:00', '08:00'] }),
    scheduleBody({ reminderTimes: ['25:00'] }),
    scheduleBody({ reminderTimes: ['08:00'], frequency: 'twice_daily' }),
    scheduleBody({ startDate: '2026-06-01', endDate: '2026-05-01' }),
    scheduleBody({ reminderTimes: [] }),
  ];
  for (const body of cases) {
    const res = await h.request(h.app).post('/api/medications').set('Authorization', `Bearer ${u.accessToken}`).send(body);
    assert.equal(res.status, 400, `expected 400 for ${JSON.stringify(body)}`);
  }
});

test('prevents accidental duplicate schedules', async () => {
  const u = await h.register('patient');
  assert.equal((await createSchedule(u.accessToken)).status, 201);
  const dup = await createSchedule(u.accessToken);
  assert.equal(dup.status, 409);
});

test('clientRequestId makes schedule creation idempotent', async () => {
  const u = await h.register('patient');
  const body = scheduleBody({ clientRequestId: 'req-123' });
  const first = await h.request(h.app).post('/api/medications').set('Authorization', `Bearer ${u.accessToken}`).send(body);
  const second = await h.request(h.app).post('/api/medications').set('Authorization', `Bearer ${u.accessToken}`).send(body);
  assert.equal(first.status, 201);
  assert.equal(second.status, 201);
  assert.equal(second.body.data.idempotent, true);
  assert.equal(String(second.body.data.schedule.id), String(first.body.data.schedule.id));
  assert.equal(await MedicationSchedule.countDocuments({ patient: u.user.id }), 1);
});

test('enforces patient ownership on schedules and doses', async () => {
  const a = await h.register('patient');
  const b = await h.register('patient');
  const created = await createSchedule(a.accessToken);
  const id = created.body.data.schedule.id;

  const detail = await h.request(h.app).get(`/api/medications/${id}`).set('Authorization', `Bearer ${b.accessToken}`);
  assert.equal(detail.status, 404);

  const patch = await h.request(h.app).patch(`/api/medications/${id}`).set('Authorization', `Bearer ${b.accessToken}`).send({ name: 'Hacked' });
  assert.equal(patch.status, 404);

  const list = await h.request(h.app).get('/api/medications').set('Authorization', `Bearer ${b.accessToken}`);
  assert.equal(list.body.data.total, 0);
});

test('a doctor cannot access medication schedules', async () => {
  const doc = await h.register('doctor');
  const res = await h.request(h.app).get('/api/medications').set('Authorization', `Bearer ${doc.accessToken}`);
  assert.equal(res.status, 403);
});

// ---------------------------------------------------------------------------
// Occurrence generation + status
// ---------------------------------------------------------------------------

test('occurrence generation is idempotent (no duplicate doses)', async () => {
  const u = await h.register('patient');
  const created = await createSchedule(u.accessToken);
  const schedule = await MedicationSchedule.findById(created.body.data.schedule.id);
  await medicationService.syncOccurrences(schedule);
  await medicationService.syncOccurrences(schedule, { fromDate: new Date() });
  const rows = await MedicationDose.find({ schedule: schedule._id }).lean();
  const keys = rows.map((r) => `${r.scheduledFor.toISOString()}`);
  assert.equal(new Set(keys).size, keys.length, 'no duplicate scheduledFor instants');
});

test('missed classification is derived server-side and never overwrites a recorded action', async () => {
  const u = await h.register('patient');
  const created = await createSchedule(u.accessToken);
  const scheduleId = created.body.data.schedule.id;
  const patient = u.user.id;

  const overdue = new Date(Date.now() - 2 * DAY);
  const recorded = await MedicationDose.create({ schedule: scheduleId, patient, scheduledFor: overdue, status: 'TAKEN', actedAt: overdue, actionSource: 'PATIENT' });
  await MedicationDose.create({ schedule: scheduleId, patient, scheduledFor: new Date(Date.now() - DAY), status: 'UPCOMING' });

  const history = await h.request(h.app).get('/api/medications/history').set('Authorization', `Bearer ${u.accessToken}`);
  assert.equal(history.status, 200);
  const statuses = history.body.data.items.map((d) => d.status);
  assert.ok(statuses.includes('MISSED'), 'unrecorded overdue dose becomes MISSED');
  assert.ok(statuses.includes('TAKEN'), 'recorded dose stays TAKEN');

  const kept = await MedicationDose.findById(recorded._id).lean();
  assert.equal(kept.status, 'TAKEN', 'a TAKEN dose is never converted to MISSED');
  assert.match(history.body.data.disclaimer || '', /not proof/i);
});

test('effectiveStatus respects due and tracking windows', () => {
  const now = new Date('2026-10-10T12:00:00Z');
  const due = new Date('2026-10-10T12:05:00Z');
  const upcoming = new Date('2026-10-10T14:00:00Z');
  const missed = new Date('2026-10-10T06:00:00Z');
  assert.equal(medicationService.effectiveStatus('UPCOMING', due, now), 'DUE');
  assert.equal(medicationService.effectiveStatus('UPCOMING', upcoming, now), 'UPCOMING');
  assert.equal(medicationService.effectiveStatus('UPCOMING', missed, now), 'MISSED');
  assert.equal(medicationService.effectiveStatus('TAKEN', missed, now), 'TAKEN');
  assert.equal(medicationService.effectiveStatus('SKIPPED', missed, now), 'SKIPPED');
});

test('timezone conversion resolves wall-clock times with DST offsets', () => {
  // 08:00 in New York on a summer date is 12:00 UTC (EDT, UTC-4).
  const summer = medicationService.zonedWallTimeToUtc(2026, 7, 15, 8, 0, 'America/New_York');
  assert.equal(summer.toISOString(), '2026-07-15T12:00:00.000Z');
  // 08:00 in New York on a winter date is 13:00 UTC (EST, UTC-5).
  const winter = medicationService.zonedWallTimeToUtc(2026, 1, 15, 8, 0, 'America/New_York');
  assert.equal(winter.toISOString(), '2026-01-15T13:00:00.000Z');
});

// ---------------------------------------------------------------------------
// Dose actions
// ---------------------------------------------------------------------------

async function firstDoseFor(token) {
  const today = await h.request(h.app).get('/api/medications/doses/today?tz=UTC').set('Authorization', `Bearer ${token}`);
  assert.equal(today.status, 200);
  assert.ok(today.body.data.items.length >= 1, 'today has doses');
  return today.body.data.items[0];
}

test('records a dose as Taken and as Skipped, idempotently', async () => {
  const u = await h.register('patient');
  await createSchedule(u.accessToken);
  const dose = await firstDoseFor(u.accessToken);

  const taken = await h.request(h.app).post(`/api/medications/doses/${dose.id}/action`)
    .set('Authorization', `Bearer ${u.accessToken}`).send({ action: 'TAKEN' });
  assert.equal(taken.status, 200);
  assert.equal(taken.body.data.dose.status, 'TAKEN');
  assert.equal(taken.body.data.dose.actionSource, 'PATIENT');

  const again = await h.request(h.app).post(`/api/medications/doses/${dose.id}/action`)
    .set('Authorization', `Bearer ${u.accessToken}`).send({ action: 'TAKEN' });
  assert.equal(again.status, 200);
  assert.equal(again.body.data.idempotent, true);

  const conflicting = await h.request(h.app).post(`/api/medications/doses/${dose.id}/action`)
    .set('Authorization', `Bearer ${u.accessToken}`).send({ action: 'SKIPPED' });
  assert.equal(conflicting.status, 409, 'a recorded dose cannot be flipped');
});

test('dose action is rejected for another patient and for unknown states', async () => {
  const a = await h.register('patient');
  const b = await h.register('patient');
  await createSchedule(a.accessToken);
  const dose = await firstDoseFor(a.accessToken);

  const foreign = await h.request(h.app).post(`/api/medications/doses/${dose.id}/action`)
    .set('Authorization', `Bearer ${b.accessToken}`).send({ action: 'TAKEN' });
  assert.equal(foreign.status, 404);

  const bad = await h.request(h.app).post(`/api/medications/doses/${dose.id}/action`)
    .set('Authorization', `Bearer ${a.accessToken}`).send({ action: 'MISSED' });
  assert.equal(bad.status, 400, 'client cannot set an arbitrary status');
});

// ---------------------------------------------------------------------------
// Editing + lifecycle preserves history
// ---------------------------------------------------------------------------

test('editing a schedule preserves historical dose actions but refreshes future occurrences', async () => {
  const u = await h.register('patient');
  const created = await createSchedule(u.accessToken);
  const id = created.body.data.schedule.id;
  const patient = u.user.id;

  const past = new Date(Date.now() - 2 * DAY);
  const taken = await MedicationDose.create({ schedule: id, patient, scheduledFor: past, status: 'TAKEN', actedAt: past, actionSource: 'PATIENT' });

  const patch = await h.request(h.app).patch(`/api/medications/${id}`)
    .set('Authorization', `Bearer ${u.accessToken}`).send({ reminderTimes: ['09:00', '21:00'] });
  assert.equal(patch.status, 200);

  const keptHistory = await MedicationDose.findById(taken._id).lean();
  assert.ok(keptHistory, 'historical dose is preserved');
  assert.equal(keptHistory.status, 'TAKEN');

  const future = await MedicationDose.find({ schedule: id, scheduledFor: { $gte: new Date() } }).lean();
  assert.ok(future.every((d) => ['09:00', '21:00'].includes(new Date(d.scheduledFor).toISOString().slice(11, 16)) || d.status !== 'UPCOMING'));
});

test('pause cancels future reminders, resume regenerates them, discontinue preserves history', async () => {
  const u = await h.register('patient');
  const created = await createSchedule(u.accessToken);
  const id = created.body.data.schedule.id;

  const paused = await h.request(h.app).post(`/api/medications/${id}/pause`).set('Authorization', `Bearer ${u.accessToken}`);
  assert.equal(paused.status, 200);
  assert.equal(paused.body.data.schedule.status, 'PAUSED');
  assert.equal(await MedicationDose.countDocuments({ schedule: id, status: 'UPCOMING', scheduledFor: { $gte: new Date() } }), 0);

  const resumed = await h.request(h.app).post(`/api/medications/${id}/resume`).set('Authorization', `Bearer ${u.accessToken}`);
  assert.equal(resumed.body.data.schedule.status, 'ACTIVE');
  assert.ok(await MedicationDose.countDocuments({ schedule: id, scheduledFor: { $gte: new Date() } }) >= 1);

  const discontinued = await h.request(h.app).post(`/api/medications/${id}/discontinue`).set('Authorization', `Bearer ${u.accessToken}`);
  assert.equal(discontinued.body.data.schedule.status, 'DISCONTINUED');
  assert.equal(await MedicationSchedule.countDocuments({ _id: id }), 1, 'schedule row preserved');
});

test('completed/discontinued schedules require explicit confirmation to reopen', async () => {
  const u = await h.register('patient');
  const created = await createSchedule(u.accessToken);
  const id = created.body.data.schedule.id;
  await h.request(h.app).post(`/api/medications/${id}/discontinue`).set('Authorization', `Bearer ${u.accessToken}`);

  const silent = await h.request(h.app).post(`/api/medications/${id}/resume`).set('Authorization', `Bearer ${u.accessToken}`).send({});
  assert.equal(silent.status, 409);

  const confirmed = await h.request(h.app).post(`/api/medications/${id}/resume`).set('Authorization', `Bearer ${u.accessToken}`).send({ confirmReopen: true });
  assert.equal(confirmed.status, 200);
  assert.equal(confirmed.body.data.schedule.status, 'ACTIVE');
});

// ---------------------------------------------------------------------------
// Prescription extraction + confirmation
// ---------------------------------------------------------------------------

test('extracts candidate medications without creating any schedule', async () => {
  const u = await h.register('patient');
  const documentId = await uploadPrescription(u.accessToken);
  const res = await h.request(h.app).post('/api/medications/extract')
    .set('Authorization', `Bearer ${u.accessToken}`).send({ documentId });
  assert.equal(res.status, 200);
  assert.ok(res.body.data.candidates.length >= 1);
  const metformin = res.body.data.candidates.find((c) => /metformin/i.test(c.name));
  assert.ok(metformin, 'metformin candidate found');
  assert.ok(Array.isArray(metformin.uncertainFields));
  assert.equal(await MedicationSchedule.countDocuments({ patient: u.user.id }), 0, 'nothing persisted before confirmation');
  assert.match(res.body.data.note, /confirm/i);
});

test('prescription extraction rejects another patient\'s document', async () => {
  const a = await h.register('patient');
  const b = await h.register('patient');
  const documentId = await uploadPrescription(a.accessToken);
  const res = await h.request(h.app).post('/api/medications/extract')
    .set('Authorization', `Bearer ${b.accessToken}`).send({ documentId });
  assert.equal(res.status, 404);
});

test('unreadable prescriptions return a helpful error', async () => {
  const u = await h.register('patient');
  // A note with no medication section recovers text but yields no candidates.
  const up = await h.request(h.app).post('/api/documents')
    .set('Authorization', `Bearer ${u.accessToken}`).field('category', 'prescription')
    .attach('file', Buffer.from('Clinic note. Please rest and drink water.'), { filename: 'note.txt', contentType: 'text/plain' });
  const documentId = up.body.data.document.id;
  const res = await h.request(h.app).post('/api/medications/extract')
    .set('Authorization', `Bearer ${u.accessToken}`).send({ documentId });
  assert.equal(res.status, 422);
  assert.match(String(res.body.error.message), /manually/i);
});

test('confirmation is required before a prescription schedule is created', async () => {
  const u = await h.register('patient');
  const documentId = await uploadPrescription(u.accessToken);
  const medication = scheduleBody({ name: 'Metformin', frequency: 'twice_daily' });

  const unconfirmed = await h.request(h.app).post('/api/medications/confirm')
    .set('Authorization', `Bearer ${u.accessToken}`).send({ documentId, medication });
  assert.equal(unconfirmed.status, 400);
  assert.equal(await MedicationSchedule.countDocuments({ patient: u.user.id }), 0);

  const confirmed = await h.request(h.app).post('/api/medications/confirm')
    .set('Authorization', `Bearer ${u.accessToken}`)
    .send({ documentId, confirmed: true, snippet: '1. Metformin 500 mg twice daily', medication });
  assert.equal(confirmed.status, 201);
  const schedule = await MedicationSchedule.findById(confirmed.body.data.schedule.id);
  assert.equal(schedule.sourceType, 'PRESCRIPTION');
  assert.equal(String(schedule.sourceDocument), String(documentId));
  assert.equal(schedule.confirmed, true);
  assert.equal(String(schedule.extraction.documentName), 'rx.txt');
});
