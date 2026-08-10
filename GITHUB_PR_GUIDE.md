# ScamShield — GitHub Issues & PRs kit

This kit turns the five changes into **5 GitHub issues + 5 pull requests**, each based on branch **`V1`**.

- **`create_prs.sh`** — automated. Safe by default (dry-run), non-destructive to your other work.
- This guide — what each PR contains, a manual fallback, and one **security action you should take now**.

---

## ⚠️ Security: rotate these keys now

During our chat, real API keys and a DB password were pasted in plaintext. They now live **only** in your git-ignored `server/.env` and `backend/.env` (verified: not tracked, not in any PR, not in the ZIP). Even so, because they were exposed in chat, treat them as compromised and **rotate them**:

- **VirusTotal API key** — regenerate at virustotal.com → API key.
- **Google Safe Browsing key** — rotate in Google Cloud Console → Credentials. (A copy was also hardcoded in `server/test_security_remediation.py`; PR1 replaces it with a dummy.)
- **AbuseIPDB key** — regenerate in your AbuseIPDB account.
- **DB password** (`scamshield_password`) — change it; it's only a default in `backend/app/core/config.py`, but don't ship it to production.

After rotating, put the new values in `server/.env` / `backend/.env` only.

---

## The five PRs (file-disjoint)

No file appears in two PRs, so every branch is cut from `V1` independently and they merge in **any order** with no conflicts.

| PR | Title | Files |
|----|-------|-------|
| 1 | fix(osint): honest threat-intel statuses + remove hardcoded API keys | `lib/services/osint_service.dart`, `lib/services/scanner_service.dart`, `server/.env.example`, `server/test_security_remediation.py` |
| 2 | feat(scan): open the full APK scanner from the Scan bottom sheet | `lib/widgets/scan_now_bottom_sheet.dart` |
| 3 | fix(apk): unify picker + report in one scroll view | `lib/screens/apk_scan_screen.dart` |
| 4 | feat(breach): Email-Breach tab replacing the APK tab | `lib/services/breach_service.dart`, `lib/screens/breach_screen.dart`, `lib/main.dart`, `lib/screens/home_screen.dart` |
| 5 | style(theme): cybersecurity-themed typography | `lib/theme.dart`, `pubspec.yaml` |

**Why `apk_scan_screen.dart` is only in PR3:** that file mixes the scroll fix (PR3) with the on-screen VirusTotal/Safe-Browsing status cards (conceptually PR1). To keep the PRs file-disjoint, the whole screen ships in PR3; PR1 owns the data layer that feeds those cards. Each still compiles independently — the screen reads the status maps with safe defaults.

---

## How to run it

```bash
# from the repo root
chmod +x create_prs.sh

# 1) preview — prints the plan, changes nothing
./create_prs.sh

# 2) create all 5 issues + 5 PRs against V1
DRY_RUN=0 ./create_prs.sh

# variations
DRY_RUN=0 ONLY="1 4" ./create_prs.sh   # only PR1 and PR4
DRY_RUN=0 BASE=main   ./create_prs.sh   # target a different base branch
```

**Requirements:** `git` and the GitHub CLI `gh`, authenticated (`gh auth login`).

**What it does safely:** stashes *all* your other uncommitted work (tracked + untracked — your `server/main.py`, `login_screen.dart`, app icons, `backend/*`, etc.), builds each branch from `origin/V1` with only that PR's files, opens the issue + PR, then restores your original branch and working tree. It uses `--force-with-lease` on push so re-runs update the same branch without clobbering anyone else's work.

> After merging PR5, run `flutter pub get` (it adds the `google_fonts` dependency).

---

## Manual fallback (if you'd rather not use the script)

Do this once per PR. Example shown for PR1; repeat with each row's branch/files.

```bash
git fetch origin

# snapshot your current edits so we can pick files off it onto a clean branch
SNAP=$(git stash create)          # prints a commit SHA; if empty, your edits are already committed → use HEAD

# --- PR1 ---
git checkout -B fix/threat-intel-status-honesty origin/V1
git checkout ${SNAP:-HEAD} -- lib/services/osint_service.dart lib/services/scanner_service.dart server/.env.example server/test_security_remediation.py
git add lib/services/osint_service.dart lib/services/scanner_service.dart server/.env.example server/test_security_remediation.py
git commit -m "fix(osint): honest threat-intel statuses + remove hardcoded API keys"
git push -u origin fix/threat-intel-status-honesty
gh issue create --title "Threat-intel cards show false negatives; hardcoded keys" --body "See PR."
gh pr create --base V1 --head fix/threat-intel-status-honesty \
  --title "fix(osint): honest threat-intel statuses + remove hardcoded API keys" \
  --body "Honest VirusTotal/Safe-Browsing statuses; removed hardcoded API keys."

git checkout -   # back to where you were
```

Branch → files for the other four:

- **PR2** `feat/apk-scan-in-scan-flow` → `lib/widgets/scan_now_bottom_sheet.dart`
- **PR3** `fix/apk-picker-card-scroll` → `lib/screens/apk_scan_screen.dart`
- **PR4** `feat/email-breach-tab` → `lib/services/breach_service.dart lib/screens/breach_screen.dart lib/main.dart lib/screens/home_screen.dart`
- **PR5** `style/cybersec-fonts` → `lib/theme.dart pubspec.yaml`

---

## Note on verification

These edits were verified statically (scope/delimiter balance, disjoint file sets, graceful defaults) — this environment has no Flutter SDK, so nothing was compiled. Before merging, please run on each branch:

```bash
flutter pub get
flutter analyze
flutter run     # smoke-test the affected screen
```
