'use strict';

/* eslint-disable no-console */
/**
 * End-to-end medication-reminders workflow against a running API.
 * Usage: node scripts/e2e-medications.js [baseUrl]
 *
 * Exercises the full acceptance path:
 *   create manual schedule -> idempotent replay -> duplicate guard ->
 *   today/upcoming doses -> Taken/Skipped tracking -> history disclaimer ->
 *   pause/resume -> prescription extract (no persistence) -> confirm ->
 *   edit preserves history -> discontinue/reopen -> audit -> doctor denied.
 *
 * Requires the seeded demo accounts (patient@demo.health / doctor@demo.health).
 */

const BASE = process.argv[2] || 'http://localhost:4000';
const P = 'DemoPass123!';

let pass = 0; let fail = 0;
function check(name, cond, detail) {
  if (cond) { pass += 1; console.log(`  \u2713 ${name}`); }
  else { fail += 1; console.log(`  \u2717 ${name}${detail ? ` -- ${detail}` : ''}`); }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function api(path, { method = 'GET', token, body } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  let payload = body;
  if (body && !(body instanceof FormData)) { headers['Content-Type'] = 'application/json'; payload = JSON.stringify(body); }
  let res;
  for (let attempt = 0; attempt < 6; attempt++) {
    res = await fetch(`${BASE}${path}`, { method, headers, body: payload });
    if (res.status !== 429) break;
    await sleep(2000 * (attempt + 1));
  }
  const text = await res.text();
  let json; try { json = JSON.parse(text); } catch { json = { raw: text }; }
  return { status: res.status, json };
}

/** Build a minimal real PDF with a text layer (no external deps). */
function tinyPdf(lines) {
  const esc = (s) => s.replace(/([()\\])/g, '\\$1');
  const content = `BT /F1 12 Tf 50 760 Td 16 TL ${lines.map((l) => `(${esc(l)}) Tj T*`).join(' ')} ET`;
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  let pdf = '%PDF-1.4\n';
  const offsets = [];
  objs.forEach((o, i) => { offsets.push(pdf.length); pdf += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  const xrefStart = pdf.length;
  pdf += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n`;
  offsets.forEach((off) => { pdf += `${String(off).padStart(10, '0')} 00000 n \n`; });
  pdf += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${xrefStart}\n%%EOF`;
  return Buffer.from(pdf, 'latin1');
}

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

(async () => {
  console.log(`\nE2E medication reminders against ${BASE}\n`);

  const health = await api('/api/meta/health');
  check('API health is ok', health.json?.data?.status === 'ok');

  const login = await api('/api/auth/login', { method: 'POST', body: { email: 'patient@demo.health', password: P } });
  const pt = login.json?.data?.accessToken;
  check('patient can sign in', Boolean(pt));
  if (!pt) { console.log('Cannot continue without a patient token.'); process.exit(1); }

  // A doctor token is used later to prove schedules are patient-only.
  const dLogin = await api('/api/auth/login', { method: 'POST', body: { email: 'doctor@demo.health', password: P } });
  const dt = dLogin.json?.data?.accessToken;

  // 1. Manual schedule creation (idempotent via clientRequestId).
  const clientRequestId = `e2e-${Date.now()}`;
  const scheduleBody = {
    name: 'E2E Metformin',
    strength: '500 mg',
    doseInstructions: '1 tablet',
    route: 'oral',
    frequency: 'twice_daily',
    reminderTimes: ['08:00', '20:00'],
    startDate: todayIso(),
    timezone: 'UTC',
    clientRequestId,
  };
  const created = await api('/api/medications', { method: 'POST', token: pt, body: scheduleBody });
  check('creates a medication schedule', created.status === 201 && created.json?.data?.schedule?.name === 'E2E Metformin', `status=${created.status}`);
  const scheduleId = created.json?.data?.schedule?.id;
  check('generates dose occurrences', (created.json?.data?.dosesCreated || 0) >= 1);

  const replay = await api('/api/medications', { method: 'POST', token: pt, body: scheduleBody });
  check('idempotent replay returns the same schedule', replay.json?.data?.idempotent === true && String(replay.json?.data?.schedule?.id) === String(scheduleId));

  const dup = await api('/api/medications', { method: 'POST', token: pt, body: { ...scheduleBody, clientRequestId: undefined } });
  check('duplicate schedule is rejected', dup.status === 409);

  // 2. Reads: today + upcoming.
  const today = await api('/api/medications/doses/today?tz=UTC', { token: pt });
  check('today returns dose occurrences', today.status === 200 && Array.isArray(today.json?.data?.items));
  const upcoming = await api('/api/medications/doses/upcoming?limit=5', { token: pt });
  check('upcoming returns future doses', upcoming.status === 200 && Array.isArray(upcoming.json?.data?.items));

  // 3. Dose tracking: Taken, idempotent replay, conflicting change rejected.
  let doseId = (today.json?.data?.items || [])[0]?.id;
  if (!doseId) doseId = (upcoming.json?.data?.items || [])[0]?.id;
  check('a dose occurrence is available to act on', Boolean(doseId));
  if (doseId) {
    const taken = await api(`/api/medications/doses/${doseId}/action`, { method: 'POST', token: pt, body: { action: 'TAKEN' } });
    check('records a dose as Taken', taken.status === 200 && taken.json?.data?.dose?.status === 'TAKEN', `status=${taken.status}`);
    const again = await api(`/api/medications/doses/${doseId}/action`, { method: 'POST', token: pt, body: { action: 'TAKEN' } });
    check('repeating Taken is idempotent', again.json?.data?.idempotent === true);
    const flip = await api(`/api/medications/doses/${doseId}/action`, { method: 'POST', token: pt, body: { action: 'SKIPPED' } });
    check('a recorded dose cannot be flipped to Skipped', flip.status === 409);
  }

  // 4. History carries the "not proof" disclaimer.
  const history = await api('/api/medications/history?limit=20', { token: pt });
  check('history returns entries', history.status === 200 && Array.isArray(history.json?.data?.items));
  check('history explains what Missed means', /not proof/i.test(history.json?.data?.disclaimer || ''));

  // 5. Pause cancels future reminders; resume restores them.
  const paused = await api(`/api/medications/${scheduleId}/pause`, { method: 'POST', token: pt });
  check('pause sets status PAUSED', paused.json?.data?.schedule?.status === 'PAUSED');
  const upAfterPause = await api('/api/medications/doses/upcoming?limit=10', { token: pt });
  check('paused schedule has no upcoming doses', !(upAfterPause.json?.data?.items || []).some((d) => String(d.scheduleId) === String(scheduleId)));
  const resumed = await api(`/api/medications/${scheduleId}/resume`, { method: 'POST', token: pt });
  check('resume sets status ACTIVE', resumed.json?.data?.schedule?.status === 'ACTIVE');

  // 6. Edit: change reminder times, history preserved.
  const edited = await api(`/api/medications/${scheduleId}`, { method: 'PATCH', token: pt, body: { reminderTimes: ['09:30', '21:30'] } });
  check('edits reminder times', edited.status === 200 && edited.json?.data?.schedule?.reminderTimes?.includes('09:30'));
  const detail = await api(`/api/medications/${scheduleId}`, { token: pt });
  check('edited history is preserved', (detail.json?.data?.recentHistory || []).some((d) => d.status === 'TAKEN'));

  // 7. Prescription extraction: preview only, then explicit confirmation.
  const pdf = tinyPdf([
    'Riverside Family Clinic',
    'Prescription',
    `Date: ${todayIso()}`,
    'Rx',
    '1. Amlodipine 5 mg once daily',
    '2. Atorvastatin 20 mg at bedtime',
  ]);
  const fd = new FormData();
  fd.append('file', new Blob([pdf], { type: 'application/pdf' }), 'prescription-e2e.pdf');
  fd.append('category', 'prescription');
  const uploadRes = await fetch(`${BASE}/api/documents`, { method: 'POST', headers: { Authorization: `Bearer ${pt}` }, body: fd });
  const upload = await uploadRes.json();
  const documentId = upload?.data?.document?.id;
  check('uploads a prescription document', Boolean(documentId));

  const before = await api('/api/medications', { token: pt });
  const beforeTotal = before.json?.data?.total || 0;
  const extract = await api('/api/medications/extract', { method: 'POST', token: pt, body: { documentId } });
  check('extracts candidate medications', extract.status === 200 && (extract.json?.data?.candidates || []).length >= 1, `status=${extract.status}`);
  check('extraction flags uncertain fields', (extract.json?.data?.candidates || []).every((c) => Array.isArray(c.uncertainFields)));
  check('extraction carries a source snippet', (extract.json?.data?.candidates || []).some((c) => Boolean(c.sourceSnippet)));
  const afterExtract = await api('/api/medications', { token: pt });
  check('extraction creates no schedule before confirmation', (afterExtract.json?.data?.total || 0) === beforeTotal);

  const candidate = (extract.json?.data?.candidates || [])[0] || {};
  const unconfirmed = await api('/api/medications/confirm', { method: 'POST', token: pt, body: { documentId, medication: { name: candidate.name || 'Amlodipine', reminderTimes: ['09:00'], startDate: todayIso(), timezone: 'UTC' } } });
  check('confirmation is required', unconfirmed.status === 400);

  const confirmed = await api('/api/medications/confirm', {
    method: 'POST',
    token: pt,
    body: {
      documentId,
      confirmed: true,
      snippet: candidate.sourceSnippet || null,
      clientRequestId: `e2e-rx-${Date.now()}`,
      medication: {
        name: candidate.name || 'Amlodipine',
        strength: candidate.strength || '5 mg',
        frequency: 'once_daily',
        reminderTimes: ['09:00'],
        startDate: todayIso(),
        timezone: 'UTC',
      },
    },
  });
  check('confirmation creates a prescription schedule', confirmed.status === 201 && confirmed.json?.data?.schedule?.sourceType === 'PRESCRIPTION', `status=${confirmed.status}`);
  const rxId = confirmed.json?.data?.schedule?.id;
  if (rxId) {
    const rxDetail = await api(`/api/medications/${rxId}`, { token: pt });
    check('prescription schedule links to its source document', String(rxDetail.json?.data?.sourceDocument) === String(documentId));
  }

  // 8. Lifecycle: discontinue then reopen requires confirmation.
  const disc = await api(`/api/medications/${scheduleId}/discontinue`, { method: 'POST', token: pt });
  check('discontinue sets status DISCONTINUED', disc.json?.data?.schedule?.status === 'DISCONTINUED');
  const silent = await api(`/api/medications/${scheduleId}/resume`, { method: 'POST', token: pt, body: {} });
  check('reopening a discontinued schedule needs confirmation', silent.status === 409);
  const reopen = await api(`/api/medications/${scheduleId}/resume`, { method: 'POST', token: pt, body: { confirmReopen: true } });
  check('confirmed reopen reactivates', reopen.json?.data?.schedule?.status === 'ACTIVE');

  // 9. Ownership: doctors cannot read schedules even though they can view shared records.
  if (dt) {
    const doctorList = await api('/api/medications', { token: dt });
    check('doctor is forbidden from medication schedules', doctorList.status === 403);
  } else {
    check('doctor token available', false, 'doctor login failed');
  }
  const anon = await api('/api/medications/doses/today');
  check('anonymous access is rejected', anon.status === 401);

  // 10. Audit trail records medication actions.
  const audit = await api('/api/audit', { token: pt });
  const actions = (audit.json?.data?.items || []).map((a) => a.action);
  check('audit records schedule creation', actions.includes('medication.schedule_created'));
  check('audit records a dose action', actions.includes('medication.dose_taken'));
  check('audit records prescription confirmation', actions.includes('medication.confirmed_from_prescription'));

  console.log(`\nResult: ${pass} passed, ${fail} failed\n`);
  process.exit(fail ? 1 : 0);
})().catch((err) => { console.error('E2E error:', err); process.exit(1); });
