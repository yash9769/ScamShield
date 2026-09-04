# ScamShield — DPDP Compliance Status

**Date:** 2026-09-04
**Basis:** `DPDP_AUDIT.md` (Phase 1 findings) and the technical controls implemented afterward (Phase 2). This document does not, and cannot, claim legal certification. It states what was built, what was not, and what remains a product or legal decision.

**Do not read this as "ScamShield is DPDP compliant."** No qualified legal/compliance review has occurred. This is an engineering status report against the technical controls a DPDP-aligned product typically needs.

---

## Implemented

Each item below is a real, working, tested control — not a UI label.

| Control | Where | Evidence |
|---|---|---|
| In-app Privacy Policy | `lib/screens/privacy_policy_screen.dart` | Reachable from the consent gate and Settings > Privacy & Data; content matches actual data flows per `DPDP_AUDIT.md` |
| First-launch consent gate, no pre-selected consent | `lib/screens/consent_screen.dart`, `lib/services/consent_service.dart` | Checkbox starts unchecked; "I Agree & Continue" disabled until checked (verified live on an Android emulator, screenshots taken during implementation) |
| Consent record: version + timestamp | `lib/data/database/database_helper.dart` (schema v2: `consent_version`, `consent_timestamp`), `PreferencesRepository.grantConsent()` | Unit-tested: `test/data/privacy_repository_test.dart` ("grantConsent records version and a timestamp") |
| Re-prompt on policy version change | `ConsentService.hasGivenCurrentConsent()` compares stored `consentVersion` to `ConsentService.currentPolicyVersion` | Unit-tested: "consent for an old policy version does not satisfy the current one" |
| Separate, optional, severable consent for AI processing | `ConsentService.setAiProcessingEnabled()`, wired into `ApiService.analyzeMessage()` | Turning it off skips the network call to Groq/Gemini and falls back to the on-device heuristic engine; scanning still works. Unit-tested + verified live (toggle in Settings > Privacy & Data) |
| Right to access / data export | `lib/screens/my_data_screen.dart`, `DataPrivacyService.exportUserData()` | Verified live on-device: exported JSON pulled from the emulator and inspected — contains profile, settings, consent record, and scan-history metadata; Safe Vault **contents** deliberately excluded (titles/categories only) so export never writes secrets to plaintext |
| Delete My Data (erase scan history, Safe Vault, generated reports; keep account) | `PrivacySettingsScreen`, `DataPrivacyService.deleteAllScanAndVaultData()` | Verified live: performed a real scan, deleted via this flow, confirmed both the database and the UI reflect zero records with no app restart |
| Delete Account (full local erasure, password-confirmed) | `PrivacySettingsScreen._confirmDeleteAccount()`, `DataPrivacyService.deleteAccountAndAllData()` | Composes the above plus `AuthService.deleteAccount()`, profile/settings reset, and `PreferencesRepository.resetToDefaults()`; requires re-entering the account password before proceeding |
| Scan-history deletion (single, bulk, and now cross-screen-consistent) | `ScanRepository.deleteById/clearAll` (pre-existing, still present); cross-instance cache bug fixed (see below) | Unit + live-verified |
| Safe Vault bulk deletion | `lib/screens/safe_vault_screen.dart` `_deleteAllNotes()` | New — the pre-existing implementation only had per-item delete |
| Configurable local retention for scan history | `PrivacySettingsScreen` "Data Retention" chips (Never/30/90/180 days) → `PreferencesRepository.setAutoDelete()` + `ScanRepository.deleteOlderThan()`, applied both on selection and at every app startup | Unit-tested: `deleteOlderThan removes only records past the cutoff`. **Default is "Never"** — no period is silently imposed |
| Generated-report cleanup | `DataPrivacyService.deleteAllGeneratedReports()` (part of both erasure flows) + `cleanupStaleTempReports()` (best-effort startup cleanup of the OS temp copy only, 7-day age) | Closes a real gap found in the audit — PDFs were previously never deleted anywhere |
| Server-side audit-log retention (opt-in, admin-configurable) | `server/main.py` `AUDIT_LOG_RETENTION_DAYS` env var + `cleanup_audit_logs()`, run at startup and on every admin dashboard load | Tested: `server/test_dpdp_privacy.py` ("cleanup deletes rows older than configured retention", "cleanup is a no-op when retention not configured") |
| Server-side audit-log erasure (admin action) | `DELETE /api/audit-logs` | Tested: "delete_audit_logs empties the table" |
| Admin-endpoint authentication hardening | `server/main.py` — the pytest/CI fallback admin key can no longer be triggered by a stray `CI` env var on a real deployment; only an actual `pytest` import does | Tested: `test_missing_admin_key_raises_error` (fixed a pre-existing path bug in the same test so it actually runs under CI's working directory) |
| Admin key no longer leaked via dashboard URL/query string | `server/static/dashboard.html` | Key is now only ever sent as an `X-Admin-Key` header; a `?key=` in the URL is stripped from browser history immediately and never re-added to a request URL |
| `/scan-batch` size and count caps | `server/main.py` — per-file `MAX_APK_SIZE` check + new `MAX_BATCH_FILES` cap | Tested: "scan_batch rejects too many files", "scan_batch skips oversized file without crashing" |
| Local data stores excluded from version control | `.gitignore` (`*.db`, `*.sqlite`, `*.sqlite3`) | New — `server_audit.db` (containing message excerpts) was previously not gitignored |
| Cross-screen data-deletion consistency bug fixed | `lib/data/repositories/scan_repository.dart` (shared cache) + `lib/services/data_change_notifier.dart` (Home/History/Profile refresh signal) | **Found during live verification of this work, not by the original audit.** `MainNavigation` keeps every tab alive in an `IndexedStack`; without this fix, "Delete My Data" would genuinely delete the database but the History/Home/Profile tabs would keep showing the old data until the app restarted — indistinguishable from the deletion silently failing. Regression-tested: `test/data/privacy_repository_test.dart` "a deletion made via one ScanRepository instance is visible from another"; verified live end-to-end on an Android emulator with no app restart |
| Safe Vault UI claims corrected to match implementation | `lib/screens/safe_vault_screen.dart` | Previously claimed "AES-256"/"Hardware Encrypted Storage"; corrected to describe the actual mechanism (OS keystore via `flutter_secure_storage`) — a claims-vs-implementation gap the audit flagged |
| Documented (previously undocumented) Groq env var | `server/.env.example` | Groq is the *primary* AI provider in code but was absent from the example env file |

---

## Partially Implemented

| Control | What exists | What's missing |
|---|---|---|
| Data minimisation on `/api/v1/breach` (email lookup) | Rate-limited (30/min), email not persisted server-side, response schema unchanged | No ownership/consent gate — any caller can look up any email, not just their own. Fixing this requires a product decision (see below); no technical restriction was added because the intended behavior is ambiguous |
| Server-side audit-log data minimisation | Secret-pattern redaction (pre-existing), retention now configurable and erasable | The 100-character message excerpt is still stored by default when `AUDIT_LOG_RETENTION_DAYS` is unset — indefinite retention remains the default until an operator configures a period |
| Correction (right to rectify) | Profile name/title/avatar are editable (pre-existing); account email is not editable anywhere in the UI | No path to correct the registered email without deleting and re-registering the account |
| Grievance/contact mechanism | A "Grievance / Contact" section exists in Settings > Privacy & Data and is referenced in the Privacy Policy | Both currently show a placeholder — no real contact/Grievance Officer has been designated by the business |
| `/analyze-voice` / `/analyze-image` privacy posture | Neither is reachable from the shipped client (screenshots/voice notes are not currently uploaded) | If either is completed as a real feature, it will newly send image/audio-derived content to Groq/Gemini and this document, the Privacy Policy screen, and `THIRD_PARTY_DATA_PROCESSORS.md` must be updated *before* release — not after |

---

## Requires Product Decision

1. **Should `GET /api/v1/breach` allow looking up *any* email, or only the caller's own?** The feature has a legitimate "check if this contact leaked" use case, but as-built it is also a general-purpose email-breach oracle with no consent step. A restriction (e.g., requiring the caller's own registered email, or adding an explicit "I'm checking someone else's email with their knowledge" acknowledgment) needs a product owner's call — not decided or implemented here.
2. **What should the default/mandatory scan-history retention period be?** Currently "Never" (user-configurable), matching the pre-existing behavior. No period is invented by this work.
3. **What should the server-side audit-log retention period be?** Currently unset (no auto-cleanup) unless an operator configures `AUDIT_LOG_RETENTION_DAYS`. No period is invented by this work.
4. **Is collecting a full name at registration actually necessary?** It is never verified or shown to any third party today — kept as-is (removing a field is a larger, separately-reviewable UX change), but flagged as a data-minimisation candidate.
5. **Fate of `backend/app/`.** Still open from the original `CODEBASE_AUDIT.md`. It has no authentication at all and a materially larger third-party footprint (see `THIRD_PARTY_DATA_PROCESSORS.md`); if resurrected, it needs its own DPDP pass before deployment.

## Requires Legal Review

1. **Legal basis for each processing activity.** This work implements consent capture as the technical mechanism, but whether consent (vs. a "legitimate use" exemption under the Act) is the intended basis for each specific processing activity is a legal determination, not a code change.
2. **Whether ScamShield is a Data Fiduciary, and whether it meets any Significant Data Fiduciary threshold**, given the scale/sensitivity of processing (breach lookups, APK/message analysis). Not determinable from code.
3. **Grievance Officer designation and grievance-redressal SLA**, required content under the Act — currently a placeholder in-app.
4. **Cross-border data transfer implications** of sending data to Groq, Gemini, VirusTotal, Google Safe Browsing, AbuseIPDB, and XposedOrNot — see the `VERIFY` markers in `THIRD_PARTY_DATA_PROCESSORS.md`; none of those vendor terms were reviewed as part of this engineering work.
5. **Whether the current Privacy Policy content (placeholders included) is sufficient for the Act's notice requirements**, or needs counsel drafting before production release.
6. **`test/test.py:3`** contains a string formatted as a live Anthropic API key with no placeholder marker, unlike every other test fixture in the repo. This was **not modified** by this work (out of scope for a privacy/security engineering pass to silently rewrite what might be evidence of a real incident) — it needs manual confirmation and, if live, rotation, by whoever has context on that file.

---

## Technical Evidence

- **Services:** `lib/services/consent_service.dart`, `lib/services/data_privacy_service.dart`, `lib/services/data_change_notifier.dart`
- **Screens:** `lib/screens/consent_screen.dart`, `lib/screens/privacy_policy_screen.dart`, `lib/screens/privacy_settings_screen.dart`, `lib/screens/my_data_screen.dart`
- **Database:** `lib/data/database/database_helper.dart` schema v2 (`consent_version`, `consent_timestamp`, `ai_processing_enabled` columns, with a real `ALTER TABLE` migration path from v1)
- **APIs (server):** `DELETE /api/audit-logs` (new), `AUDIT_LOG_RETENTION_DAYS` behavior, `/scan-batch` caps — all in `server/main.py`
- **Tests:**
  - `server/test_dpdp_privacy.py` — 14 tests, all passing (admin auth, erasure, retention cleanup, redaction, batch caps)
  - `server/test_server.py` — 33 pre-existing tests, all still passing (regression check; includes a fix to a pre-existing broken-path test, `test_missing_admin_key_raises_error`)
  - `test/data/privacy_repository_test.dart` — 15 tests, all passing (scan deletion, retention cleanup, consent state, the cross-instance cache regression)
  - Full existing Flutter suite re-run: `test/data/clipboard_scan_test.dart`, `test/data/progress_service_test.dart`, `test/data/scam_detector_test.dart` — all still passing (37 total across these + the new file)
  - Two **pre-existing** failures (`test/widget_test.dart` — an unmodified default Flutter counter template with no relation to this app's UI; `test/apk_analyzer_test.dart` — missing binary APK fixture files) are unrelated to this work and were not introduced by it; not fixed, as they are out of scope for a privacy/security pass
- **Live verification:** performed on a real Android emulator (`emulator-5554`, Android 16/API 36) against the live `server/main.py` backend — consent gate, Privacy & Data screen, My Data export (file pulled and inspected on-device), Delete My Data (with before/after History-screen check, including the cross-instance cache bug found and fixed during this verification), and a live text scan through the actual backend
- **Deletion mechanisms:** `ScanRepository.clearHistory/deleteById/deleteOlderThan`, `DataPrivacyService.deleteAllScanAndVaultData/deleteAccountAndAllData/deleteAllGeneratedReports`, server `DELETE /api/audit-logs`, `cleanup_audit_logs()`
- **Retention mechanisms:** client `autoDeleteDays` preference (applied at startup and on selection), server `AUDIT_LOG_RETENTION_DAYS` (applied at startup and on admin log view)
- **Security controls preserved/unmodified:** PBKDF2 password hashing, `flutter_secure_storage` usage, rate limiting, upload validation, CORS, secret redaction in logs — none of these were touched; only the admin-key fallback and dashboard query-string leak were hardened

## What was explicitly NOT claimed or fabricated

- No "DPDP Compliant" badge was added anywhere in the app.
- No retention period was invented where the audit found none defined.
- No legal basis determination was made in code or copy beyond capturing consent as a mechanism.
- Test counts and results above are the actual output of running the suites in this environment on 2026-09-04, not estimates.
