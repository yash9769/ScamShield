# ScamShield — DPDP (India Digital Personal Data Protection Act, 2023) Audit

**Date:** 2026-09-03
**Scope:** Full repository — Flutter client (`lib/`), live backend (`server/`), dormant backend (`backend/app/`), infra/CI/Docker, docs.
**Method:** Static code review only (no runtime testing in this phase). Every claim below is cited `file:line`. Nothing was guessed; unresolvable questions are marked `UNKNOWN - REQUIRES PRODUCT/LEGAL DECISION`.
**Non-goal:** This document is a technical audit, not a legal opinion. It does not determine ScamShield's status as a "Data Fiduciary"/"Significant Data Fiduciary" under the Act, nor does it establish a lawful basis for any specific processing activity — those are legal/product calls, flagged accordingly.

This audit does not modify application code. See [DPDP_COMPLIANCE.md](DPDP_COMPLIANCE.md) for what was subsequently implemented.

---

## 0. System shape (needed to read everything below)

ScamShield ships **two parallel backends**:

- **`server/main.py`** — the backend the Flutter client actually calls (port 8000). SQLite-based, no user accounts, no Postgres/Redis. **This is the live processing path** and the primary subject of this audit.
- **`backend/app/`** — a more sophisticated, unfinished FastAPI app (Postgres/Redis/MobSF/JWT-less) that **nothing imports or starts**. Confirmed dead: not referenced by `server/` or `lib/` (only two aspirational Dart comments mention it — `lib/services/osint_service.dart:39-40`, `lib/services/file_scanner_service.dart:155-156`), not built/tested by the only workflow GitHub actually runs (`.github/workflows/ci.yml`), and one of its own route files (`backend/app/routes/scan_endpoints.py`) has zero imports and cannot be imported. It is audited here (§7) because dead code still ships in the repo, models real personal-data schemas, and is a live risk if ever resurrected — but it is **not currently processing any user's data**.
- **Client accounts are fully local.** `lib/services/auth_service.dart` has no network calls at all — there is no server-side account system. "Login" creates a PBKDF2-hashed credential pair in on-device `flutter_secure_storage`.

---

## 1–2. Personal data collected and processed

| # | Data type | Collected where | Processed how |
|---|---|---|---|
| 1 | Email + password (device account) | Register/login screens (`lib/screens/register_screen.dart:27-63`, `login_screen.dart:31-58`) | PBKDF2-HMAC-SHA256, 120k iterations, random salt, stored in `flutter_secure_storage` (`auth_service.dart:33-39,61-79`). Never leaves device. |
| 2 | Full name | Register screen (`register_screen.dart:15,28,56`) | Written to plaintext `SharedPreferences` via `UserProfileService`, decoupled from the auth record (`user_profile_service.dart:8,30-61`) |
| 3 | Profile title/avatar | Profile screen edit dialog (`profile_screen.dart:37-129`) | Plaintext `SharedPreferences` (`user_profile_service.dart:9-10`) |
| 4 | Free-text scanned message/SMS content | Scan screen, clipboard auto-read (`main.dart:82-121`) | Sent to `POST /analyze` (`api_service.dart:21-27`) → forwarded to **Groq** and/or **Gemini** LLM (`server/main.py:308-378`); stored (first 100 chars, secret-redacted) in local SQLite `scan_records.input_text` and server-side `audit_logs.target` |
| 5 | Uploaded APK files | APK scan screen (`scanner_service.dart:19-33`) | Full binary sent to `POST /scan`; server writes to a temp file, statically analyzes (Androguard/YARA/VirusTotal/Safe Browsing), deletes temp file in `finally` (`server/main.py:965,977-981`); result cached **in server RAM only** keyed by SHA-256 (`main.py:690-857`); client also generates a **PDF report saved permanently on-device** (`report_generator_service.dart`, see §6) |
| 6 | Screenshots | File/image picker (`file_scanner_service.dart`) | **Not actually uploaded** — only the filename string is analyzed locally; `/analyze-image` exists but is dead code in the shipped client (never called from any screen). Image bytes never leave the device today. |
| 7 | Voice notes | — | **Not wired to any UI.** `/analyze-voice` exists server-side but no screen in `lib/` calls `api_service.dart`'s `analyzeVoice()`. No transcription (Whisper) exists in `server/` at all — WAV metadata only, and the fallback path has a code bug that likely crashes non-WAV uploads (`server/main.py:909-914`, undefined `URL_REGEX`). |
| 8 | Email address (breach lookup) | Breach screen (`breach_screen.dart:102`) | Sent to `GET /api/v1/breach?email=` (`breach_service.dart:365-370`) → forwarded in URL query string to **XposedOrNot** third-party API (`server/main.py:1090-1175`), unauthenticated, no ownership check |
| 9 | Safe Vault secrets (PINs, passwords, notes) | Safe Vault screen (`safe_vault_screen.dart:8-38,116-198`) | JSON blob in `flutter_secure_storage`; UI claims "AES-256"/"Hardware Encrypted" but only OS-keystore-level protection exists — no additional app-layer crypto (`safe_vault_screen.dart:51,266,269` vs. implementation) |
| 10 | Device/app metadata for permission gating | `permission_service.dart:18-53` | Storage/photos/notification permission requested once; result flag cached locally. No contacts/location/camera/mic ever requested despite being declared in the Android manifest (unused-but-declared permissions) |
| 11 | IP address (implicit) | Every server request | Used only as the `slowapi` rate-limit key (`server/main.py:159`) — not persisted to `audit_logs` (schema has no IP column) |
| 12 | Third-party developer identity (APK signer name/org) | `/scan` response | Androguard certificate parsing surfaces the **APK signer's** (not the app user's) real name/org (`server/main.py:727-738`) — personal data of a third party, not the ScamShield user |

---

## 3–8. Data-flow table

| Data | Source | Purpose | Destination | Storage | Retention | Third Party | Deletion |
|---|---|---|---|---|---|---|---|
| Email + password hash | Register/login | Local account gate | On-device only | `flutter_secure_storage` | Indefinite | None | `AuthService.deleteAccount()` exists but **has zero UI entry point** — unreachable |
| Name, title, avatar | Register/profile edit | Personalize UI | On-device only | `SharedPreferences` (plaintext) | Indefinite | None | No delete/reset method exists anywhere |
| Scanned message text | Scan screen / clipboard | Scam classification | `server/` `/analyze` → Groq/Gemini | Local SQLite (`scan_records`) + server SQLite (`audit_logs`, 100-char excerpt) | Indefinite (no TTL, no cleanup job — confirmed via grep of `server/*.py` for `DELETE FROM`/`TTL`/`cleanup`/`VACUUM`: none) | Groq or Gemini (LLM inference), whichever is configured | Client-side: per-record and clear-all delete exist in History screen. Server-side `audit_logs` row: **no deletion mechanism at all** |
| APK file | APK scan screen | Malware/permission analysis | `server/` `/scan` → temp file → deleted | Temp file deleted same request; **generated PDF report persists indefinitely** in app-documents/temp dirs on-device, never cleaned up (`report_generator_service.dart`, no `.delete(` call anywhere for these paths) | Indefinite (PDF); server-side scan cache (in-RAM, cleared on restart) | VirusTotal (hash), Google Safe Browsing (extracted URLs) | No client UI deletes generated PDF reports. No server persistence to delete. |
| Email (breach lookup) | Breach screen | Show exposure | `server/` `/api/v1/breach` → XposedOrNot | Not stored server-side (no DB write for this route); not stored client-side either (result not written to scan history) | N/A (not persisted) | XposedOrNot | N/A — nothing to delete, but see §11 (no consent/ownership gate on the lookup itself) |
| Safe Vault content | Safe Vault screen | User-managed secret storage | On-device only | `flutter_secure_storage` | Indefinite | None | Per-item delete exists; no bulk-delete |
| Admin dashboard audit log rows | All requests | Operational visibility | `server/server_audit.db` | Indefinite, unbounded, `.db` file not `.gitignore`d | Not exposed to end users; readable by anyone holding `ADMIN_API_KEY` | None | No deletion mechanism (no endpoint, no TTL) |

---

## 9. Optional vs. necessary processing

| Processing | Necessary for stated purpose? | Notes |
|---|---|---|
| Sending scanned message text to Groq/Gemini | Yes, for AI-mode classification | Heuristic fallback exists and works without any network call — AI path is genuinely optional at the product level but the app does not currently expose a user toggle to force heuristic-only mode |
| Sending APK hash to VirusTotal | Yes, for reputation lookup | Already key-gated; degrades gracefully without a key |
| Sending extracted URLs to Google Safe Browsing | Yes, for URL reputation | Same as above |
| Email → XposedOrNot | Yes, that is the feature | **But**: the endpoint accepts and forwards *any* email, not just the caller's own — see §11 finding 1 |
| PDF report containing extracted secrets/OSINT results, retained indefinitely | **No** — retention is not required for the analysis to happen | This is scan output, not scan input; nothing about the classification task requires keeping the PDF after the user has viewed/exported it |
| Server-side `audit_logs` storing 100-char excerpts of user text indefinitely | `UNKNOWN - REQUIRES PRODUCT/LEGAL DECISION` — some audit trail may be operationally justified (abuse detection, debugging), but indefinite retention of message content excerpts is not self-evidently necessary |
| Full name collected at registration | `UNKNOWN - REQUIRES PRODUCT/LEGAL DECISION` — nothing in the app currently requires a real name (it is never verified, never shown to any third party, used only as a locally-editable display label) |

---

## 10. Is deletion currently possible?

| Data | Deletable today via product UI? |
|---|---|
| Single scan history record | **Yes** — swipe-to-delete (`history_screen.dart:246-249`) |
| All scan history | **Yes** — "Reset All Data" (`history_screen.dart:129-133,67-101`) |
| Single Safe Vault note | **Yes** — swipe-to-delete (`safe_vault_screen.dart:200-209`) |
| All Safe Vault notes | **No** — no bulk action |
| Account (email/password/session) | **No** — `AuthService.deleteAccount()` exists in code but is called from nowhere; only `logout()` (session-only) is wired to UI |
| Profile (name/title/avatar) | **No** — no reset/delete, only overwrite via edit |
| Generated PDF reports | **No** — no delete capability, no auto-cleanup |
| Server-side audit log entries | **No** — no endpoint, no admin action, no TTL |

## 11. Access / correction / consent

- **Access:** No "my data" / export screen exists anywhere in `lib/`.
- **Correction:** Profile name/title/avatar can be edited (overwritten) — this is the only correction path in the app. Email (auth) cannot be changed once registered (no UI).
- **Consent:** A `has_consented` column exists in the local `user_preferences` SQLite table (`database_helper.dart:69-78`) and a `PreferencesRepository.setConsent()` method exists (`preferences_repository.dart:38-41`) — **but the entire class is dead code**, never instantiated or called anywhere in `lib/`. **There is no live consent flow, banner, or toggle shown to users today.** The app currently begins processing (clipboard auto-read, AI submission) with no consent gate of any kind.
- **Legal basis currently relied upon:** none is technically implemented (no consent capture, no documented "legitimate use" determination in code/config). `UNKNOWN - REQUIRES PRODUCT/LEGAL DECISION` on which basis under the DPDP Act (consent vs. a "legitimate use" exemption, e.g. voluntary disclosure for a specified purpose) the business intends to rely on for each processing activity above.

---

## 12. Security controls currently implemented

- PBKDF2-HMAC-SHA256 (120k iterations, random salt) for on-device password hashing; credentials in OS-backed secure storage, not plaintext.
- Rate limiting (`slowapi`) on most user-facing routes (60/min text, 20/min voice/image, 10/min scan, 30/min breach) — **but not on `/`, `/health`, `/dashboard`, `/api/audit-logs`, `/stats`**.
- Upload validation on `/scan`: extension check, ZIP-magic check, 100MB cap, zip-bomb mitigation (entry count/size caps) — **`/scan-batch` has no size cap and no per-batch limit at all** (`server/main.py:1043-1064` vs. `961-962`).
- Admin endpoints gated by a bearer/`X-Admin-Key` header compared against `ADMIN_API_KEY` (non-constant-time `!=` comparison, `server/main.py:61`).
- Audit-log write path redacts common secret patterns (API keys, bearer tokens) before insertion (`server/main.py:97-108`).
- CORS: `allow_credentials=False`; origins configurable via `ALLOWED_ORIGINS` but **default to `*`** in both code and `.env.example`.
- No hardcoded live secrets found in `lib/` (prior audit's C3 finding — hardcoded OSINT keys — was already resolved).

## 13. Missing controls (technical gaps, not yet legal/product)

1. No consent mechanism live anywhere in the shipped app.
2. No account-deletion UI (server method exists, unreachable).
3. No retention policy or automatic cleanup for: server `audit_logs`, client-generated PDF reports, local scan history (repository has a `deleteOlderThan()` method, also dead/unwired).
4. No privacy notice/policy screen in the app.
5. `GET /api/v1/breach` performs no ownership/consent check on the queried email — see §14 finding 1.
6. `server_audit.db` is not `.gitignore`d.
7. `ADMIN_API_KEY` silently falls back to a hardcoded string (`scamshield_admin_sec_key_2026`) when `CI`/`PYTEST_CURRENT_TEST` env vars are present (`server/main.py:40-45`) — the **same** hardcoded string is the client-side dashboard fallback (`server/static/dashboard.html:179`).
8. Dashboard still sends the admin key as a URL query parameter on every poll (`server/static/dashboard.html:178-188`) despite `QA/SCAMSHIELD-SECURITY-FINDINGS.md` claiming query-string credentials are disabled — the *server* ignores `?key=`, but the *client* still leaks it into browser history / proxy logs.
9. `/analyze-voice`'s error-fallback path references an undefined name (`URL_REGEX`, `server/main.py:910`) and will raise uncaught on non-WAV uploads — a reliability bug, not directly a privacy one, but it means failed requests bypass audit logging entirely.
10. Cleartext HTTP allowed by default (`android:usesCleartextTraffic="true"`, confirmed in the client audit) — production builds must override the backend URL to HTTPS explicitly or personal data (including the user's own email in breach lookups) transits unencrypted.
11. Safe Vault UI claims stronger encryption ("AES-256", "Hardware Encrypted Storage") than what's implemented (OS-keystore-backed `flutter_secure_storage` only) — a claims-vs-implementation gap that is itself a compliance/consumer-protection risk independent of DPDP.

## 14. High-risk privacy issues (ranked)

1. **CRITICAL — Unauthenticated third-party-email breach lookup.** `GET /api/v1/breach` / `/breach` (`server/main.py:1090-1175`) lets any caller query breach-exposure data for *any* email address, not necessarily their own, with only IP-based rate limiting. This returns another person's personal data (breach names, exposed data classes, dates) to an unrelated requester with no consent or ownership check — the clearest DPDP-relevant exposure in the live system.
2. **HIGH — No functioning account-deletion / right-to-erasure path.** `AuthService.deleteAccount()` exists but has no caller; users cannot self-serve delete their account, and no data (profile, vault, scan history) is bundled into a single erasure action.
3. **HIGH — No consent capture despite a consent-flag schema already present** (dead code) — the app processes personal data (clipboard auto-scan, AI submission of message text) from first launch with no gate.
4. **MEDIUM — Indefinite server-side retention of message-text excerpts and filenames** in `audit_logs` with no TTL, no cleanup job, and readable by anyone holding the admin key (itself has a hardcoded CI/pytest fallback).
5. **MEDIUM — Generated PDF audit reports (containing extracted secrets, OSINT/cert data) persist indefinitely on-device** with no delete UI or auto-cleanup — worse for the app-documents-directory copy, which is outside normal OS cache eviction.
6. **MEDIUM — Hardcoded admin-key fallback** shared between server startup guard and dashboard client (`scamshield_admin_sec_key_2026`) creates a latent bypass if `CI`/`PYTEST_CURRENT_TEST` env vars leak into a real deployment.
7. **LOW/HOUSEKEEPING — `test/test.py:3`** contains a string formatted as a live Anthropic API key with no placeholder markers (unlike every other test fixture in the repo, which uses obvious dummy values). Requires manual confirmation of whether this key is real/live and rotation if so — **cannot be verified from static review alone.**
8. **LOW — `backend/docker/docker-compose.yml`** (dead tree) bakes in a default Postgres password (`scamshield_password`) and MobSF API key (`mobsf_api_key_123`) directly into a committed file, and stands up an unauthenticated Redis instance if ever run as-is.
9. **LOW — Dead `backend/app/` has zero authentication** on any route (`GET /history`, `GET /scan/{id}`, etc. — no ownership filter), a materially different and weaker posture than the live stack. Only a latent risk while dead, but a real one if ever resurrected without first adding auth.

## 15. Technical changes required (superset — see DPDP_COMPLIANCE.md for what was implemented)

1. Privacy notice screen (in-app).
2. Consent-management service wired to real UI, replacing the dead `PreferencesRepository`/`has_consented` scaffold.
3. Working "Delete My Account" flow wired to `AuthService.deleteAccount()` (extended to also purge profile, scan history, vault).
4. Bulk "Delete all Safe Vault items."
5. Retention/cleanup: local scan history age-based purge (wire up the existing `deleteOlderThan()`), generated PDF cleanup, server-side `audit_logs` TTL/cleanup job.
6. Ownership/consent gate — or at minimum explicit rate-limit tightening and logging — on `GET /api/v1/breach` given it's a third-party-data lookup, plus a decision on whether it should require the caller to prove ownership of the email (e.g. app already collected the user's own email at registration — restrict the endpoint to that email unless a legal basis for arbitrary lookups is documented).
7. Fix hardcoded admin-key fallback; require `ADMIN_API_KEY` unconditionally, or use a distinct, clearly-non-production test key that is refused if the app is reachable on a non-loopback interface.
8. `.gitignore` the SQLite DB files that hold personal data.
9. `THIRD_PARTY_DATA_PROCESSORS.md` documenting every external processor.
10. `/scan-batch` size/count caps to match `/scan`.
11. Fix or remove the dead `/analyze-voice`/`/analyze-image` client paths, or correct the `URL_REGEX` bug if voice/image scanning is to be completed.
12. Correct the Safe Vault UI copy to match actual protection level, or implement the claimed app-layer AES-256 encryption.

---

## Data types marked UNKNOWN

- Whether "full name" collection at registration is product-required — `UNKNOWN - REQUIRES PRODUCT/LEGAL DECISION`.
- Legal basis (consent vs. legitimate-use exemption) per processing activity — `UNKNOWN - REQUIRES PRODUCT/LEGAL DECISION`.
- Retention period for server-side audit logs, local scan history, and generated reports — no period is currently defined anywhere in code or docs; **no period is invented in this audit or its implementation** (see DPDP_COMPLIANCE.md).
- Whether `GET /api/v1/breach` is intended to support looking up emails other than the caller's own (e.g. a "check if this contact's email leaked" use case) — `UNKNOWN - REQUIRES PRODUCT/LEGAL DECISION`; the technical fix implemented is documentation + logging tightening only, not a hard restriction, pending this decision.
- Whether ScamShield intends to operate as a Data Fiduciary under the Act, and whether any processing here would classify it as a Significant Data Fiduciary — `UNKNOWN - REQUIRES LEGAL DECISION`.
- Whether `test/test.py:3`'s API-key-shaped string is a live credential — `UNKNOWN - REQUIRES PRODUCT DECISION` (verify and rotate if live; this audit only flags the pattern).
