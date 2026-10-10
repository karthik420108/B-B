# Implementation Report — AI-Powered Personal Health Wallet

## 1. Architecture

```
frontend (Flutter web)                 backend (Express)                MongoDB
─────────────────────                  ──────────────────                ──────────
GoRouter ──role guards──►  REST  ──►  authenticate (JWT)        ──►  users
Riverpod providers                   requireRole / requireVerifiedDoctor  doctorProfiles
Dio ApiClient  (auto refresh)         validate (zod)                     documents
flutter_secure_storage (tokens)        shareService (per-request checks)  shareGrants
                                      auditService                       records / timelines
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

## 3. API endpoints

**Auth** — `POST /api/auth/register|login|refresh|logout|forgot-password|reset-password|change-password`, `GET /api/auth/me`

**Doctor** — `GET /api/doctor/directory` (no patient records exposed), `GET /api/doctor/shares`, `GET /api/doctor/shares/:id`, `POST /api/doctor/verify` (dev-only)

**Sharing (patient)** — `POST /api/shares`, `GET /api/shares/mine`, `GET /api/shares/:id`, `POST /api/shares/:id/revoke`, `GET /api/shares/:id/access-history`

**Sharing (token/link)** — `GET /api/share/:token/inspect`, `POST /api/share/:token/claim`, `GET /api/share/:token/bundle`, `GET /api/share/:token/documents/:docId/file`

**Records/Documents/AI** — `/api/documents/*`, `/api/records/*`, `/api/ai/*` (grounded RAG with citations)

## 4. Environment variables

See `backend/.env.example` (placeholders only). Key ones: `JWT_ACCESS_SECRET`,
`JWT_REFRESH_SECRET`, `MONGODB_URI`, `STORAGE_DRIVER=local`, `AI_PROVIDER=local`,
`AI_ALLOW_EXTERNAL_DATA_TRANSFER=false`, `DOCTOR_VERIFY_KEY` (dev verification workflow),
`RATE_LIMIT_MAX` / `SENSITIVE_RATE_LIMIT_MAX`, `MAX_UPLOAD_MB`.

## 5. Test results (actually executed)

| Suite | Command | Result |
|---|---|---|
| Backend unit | `npm test` (node --test, sequential) | **49/49 pass** |
| E2E acceptance | `node scripts/e2e.js` | **34/34 pass** |
| Flutter unit + widgets | `flutter test` | **23/23 pass** |
| Static analysis | `flutter analyze` | **0 issues** |
| Web build | `flutter build web --release` | **success** |

Coverage maps to the spec: registration/login, refresh rotation, logout revocation,
role-scoped routes, share creation/claim/bundle, scoping (doctor sees only shared docs),
cross-patient isolation, revocation immediacy, expiry re-validation, max-access limits,
audit events, unverified-doctor denial (new), dev verification workflow (new), login-time
verification status (new), Flutter loading/error/empty states.

## 6. Remaining limitations

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
