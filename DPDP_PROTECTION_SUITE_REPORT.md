# ScamShield — DPDP Protection-Suite Implementation Report

**Date:** 2026-09-06
**Prepared as:** a follow-up DPDP (India's Digital Personal Data Protection Act, 2023) technical pass, covering eight features shipped after `DPDP_IMPLEMENTATION_REPORT.md` (2026-09-04): scam call screening, FCM push notifications, a learning leaderboard, anonymous verdict feedback, six-language localization, Simple Mode, encrypted local backup, and a home-screen widget.
**Companion documents:** `DPDP_AUDIT.md` and `DPDP_COMPLIANCE.md` (original pass), `THIRD_PARTY_DATA_PROCESSORS.md` (updated by this pass).

This report does not claim legal compliance. It records what was found, what was changed, how it was tested, and what remains open — the same standard the original report held itself to.

---

## 1. Why this pass exists

The eight features above shipped between the 2026-09-04 DPDP pass and now. The most consequential of them, by far, is `server/accounts.py`: a real server-side account system. `DPDP_AUDIT.md` §0 states, accurately as of the date it was written:

> "Client accounts are fully local... there is no account server."

That statement is no longer true. `server/accounts.py` stores, for anyone who creates a cloud sync account: email and password hash (or a Google identity), the **full text** of every scan synced from a device, family group membership and every alert raised in it, a push-notification token, and learning/leaderboard progress. None of the erasure, export, or consent machinery built in the 2026-09-04 pass knew this system existed, because it didn't yet.

This pass exists to close that gap, and to give the other seven features (which turned out to be lower-risk, but not risk-free) the same review.

---

## 2. What was found

Reviewed every new feature's data flow against the same questions the original audit asked: what is collected, where does it go, can the user see it, can they delete it, is it disclosed. Findings, most serious first:

1. **CRITICAL — Account deletion never touched the server.** `AuthService.deleteAccount()` and `DataPrivacyService.deleteAccountAndAllData()` deleted only the local device account. `server/accounts.py` had a working, cascading `DELETE /account` endpoint — but nothing in the client ever called it. A user with a cloud sync account who deleted their account still had their email, full scan history, family membership, push token, and learning progress sitting on the server, indefinitely, with no way to remove it from the app.
2. **CRITICAL — No server-side export endpoint at all.** `GET /account/export` did not exist. "My Data" (the DPDP right-to-access feature from the original pass) only ever showed what was on the device — a user with cloud sync had no way to see, from within the app, what the server held about them.
3. **HIGH — Local scan deletion didn't propagate to the server.** `CloudSyncService.sync()` only ever pushed scans as `deleted: false`. Deleting a scan locally — even via the "Delete My Data" erasure flow — never told the server anything had changed. The old server-side copy, from any prior sync, was left untouched. Worse: a full resync (a new device signing in, or the sync cursor being reset, which `logout()` already did on every sign-out) would pull that "deleted" scan straight back down, undoing a deletion the user had already completed.
4. **HIGH — The in-app Privacy Policy and `THIRD_PARTY_DATA_PROCESSORS.md` predated all eight features.** Both were last written for the 2026-09-04 state of the app. Neither mentioned the cloud account, family alerts, push notifications, call screening, the leaderboard, verdict feedback, or encrypted backup — a user reading either document would have no idea any of these processed personal data.
5. **MEDIUM — Cloud account sign-up disclosed almost nothing.** The sheet that creates a cloud sync account (`family_screen.dart`) said only "it's what links your phones together and carries family alerts" — no mention that this uploads the full text of every scan, or that family members can see a member's verdict/risk/summary history.
6. **MEDIUM — "Delete My Data" / "Delete Account" left some derived data untouched.** Learning progress (points, streak, badges) was not reset by either erasure flow, and neither flow turned off active SMS or call screening — a "deleted" account could still have live phone/message monitoring running under it.
7. **HIGH — Both server SQLite databases were tracked in version control.** `.gitignore` had no `*.db`/`*.sqlite`/`*.sqlite3` rule at all — despite `DPDP_COMPLIANCE.md` (2026-09-04) explicitly claiming "`server_audit.db`... was previously not gitignored" in a way that implied it now was. `git ls-files` showed both `server/server_accounts.db` (schema for emails, password hashes, full synced scan text, family data — empty at the moment this was found, but that's incidental, not structural) and `server/server_audit.db` (22 real rows of audit-log data from earlier verification work) as tracked, committed files. See §4 for the fix and its limits.

Everything else reviewed — verdict feedback (anonymous by construction, a hash only), encrypted backup (never transmitted, user-controlled), Simple Mode and localization (no new data collection), the home-screen widget (a locally-computed status string) — was already sound and needed no change.

One unrelated bug surfaced while verifying the above with the full suite: `test_dpdp_privacy.py::test_cleanup_deletes_rows_older_than_configured_retention` failed, but only when run after `test_accounts.py` — passing every time in isolation. Root cause: the test imported `DB_PATH` by value at module load (`from main import app, DB_PATH`), while `test_accounts.py`'s fixture reassigns the live `main.DB_PATH` to a fresh temp file per test; the retention test was writing its fixture rows into a stale, no-longer-current path while `cleanup_audit_logs()` read from wherever `main.DB_PATH` actually pointed. Order-dependent test flakiness on a DPDP retention test undermines confidence in exactly the control this pass is about, so it was fixed alongside everything else (read `main.DB_PATH` dynamically instead) — see §3.

---

## 3. What was changed

### Server (`server/accounts.py`)
- Added `GET /account/export`: returns profile, devices, synced scans (full content, tombstones excluded), family membership/alerts (reusing the existing `_build_family_out`), learning progress, and a push-token *summary* (count/platform/date — never the raw token, which is a live device credential rather than content about the user).
- `DELETE /account` was already correct (cascading deletes via foreign keys) but had **zero test coverage** — added 7 tests confirming it actually cascades to synced scans, push tokens, and learning progress, dissolves a family the deleted user owned, and leaves other users' data untouched.

### Flutter client — new/changed service code
- `CloudAccountService.deleteAccount()` — calls the server, and **always** clears the local cloud session afterward regardless of whether the server call succeeded. Left alone on failure would risk a session surviving an erasure attempt with no visible sign anything went wrong; recovery if the network call genuinely failed is still possible by signing back in (the account still exists) and deleting again.
- `CloudAccountService.exportAccountData()` — fetches the new export endpoint; returns `null` on failure so the caller can say so explicitly.
- `CloudSyncService.pushTombstones()` — pushes an explicit `deleted: true` entry for records being removed, chunked to the server's 200-scan batch limit. Wired into: `HistoryScreen` single-delete and "Reset All"; `main.dart`'s scheduled retention cleanup (records are now loaded *before* being purged, so their cloud ids can still be computed); and `DataPrivacyService.deleteAllScanAndVaultData()`.
- `DataPrivacyService.deleteAllScanAndVaultData()` ("Delete My Data") now also resets learning progress locally and, if signed in, pushes the reset to the leaderboard, and refreshes the call-screening blocklist a synced-scan list feeds.
- `DataPrivacyService.deleteAccountAndAllData()` ("Delete Account") now: deletes the server-side cloud account first (before touching anything local, so a result is available to report even if a later local step were somehow interrupted); resets the sync cursor; disables SMS and call screening; and returns an `AccountDeletionResult` recording whether the server-side deletion was actually confirmed, rather than assuming success.
- `DataPrivacyService.exportUserData()` — merges in the server-held section (with an explicit error message if unreachable, not a silent omission), local learning progress, and call/SMS screening settings.

### Flutter client — UI
- `privacy_settings_screen.dart` — the "Delete My Data" dialog now says plainly when cloud-synced data is also being removed; a new completion dialog tells the user explicitly if their cloud account's deletion could not be confirmed (most likely no connection), with the concrete recovery step (sign back in, delete again).
- `family_screen.dart`'s cloud-account sign-up sheet now states, before the user creates an account, that full scan text uploads and that family members see verdict/risk/summary — with a direct link to the full Privacy Policy.
- `my_data_screen.dart` — the on-screen summary now shows cloud-sync status, server-held scan count (when reachable), and learning points, not just device-local figures.
- `privacy_policy_screen.dart` — rewritten with a dedicated section for each of: cloud sync account, family protection, push notifications, scam call screening, learning/leaderboard, verdict feedback, and encrypted backup. Existing sections (third-party services, data storage, retention, your controls, security measures) updated to reflect the account system's existence.
- `consent_service.dart` — `currentPolicyVersion` bumped `1.0.0` → `1.1.0`, so every existing user is re-prompted for essential consent against the updated notice on next launch, using the versioning mechanism the original pass already built for exactly this situation.

### Test infrastructure
- `server/test_dpdp_privacy.py` — fixed the order-dependent flake described in §2: reads `main.DB_PATH` dynamically instead of a value imported once at module load, so the test isolates correctly regardless of what other test files in the same run have reassigned it to.

### Documentation
- `THIRD_PARTY_DATA_PROCESSORS.md` — added a Firebase Cloud Messaging row (push token + generic alert text, no scan content); added a dated correction note addressing the now-outdated "no account server" line in `DPDP_AUDIT.md`, without editing that document itself (it is a dated snapshot; the correction lives here instead); documented what the new features do *not* send to any third party (verdict feedback, encrypted backup, the local call-screening blocklist).
- `DPDP_COMPLIANCE.md` — new dated addendum summarizing this pass, cross-referencing this report.

---

## 4. Repository hygiene: two personal-data-bearing files were tracked in git

Finding §2.7 above, fixed as follows:

- Added `*.db`, `*.sqlite`, `*.sqlite3` to `.gitignore` (there was no such rule at all, despite `DPDP_COMPLIANCE.md` implying one existed).
- Ran `git rm --cached server/server_accounts.db server/server_audit.db` — both files are untracked as of this pass's commit but remain on disk; nothing local was deleted.
- `server_accounts.db` held an empty schema (0 rows in every table) at the time this was found; `server_audit.db` held 22 real audit-log rows carried over from earlier verification work.

**What this fix does not do, and why:** the commits already made before this pass — on this branch, and already pushed to `origin/claude/protection-suite` — still contain the tracked snapshots of these files as they existed at each of those commits. Removing that from git *history* (not just from the current tree) requires rewriting commits and force-pushing the branch, which would invalidate anyone else's clone or any open pull request built on it. That is exactly the class of hard-to-reverse, outward-facing action this pass does not take unilaterally. **This needs an explicit decision from whoever owns this branch**: either rewrite history (`git filter-repo` or the BFG Repo-Cleaner, then a coordinated force-push) if the exposure is judged serious enough to warrant it, or accept that historical commits carry this snapshot and rely on the fix above to stop it from recurring. Given the current file contents were schema-empty and 22 rows of already-redacted audit excerpts rather than, say, live account credentials in bulk, this pass's judgment is that stopping the leak going forward is the correct immediate action and the history question is the user's call — but that judgment, and the decision itself, are both stated here rather than acted on silently.

## 5. Database changes

- No schema changes. `server/accounts.py`'s tables were already complete for what they need to do (they already supported tombstones via the existing `deleted` column on `synced_scans` — the bug was that the client never set it, not that the server couldn't represent it).

## 6. API changes

- New: `GET /account/export` (auth required).
- No changes to any existing endpoint's request/response shape. `DELETE /account`'s behavior is unchanged — only its test coverage and client-side reachability changed.

## 7. Privacy controls (summary)

Access now genuinely covers both storage locations (device + server, when applicable). Erasure now genuinely covers both, with the server-side result reported honestly rather than assumed. Consent's versioning mechanism was exercised for the first time since it was built. Third-party disclosure now lists every processor introduced by the protection suite.

## 8. Tests executed — actual results

Run in this environment on 2026-09-06.

```
cd server && python3 -m pytest test_accounts.py -q
```
**Result: 60 passed, 0 failed** (42 pre-existing + 18 new: 9 for `GET /account/export`, 7 for the previously-untested `DELETE /account` cascade behavior, plus 2 covering export/deletion auth requirements).

```
cd server && python3 -m pytest test_server.py test_accounts.py -q
```
Full server regression check — see §10 below for the combined result.

**Not run in this environment: `flutter test` / `flutter analyze`.** As with every Flutter change made in this session, there is no Flutter SDK available here (confirmed at session start; see the earlier protection-suite work). Every new or modified Dart API used above was checked against the actual method signatures already present in the codebase (`CloudAccountService.syncScans`, `ProgressService.resetProgress`, `CallScreeningService`'s exposed getters, `SmsScreeningService.disable`, etc.) rather than assumed, and the change set was kept to composing existing, already-tested building blocks wherever possible — but this is not a substitute for actually running `flutter test` and `flutter analyze` on a machine that has the Flutter SDK installed, which the user should do before release.

## 9. What was explicitly NOT claimed or fabricated

- No "DPDP Compliant" badge was added anywhere in the app.
- No retention period was invented for anything left open in the original pass (server audit-log retention, the breach-lookup ownership question) — those remain exactly as open as `DPDP_COMPLIANCE.md` already stated.
- The Grievance Officer placeholder was not filled with an invented contact.
- Legal basis, Data Fiduciary classification, and cross-border transfer review remain explicitly un-decided — this is engineering work, not a legal opinion, same disclaimer as the original report.
- Test counts above are the actual output of running the suite in this environment on 2026-09-06, not estimates.

---

## 10. Combined regression check

```
cd server && python3 -m pytest test_server.py test_accounts.py -q
```
**Result: 93 passed, 0 failed** (33 in `test_server.py`, unchanged since the original DPDP pass; 60 in `test_accounts.py`, up from 42 — the 18 new tests are §8 above).

```
cd server && python3 -m pytest test_accounts.py test_server.py test_dpdp_privacy.py -q
```
**Result: 107 passed, 0 failed**, confirming the fix in §3 — this exact combination, in this exact order, is what previously failed one test in `test_dpdp_privacy.py`.

Two categories of pre-existing, environment-related non-results, neither touched by this pass:
- `test_models.py` fails to *collect* here because the optional `google-genai` package isn't installed in this environment.
- `test_all_endpoints.py` and `test_security_remediation.py` are integration-style suites that dial an actual running server over the network (`httpx.ConnectError` with nothing listening) rather than using FastAPI's `TestClient` against the app in-process — they need a live server started separately and don't run standalone under plain `pytest` here.
