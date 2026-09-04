# ScamShield — DPDP Implementation Report

**Date:** 2026-09-04
**Prepared as:** the final deliverable of a repository-wide DPDP (India's Digital Personal Data Protection Act, 2023) technical audit and implementation pass.
**Companion documents:** `DPDP_AUDIT.md` (Phase 1 findings), `DPDP_COMPLIANCE.md` (implemented vs. outstanding), `THIRD_PARTY_DATA_PROCESSORS.md` (external data flows).

This report does not claim legal compliance. It records what was changed, why, how it was tested, and what remains open.

---

## 1. What was changed

### Backend (`server/main.py`) — active system
- Hardened the admin-key bootstrap: the CI/test fallback admin key can no longer be triggered by a stray `CI` env var on a real deployment — only an actual `pytest` import does, with a loud warning log.
- Added `AUDIT_LOG_RETENTION_DAYS` (opt-in, unset by default) and `cleanup_audit_logs()`, run at startup and on every admin audit-log view.
- Added `DELETE /api/audit-logs` (admin-only) for manual erasure of the audit log.
- Fixed `/scan-batch` to enforce the same 100 MB per-file cap as `/scan`, plus a new `MAX_BATCH_FILES` (20) cap — previously unbounded.
- Documented the previously-undocumented `GROQ_API_KEY` in `server/.env.example` and added the new `AUDIT_LOG_RETENTION_DAYS` var with an explanatory comment.
- Fixed a pre-existing broken test (`test_missing_admin_key_raises_error` used a `cwd` that only worked if pytest was invoked from the repo root — it now resolves relative to the test file itself, matching how the actual CI job and `cd server && pytest` both run it).

### Backend (`server/static/dashboard.html`)
- Removed the hardcoded fallback admin key and the practice of re-sending the admin key as a URL query parameter on every 5-second poll. The key is now only ever sent via the `X-Admin-Key` header; if present in the URL it's stripped from browser history immediately, and the dashboard prompts for a key if none was supplied.

### Flutter client (`lib/`) — new files
- `lib/services/consent_service.dart` — consent capture/versioning/withdrawal for the optional AI-processing consent.
- `lib/services/data_privacy_service.dart` — composes erasure (Delete My Data / Delete Account), report-file cleanup, and data export.
- `lib/services/data_change_notifier.dart` — a shared signal so IndexedStack-resident tabs (Home/History/Profile) refresh after a scan or a deletion made elsewhere.
- `lib/screens/consent_screen.dart`, `lib/screens/privacy_policy_screen.dart`, `lib/screens/privacy_settings_screen.dart`, `lib/screens/my_data_screen.dart` — the user-facing privacy UI.

### Flutter client — modified files
- `lib/main.dart` — wires the consent gate before login/home, and runs best-effort startup cleanup (stale temp reports, configured retention).
- `lib/data/database/database_helper.dart` — schema bumped to v2 with a real migration, adding `consent_version`, `consent_timestamp`, `ai_processing_enabled`.
- `lib/data/models/user_preferences.dart`, `lib/data/repositories/preferences_repository.dart` — support the new consent fields.
- `lib/data/repositories/scan_repository.dart` — cache is now shared across instances (see §2, "regression found and fixed"); mutating methods fire `DataChangeNotifier`.
- `lib/services/api_service.dart` — `analyzeMessage()` checks the AI-processing consent flag and skips the network call (falling back to the existing heuristic-fallback code path) when the user has turned it off.
- `lib/screens/profile_screen.dart` — adds a "Privacy & Data" entry; listens for `DataChangeNotifier` to keep its stats live.
- `lib/screens/home_screen.dart` — listens for `DataChangeNotifier` to keep its stats live.
- `lib/screens/history_screen.dart` — listens for `DataChangeNotifier` to keep the list live.
- `lib/screens/safe_vault_screen.dart` — adds bulk "Delete All Vault Items"; corrects UI copy that overclaimed "AES-256"/"Hardware Encrypted Storage" to accurately describe OS-keystore-backed storage.

### Infra / config
- `.gitignore` — added `*.db`, `*.sqlite`, `*.sqlite3` (the SQLite audit-log database was not previously excluded).
- `.github/workflows/ci.yml` — the backend job now also runs the new `server/test_dpdp_privacy.py` suite.
- `pubspec.yaml` — added `sqflite_common_ffi` as a dev dependency (enables real SQLite-backed tests without a device/emulator).
- `.claude/launch.json` — added a dev-server launch config used to smoke-test the app in this environment (Flutter web dev server; harmless to leave, not required for the app itself).

### Documentation
- `DPDP_AUDIT.md`, `DPDP_COMPLIANCE.md`, `THIRD_PARTY_DATA_PROCESSORS.md` (new — see those files for full content).

---

## 2. A regression found and fixed during this work (not in the original audit)

While live-verifying the "Delete My Data" flow, the History tab kept showing already-deleted records with no app restart — the deletion had genuinely succeeded in SQLite, but the UI didn't reflect it, which for a privacy-erasure feature is functionally equivalent to the deletion silently failing.

**Root cause:** `MainNavigation` (`lib/main.dart`) keeps every bottom-nav tab alive inside an `IndexedStack`, so `HistoryScreen`/`HomeScreen`/`ProfileScreen` only run `initState()` once, at app launch. Each screen also constructed its own `ScanRepository()`, and `ScanRepository` gave each instance a **private** in-memory cache — so a deletion made through one instance (e.g. Settings > Privacy & Data, a different repository instance than the History screen's) invalidated a cache the History screen never looked at again.

**Fix:**
1. `ScanRepository` now shares one cache across instances by default (`_sharedCache`), so any instance's write is visible to all of them.
2. `DataChangeNotifier` (new) is fired by every mutating `ScanRepository` method; `HistoryScreen`, `HomeScreen`, and `ProfileScreen` listen for it and reload.

**Verified:** a regression test (`test/data/privacy_repository_test.dart`, "a deletion made via one ScanRepository instance is visible from another") plus a live, on-device reproduction: scanned a message, confirmed it appeared in History, deleted it via Settings > Privacy & Data, and confirmed History updated to "0 records" **without restarting the app**.

---

## 3. Database changes

- `user_preferences` table (local SQLite, schema v2): added `consent_version TEXT`, `consent_timestamp TEXT`, `ai_processing_enabled INTEGER` via a real `ALTER TABLE` migration (`_onUpgrade`, `oldVersion < 2`) — existing installs upgrade in place, no data loss.
- No changes to `scan_records`.
- No new tables. No server-side database schema changes (`server_audit.db`'s `audit_logs` table is unchanged; only its lifecycle — retention/erasure — changed).

## 4. API changes

- New: `DELETE /api/audit-logs` (admin-only).
- Changed behavior (no signature change): `POST /scan-batch` now rejects >20 files (400) and skips any file over 100 MB with a `"skipped"` status instead of processing it unbounded.
- Changed behavior: `GET /api/audit-logs` and `GET /dashboard` now trigger retention cleanup as a side effect (no response shape change).

## 5. UI changes

- New screens: Consent gate, Privacy Policy, Privacy & Data (Settings hub), My Data.
- New entry point: Profile > "Privacy & Data".
- New action: Safe Vault > bulk delete (trash icon in the app bar, shown only when items exist).
- Corrected copy: Safe Vault banner no longer claims "AES-256"/"Hardware Encrypted Storage".

## 6. Privacy controls (summary — full detail in `DPDP_COMPLIANCE.md`)

Consent (essential + optional AI-processing, versioned, timestamped, no pre-selection), access/export (My Data), correction (pre-existing profile editing, unchanged), erasure (Delete My Data / Delete Account, plus existing scan/vault item deletion), retention (client-configurable scan-history auto-delete; server-configurable audit-log retention), and third-party documentation.

## 7. Security controls

- Preserved, unmodified: PBKDF2 password hashing, `flutter_secure_storage` usage, rate limiting, upload validation, CORS configuration, secret redaction in server logs.
- Hardened: admin-key bootstrap fallback (server), admin-key handling in the dashboard client, `/scan-batch` upload limits.
- No security functionality was removed.

## 8. Deletion mechanisms

`ScanRepository.deleteById/clearAll/deleteOlderThan`, `DataPrivacyService.deleteAllScanAndVaultData/deleteAccountAndAllData/deleteAllGeneratedReports`, Safe Vault bulk delete, server `DELETE /api/audit-logs`.

## 9. Retention mechanisms

Client: `autoDeleteDays` preference (default "Never"), enforced on selection and at every app startup. Server: `AUDIT_LOG_RETENTION_DAYS` (default unset = no automatic cleanup), enforced at startup and on admin log access.

## 10. Third-party data flows

See `THIRD_PARTY_DATA_PROCESSORS.md`. No new third-party integrations were added by this work; `ApiService.analyzeMessage()` gained a client-side ability to *skip* sending data to Groq/Gemini when the user disables AI-assisted analysis.

---

## 11. Tests executed — actual results

Run in this environment on 2026-09-04.

### Backend (Python / pytest)
```
cd server && python -m pytest test_server.py test_dpdp_privacy.py -q
```
**Result: 47 passed, 0 failed** (33 pre-existing in `test_server.py` + 14 new in `test_dpdp_privacy.py`). Verified from both `cwd=server` and `cwd=repo-root` invocation styles (matches, and fixes a mismatch in, the CI job's actual working directory).

New tests cover: admin-endpoint auth (header/bearer, missing/wrong key), audit-log erasure, retention cleanup (no-op when unconfigured, deletes only rows past the configured cutoff, ignores invalid config), secret redaction end-to-end through `/analyze` → `/api/audit-logs`, and `/scan-batch` count/size caps.

### Flutter (`flutter test`)
```
flutter test
```
**Result: 37 passed, 7 failed.** The 7 failures are **pre-existing and unrelated to this work**:
- `test/widget_test.dart` (1 failure) — the unmodified default Flutter-project counter-app template test; ScamShield has never had a counter UI, so this test could never have passed against this app.
- `test/apk_analyzer_test.dart` (6 failures) — references binary APK fixture files (`ScamShield_Test_APKs/*.apk`) that do not exist in this repository checkout.

Neither file was modified by this work. The new/relevant suites, run individually to confirm:
- `test/data/privacy_repository_test.dart` — **15 passed, 0 failed** (scan deletion, retention cleanup, consent-state handling, and the cross-instance-cache regression test).
- `test/data/clipboard_scan_test.dart`, `test/data/progress_service_test.dart`, `test/data/scam_detector_test.dart` — all pre-existing, all still passing (22 tests), confirming no regression in unrelated features.

### Static analysis
```
flutter analyze
```
**Result: 7 informational-level issues, 0 errors, 0 warnings.** 5 are pre-existing (unrelated files); 2 are new but match the exact same `use_build_context_synchronously` info-level pattern already present and tolerated elsewhere in the codebase (e.g. `profile_screen.dart:132`, pre-existing).

### Live, on-device verification
Performed on a real Android emulator (`sdk gphone64 arm64`, Android 16 / API 36) against the actual `server/main.py` backend running locally:
- Consent gate: checkbox starts unchecked, "I Agree & Continue" disabled until checked, enables once checked, grants consent and proceeds.
- Privacy & Data screen: renders correctly (Privacy Policy, Third-Party Data Sharing, AI-Assisted Analysis toggle, My Data, Data Retention chips, Delete My Data, Delete Account, Grievance placeholder).
- My Data export: tapped "Export My Data (JSON)"; pulled the actual file from the device (`/data/data/com.example.scamshield/cache/ScamShield_MyData_*.json`) and confirmed its contents (account email, profile, settings, consent record, scan history) — Safe Vault secret content confirmed absent, only titles/categories present per design.
- Delete My Data: performed a real text scan against the live backend (SCAM classification, risk score 69, heuristic-mode since no AI keys configured in this environment), confirmed it appeared in History, deleted via Settings > Privacy & Data, confirmed the confirmation dialog and success message, and confirmed History updated to zero records **live, without an app restart** (this is what surfaced and let us fix the cache regression in §2).
- Regression spot-check: Breach screen ("Data Breach Intelligence") and Scan screen (SMS/Text analysis, sample-message flow, result card rendering with risk factors) both confirmed still functioning end-to-end against the live backend.

**Not performed in this environment:** full manual pass of APK upload/scan, voice-note, and screenshot flows (these code paths were not modified by this work; APK/voice/screenshot regression relies on `flutter analyze` + the fact that no touched file is imported by those flows, rather than a fresh manual click-through). iOS/macOS builds could not be attempted (incomplete Xcode/CocoaPods installation in this environment) — this affects build verification only, not the correctness of the Dart source, which is platform-independent and covered by `flutter analyze` + `flutter test` regardless.

---

## 12. Remaining gaps (see `DPDP_COMPLIANCE.md` for full detail)

- `GET /api/v1/breach` still allows looking up any email, not just the caller's own — a product decision, not a bug, and intentionally not restricted without that decision.
- Server-side audit-log retention defaults to indefinite until an operator sets `AUDIT_LOG_RETENTION_DAYS`.
- No real Grievance Officer/contact is configured — placeholder only.
- Account email cannot be corrected/changed in-app.
- `backend/app/` (the dormant tree) still has no authentication and was not touched — resolving its fate remains an open, pre-existing item.

## 13. Items requiring legal review

Legal basis per processing activity, Data Fiduciary/Significant Data Fiduciary classification, Grievance Officer designation, cross-border transfer implications for each third-party processor, and whether the current (partially placeholder) Privacy Policy content meets the Act's notice requirements. None of these were resolved by this engineering work — see `DPDP_COMPLIANCE.md` for the full list.

## 14. Items requiring product decisions

Whether to restrict the breach-lookup endpoint to the caller's own email, what (if any) mandatory retention periods to set for scan history and audit logs, whether full-name collection at registration is actually necessary, and the fate of `backend/app/`.

---

*No claim of "100% DPDP compliant" is made anywhere in this deliverable, per the constraints of this task. Everything above is either a verified technical change with test evidence, or explicitly marked as outstanding.*
