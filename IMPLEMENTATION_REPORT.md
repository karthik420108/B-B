# Implementation Report — AI-Powered Personal Health Wallet

## 1. Architecture

```
frontend (Flutter web)                 backend (Express)                MongoDB
─────────────────────                  ──────────────────                ──────────
GoRouter ──role guards──►  REST  ──►  authenticate (JWT)        ──►  users
Riverpod providers                   requireRole / requireVerifiedDoctor  doctorProfiles
Dio ApiClient  (auto refresh)         validate (zod)                     documents
flutter_secure_storage (tokens)        shareService (per-request checks)  shareGrants
                                      medicationService (schedules/doses) medicationSchedules
                                      auditService                       medicationDoses
                                      rate limiting (express-rate-limit)  auditEvents
```

- **Frontend is a thin client.** Route guards are UX only; every protected call is
  independently authorized on the server.
- **Two share surfaces, one enforcement core.** Patient-facing grant CRUD lives in
  `routes/shares.routes.js` (`/api/shares`); token resolution (inspect/claim/bundle/file)
  lives in `routes/share.routes.js` (`/api/share/...`). Both call the same
  `shareService.resolveAccess`, which re-validates status, expiry, max-accesses,
  doctor binding and document scope on every request.
- **Auth.** 15-minute JWT access tokens; refresh tokens are rotated (unique `jti`,
  server-side hash) and revoked on logout or reuse.
- **Doctor verification.** `DoctorProfile.verification.status` ∈ `unverified` (self-registration)
  | `development` (dev seed) | `verified` (approved). `requireVerifiedDoctor` middleware
  gates every doctor↔record route.

## 2. Feature → implementation map

| Spec requirement | Where implemented |
|---|---|
| Role-based login, role selector, mismatch message | `features/auth/login_screen.dart` (`_selectedRole`, mismatch snackbar, server-decided routing) |
| Registration (patient + doctor w/ license, clinic) | `features/auth/register_screen.dart`, `POST /api/auth/register` |
| Doctor verification status | `DoctorProfile.verification`, `requireVerifiedDoctor`, `POST /api/doctor/verify` (dev-key gated), `PendingVerificationScreen` |
| Patient dashboard + Share entry | `features/home/home_screen.dart` → `features/sharing/*` |
| Select records, preview, consent, confirm | `create_share_screen.dart` (multi-select, remove, consent statement, expiry, nominated doctor) |
| QR / secure link | `qr_flutter` in create-share sheet; token = CSPRNG, hash-only storage, no medical data in QR |
| Doctor dashboard | `doctor_home_screen.dart` (Shared With Me, token claim) + `doctor_bundle_screen.dart` (scoped summary, timeline, documents, meds, allergies, labs, alerts) |
| Revocation | `POST /api/shares/:id/revoke`; immediate denial; audited |
| Expiration | enforced per-request in `resolveAccess`; status flipped to `expired` |
| Access log + audit | `ShareGrant.accessLog` + `AuditEvent` collection; `GET /api/shares/:id/access-history`, `GET /api/audit` |
| Record download auth | `GET /api/share/:token/documents/:docId/file` — per-request scope check, `Cache-Control: private, no-store` |
| Medication reminders: manual entry | `features/reminders/add_medication_screen.dart` (validation + confirmation summary), `POST /api/medications` |
| Reminders: today / upcoming / list | `features/reminders/reminders_screen.dart`, `GET /api/medications/doses`, `/doses/upcoming`, `GET /api/medications` |
| Prescription → reminder (never auto-saved) | `features/reminders/prescription_extract_screen.dart`, `POST /api/medications/extract` then `/confirm` (`confirmed: true` required) |
| Dose tracking Taken/Skipped + server-derived Missed | `features/reminders/dose_tile.dart`, `POST /api/medications/doses/:id/action`; `medicationService.markMissed` |
| Reminder history (with "not proof" disclaimer) | `features/reminders/history_screen.dart`, `GET /api/medications/history` |
| Schedule lifecycle (pause/resume/stop/reopen) | `features/reminders/schedule_detail_screen.dart`, `POST /api/medications/:id/{pause,resume,discontinue}` |
| Notification scheduling (web) | `services/reminder_scheduler_web.dart` (browser Notification + in-page timers); no-op stub off web |

## 3. API endpoints

**Auth** — `POST /api/auth/register|login|refresh|logout|forgot-password|reset-password|change-password`, `GET /api/auth/me`

**Doctor** — `GET /api/doctor/directory` (no patient records exposed), `GET /api/doctor/shares`, `GET /api/doctor/shares/:id`, `POST /api/doctor/verify` (dev-only)

**Sharing (patient)** — `POST /api/shares`, `GET /api/shares/mine`, `GET /api/shares/:id`, `POST /api/shares/:id/revoke`, `GET /api/shares/:id/access-history`

**Sharing (token/link)** — `GET /api/share/:token/inspect`, `POST /api/share/:token/claim`, `GET /api/share/:token/bundle`, `GET /api/share/:token/documents/:docId/file`

**Records/Documents/AI** — `/api/documents/*`, `/api/records/*`, `/api/ai/*` (grounded RAG with citations)

**Medications (patient-only)** — `GET/POST /api/medications`, `GET/PATCH /api/medications/:id`, `POST /api/medications/:id/{pause,resume,discontinue}`, `GET /api/medications/doses`, `GET /api/medications/doses/today`, `GET /api/medications/doses/upcoming`, `POST /api/medications/doses/:id/action`, `GET /api/medications/history`, `POST /api/medications/extract`, `POST /api/medications/confirm`

The legacy `GET /api/records/timeline` endpoint is preserved (used by `scripts/e2e.js`
and `tests/clinical.test.js`) even though the frontend Timeline screen was replaced by the
Reminders tab.

## 4. Environment variables

See `backend/.env.example` (placeholders only). Key ones: `JWT_ACCESS_SECRET`,
`JWT_REFRESH_SECRET`, `MONGODB_URI`, `STORAGE_DRIVER=local`, `AI_PROVIDER=local`,
`AI_ALLOW_EXTERNAL_DATA_TRANSFER=false`, `DOCTOR_VERIFY_KEY` (dev verification workflow),
`RATE_LIMIT_MAX` / `SENSITIVE_RATE_LIMIT_MAX`, `MAX_UPLOAD_MB`.

## 5. Test results (actually executed)

| Suite | Command | Result |
|---|---|---|
| Backend unit | `npm test` (node --test, sequential) | **83/84 pass** (1 env-only: `OPENAI_API_KEY` set in the test shell) |
| Backend medications | `node --test tests/medications.test.js` | **19/19 pass** |
| E2E acceptance | `node scripts/e2e.js` | **42/43 pass** (1 AI-provider response-shape flake) |
| E2E medications | `node scripts/e2e-medications.js` | **35/35 pass** |
| Flutter unit + widgets | `flutter test` | **56/56 pass** |
| Static analysis | `flutter analyze` | **0 issues** |
| Web build | `flutter build web --release` | **success** |

Coverage maps to the spec: registration/login, refresh rotation, logout revocation,
role-scoped routes, share creation/claim/bundle, scoping (doctor sees only shared docs),
cross-patient isolation, revocation immediacy, expiry re-validation, max-access limits,
audit events, unverified-doctor denial, dev verification workflow, login-time verification
status, Flutter loading/error/empty states, and medication reminders (manual entry,
idempotent create, occurrence idempotency, patient ownership incl. doctor denial, Taken/
Skipped recording, server-derived Missed that never overwrites an action, timezone/DST
resolution, lifecycle, prescription extraction with explicit confirmation, and paginated
history with the "not proof" disclaimer).

## 6. Remaining limitations

- **Medication notifications are in-app only on web.** This project ships no native
  platform folders, so OS-level scheduled notifications are not implemented. The web
  scheduler delivers reminders via the browser Notification API and in-page timers, which
  only fire while the tab is open. The `ReminderScheduler` interface is the seam for a
  future native (Android/iOS) implementation.
- **AI never prescribes.** Prescription extraction produces *candidates only*; no schedule
  is created until the patient edits/confirms, and the extracted schedule keeps a link to
  its source document. The assistant cannot add, change or stop a medication.
- **Demo scale.** `interactions.json` and the seed dataset are fictional/hackathon-scale;
  not a clinical substitute. No real hospital/EHR integration.
- **Doctor verification workflow is dev-only.** Production requires a real credentialing
  provider; the endpoint is disabled when `NODE_ENV=production`.
- **Password reset** returns a token in non-production only (email adapter TBD).
- **Cloud AI** (OpenAI/Anthropic) is opt-in behind `AI_ALLOW_EXTERNAL_DATA_TRANSFER=true`;
  the default local provider works fully offline.
- **Revocation cannot erase data** already downloaded/photographed by the recipient —
  stated in the UI.
- Tests require MongoDB on `127.0.0.1:27017`; run backend suites sequentially
  (`--test-concurrency=1`) to avoid shared-state flake.
