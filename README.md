# AI-Powered Personal Health Wallet

A full-stack health-record wallet: patients upload documents (PDF/image/text), OCR + AI
extract structured records, they review/verify them, and they share exactly chosen records
with verified doctors via a registered-doctor grant or a QR/secure link. Doctors see only
the consented scope; everything is re-validated server-side on every request. Patients can
also turn a prescription into medication reminders they confirm themselves.

## Stack

| Layer    | Tech |
|----------|------|
| Frontend | Flutter (Material 3, GoRouter, Riverpod, Dio, flutter_secure_storage, qr_flutter, fl_chart) |
| Backend  | Node.js + Express |
| Database | MongoDB + Mongoose |
| Auth     | Short-lived JWT access tokens + rotating refresh tokens (hashed, stored server-side) |
| OCR/AI   | tesseract.js (WASM, offline) + pdfjs-dist; local RAG by default, optional OpenAI/Anthropic |

## Quick start

### 1. Backend

```bash
cd backend
cp .env.example .env          # adjust secrets/origins
npm install
npm run seed:reset            # fictional demo data (safe reset)
npm run dev                   # http://localhost:4000
```

### 2. Frontend

```bash
cd frontend
flutter pub get
flutter run -d chrome         # or: flutter build web --release
```

### Demo accounts (seeded, fictional)

| Role    | Email               | Password      |
|---------|---------------------|---------------|
| Patient | patient@demo.health | DemoPass123!  |
| Doctor  | doctor@demo.health   | DemoPass123!  |
| Doctor  | doctor2@demo.health  | DemoPass123!  |

## Acceptance workflow

1. **Import** — upload a PDF/image/text document (multi-page, poor-quality and duplicate handling).
2. **Extract** — OCR (tesseract.js WASM) or PDF text extraction produces schema-validated records.
3. **Review & verify** — correct any field, verify or reject each record; manual entry also supported.
4. **Medication reminders** — add a medicine manually or extract candidates from a
   prescription, review/confirm every field, then mark each dose taken or skipped.
5. **Grounded AI** — answers cite the source document; says "not in your records" when missing.
6. **Safety** — medication-interaction and duplicate-test detection from a validated dataset.
7. **Share** — pick records, set expiry, generate QR + secret token, or nominate a verified doctor.
8. **Doctor view** — doctor authenticates, claims the token, sees only the consented scope.
9. **Revoke** — patient revokes; the doctor is denied immediately, even with the original QR.

## Tests

```bash
cd backend && npm test        # 84 unit tests (node --test, sequential); 83 pass, 1 env-only
cd backend && node scripts/e2e.js              # 43 end-to-end acceptance checks (42 pass; 1 AI-provider flake)
cd backend && node scripts/e2e-medications.js  # 35 medication-reminder checks (35 pass)
cd frontend && flutter test    # 56 Dart unit + widget tests
cd frontend && flutter analyze # clean
```

> The one backend unit failure is environmental: `tests/seed.test.js` asserts that
> `OPENAI_API_KEY` is unset in the test shell, but the developer environment exports one.
> The one E2E failure (`doctor AI includes citations`) is an AI-model response-shape flake
> on the doctor scoped-answer path, unrelated to the medication feature.

## Medication reminders

- **Manual entry** with local validation (name, schedule times, start/end date) and a
  confirmation summary before anything is saved.
- **Prescription extraction** reads candidate medicines from a prescription document and
  shows each with a source snippet, a confidence score and the exact fields it could not
  read. Candidates are **never** auto-saved: the patient edits and explicitly confirms each
  one, which links the new schedule back to its source document.
- **Scheduling** stores wall-clock `HH:mm` times plus a timezone; the server generates dose
  occurrences on a rolling horizon with a unique `(schedule, scheduledFor)` index, so
  repeated syncs never duplicate doses.
- **Tracking** records only `Taken`/`Skipped`. `Missed` is derived **server-side** after a
  configurable tracking window (never by a mobile timer) and is labelled as "not proof" of
  non-adherence.
- **Ownership** is strict: every `/api/medications` route is patient-only and always uses
  the authenticated patient id. Doctors do **not** gain access by viewing shared records.

**Notification platform limit (honest):** the client is a Flutter **web** app with no native
platform folders. On web, reminders use the browser Notification API plus in-page timers, so
a reminder fires only **while the app tab is open** — it cannot wake a closed browser or a
locked phone. OS-level scheduled notifications are not implemented; the `ReminderScheduler`
interface is a seam where a native implementation can be dropped in.

## Security notes

- The backend never trusts a client-supplied role; login returns the account's real role.
- Self-registered doctors are `unverified` and cannot access patient records until approved
  (dev-only `POST /api/doctor/verify` gated by `DOCTOR_VERIFY_KEY`; disabled in production).
- Share tokens are CSPRNG, stored only as SHA-256 hashes; the QR/link carries no medical data.
- Every share request re-checks status, expiry, max-accesses, doctor binding and scope.
- Files are streamed behind per-request authorization; no public static directory.
- Audit events record creation, consent, views, denials, downloads and revocations.

See [IMPLEMENTATION_REPORT.md](IMPLEMENTATION_REPORT.md) for architecture, API reference and limitations.
