#!/usr/bin/env bash
# =============================================================================
#  ScamShield — automated issue + PR creator for the 5 changes
# =============================================================================
#  Creates 5 GitHub issues and 5 pull requests (each based on branch V1),
#  one per change, from your local working-tree edits.
#
#  The five PRs are FILE-DISJOINT — no file appears in two PRs — so each
#  branches off origin/V1 independently and they merge in any order with no
#  conflicts.
#
#  SAFE BY DEFAULT:
#    • Runs in DRY-RUN mode unless you pass DRY_RUN=0 — it only prints the plan.
#    • Before touching branches it stashes ALL your other uncommitted work
#      (tracked + untracked) and restores it at the end, so your pre-existing
#      changes to server/main.py, login_screen.dart, app icons, backend/*, etc.
#      are never swept into these PRs and never lost.
#
#  REQUIREMENTS: git, GitHub CLI (`gh`) authenticated (`gh auth login`).
#
#  USAGE:
#    chmod +x create_prs.sh
#    ./create_prs.sh                 # dry run — prints the plan, changes nothing
#    DRY_RUN=0 ./create_prs.sh       # actually create the 5 issues + 5 PRs
#    DRY_RUN=0 BASE=V1 ./create_prs.sh
#    DRY_RUN=0 ONLY="1 4" ./create_prs.sh   # only create PR #1 and PR #4
# =============================================================================

set -euo pipefail

# ---- config -----------------------------------------------------------------
BASE="${BASE:-V1}"          # target branch for every PR
REMOTE="${REMOTE:-origin}"
DRY_RUN="${DRY_RUN:-1}"     # 1 = preview only (default), 0 = execute
ONLY="${ONLY:-1 2 3 4 5}"   # which PRs to create (space-separated)

# ---- pretty printing --------------------------------------------------------
c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_cyan=$'\033[36m'; c_grn=$'\033[32m'
c_yel=$'\033[33m'; c_red=$'\033[31m'
say()  { printf '%s\n' "$*"; }
head() { printf '\n%s%s%s\n' "$c_bold$c_cyan" "$*" "$c_reset"; }
ok()   { printf '%s✓%s %s\n' "$c_grn" "$c_reset" "$*"; }
warn() { printf '%s!%s %s\n' "$c_yel" "$c_reset" "$*"; }
die()  { printf '%s✗ %s%s\n' "$c_red" "$*" "$c_reset" >&2; exit 1; }

# ---- PR definitions ---------------------------------------------------------
# Branch names
BR1="fix/threat-intel-status-honesty"
BR2="feat/apk-scan-in-scan-flow"
BR3="fix/apk-picker-card-scroll"
BR4="feat/email-breach-tab"
BR5="style/cybersec-fonts"

# Files per PR (disjoint sets)
FILES1=("lib/services/osint_service.dart" "lib/services/scanner_service.dart" "server/.env.example" "server/test_security_remediation.py")
FILES2=("lib/widgets/scan_now_bottom_sheet.dart")
FILES3=("lib/screens/apk_scan_screen.dart")
FILES4=("lib/services/breach_service.dart" "lib/screens/breach_screen.dart" "lib/main.dart" "lib/screens/home_screen.dart")
FILES5=("lib/theme.dart" "pubspec.yaml")

ISSUE_TITLE1="Threat-intel cards show scary false negatives: \"VirusTotal not available\", \"Safe Browsing not configured / no URLs checked\""
ISSUE_TITLE2="APK scan should live inside the Scan flow, not as its own bottom-nav tab"
ISSUE_TITLE3="APK results: \"Select APK\" picker card doesn't disappear when scrolling the report"
ISSUE_TITLE4="Replace the APK-scan tab with an Email-Breach checker (XposedOrNot-style UI)"
ISSUE_TITLE5="App typography is too generic — adopt a cybersecurity-themed font system"

PR_TITLE1="fix(osint): honest threat-intel statuses + remove hardcoded API keys"
PR_TITLE2="feat(scan): open the full APK scanner from the Scan bottom sheet"
PR_TITLE3="fix(apk): unify picker + report in one scroll view so the picker card scrolls away"
PR_TITLE4="feat(breach): Email-Breach tab (XposedOrNot-style) replacing the APK tab"
PR_TITLE5="style(theme): cybersecurity-themed typography (Orbitron + Rajdhani)"

# ---- preflight --------------------------------------------------------------
head "ScamShield PR kit  —  base=$BASE  remote=$REMOTE  dry_run=$DRY_RUN"

command -v git >/dev/null || die "git not found on PATH."
command -v gh  >/dev/null || die "GitHub CLI (gh) not found. Install: https://cli.github.com/"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Run this from inside the ScamShield git repo."

if [ "$DRY_RUN" = "0" ]; then
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run: gh auth login"
fi

say "Fetching $REMOTE ..."
git fetch "$REMOTE" --quiet || die "git fetch $REMOTE failed."
git rev-parse --verify "$REMOTE/$BASE" >/dev/null 2>&1 \
  || die "Base branch '$REMOTE/$BASE' not found. Set BASE=<branch> (e.g. BASE=main)."
ok "Base $REMOTE/$BASE exists."

ORIG_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
say "Current branch: $ORIG_BRANCH"

# Verify every file we intend to ship actually exists in the working tree.
ALL_FILES=("${FILES1[@]}" "${FILES2[@]}" "${FILES3[@]}" "${FILES4[@]}" "${FILES5[@]}")
missing=0
for f in "${ALL_FILES[@]}"; do
  [ -e "$f" ] || { warn "expected file not found: $f"; missing=1; }
done
[ "$missing" = "0" ] || die "Some expected files are missing — aborting so nothing half-applies."
ok "All ${#ALL_FILES[@]} expected files present."

# ---- plan print -------------------------------------------------------------
print_plan_row() {
  local n="$1" br="$2" title="$3"; shift 3
  printf '%s  PR%s%s  %s\n' "$c_bold" "$n" "$c_reset" "$title"
  printf '        branch: %s  →  %s\n' "$br" "$BASE"
  printf '        files : %s\n' "$*"
}
head "Plan"
print_plan_row 1 "$BR1" "$PR_TITLE1" "${FILES1[@]}"
print_plan_row 2 "$BR2" "$PR_TITLE2" "${FILES2[@]}"
print_plan_row 3 "$BR3" "$PR_TITLE3" "${FILES3[@]}"
print_plan_row 4 "$BR4" "$PR_TITLE4" "${FILES4[@]}"
print_plan_row 5 "$BR5" "$PR_TITLE5" "${FILES5[@]}"

if [ "$DRY_RUN" != "0" ]; then
  head "DRY RUN — nothing was changed."
  say "Re-run with:  DRY_RUN=0 ./create_prs.sh"
  say "Preview a subset with:  DRY_RUN=0 ONLY=\"1 3\" ./create_prs.sh"
  exit 0
fi

# ---- body files -------------------------------------------------------------
BODYDIR="$(mktemp -d)"
trap 'rm -rf "$BODYDIR"' EXIT

write_bodies() {
# ---- Issue 1 ----
cat >"$BODYDIR/issue1.md" <<'EOF'
### Problem
On the APK report and URL/text scans, the threat-intelligence section shows alarming, misleading statuses:

- **VirusTotal:** "not available — backend OSINT service unavailable"
- **Google Safe Browsing:** "not configured — no URLs checked"

These read as *failures/misconfiguration*, but they actually mean "this lookup wasn't run in on-device mode." Worse, the previous client shipped **hardcoded live API keys** in `lib/services/osint_service.dart` (VirusTotal / Google Safe Browsing / AbuseIPDB) — any APK can be decompiled and those keys extracted. That is a real secret-exposure vulnerability (ironic for a scanner whose own job is to find hardcoded secrets in other apps).

### Expected
- No secrets embedded in the mobile client. Keys live only in server-side env vars.
- When a provider wasn't run (no key / backend unreachable), say so **honestly and neutrally** — never fabricate a "safe" or a scary "misconfigured" verdict, and distinguish "not run" from "ran, found nothing."
- "No URLs were extracted, so there was nothing to check" is a clean state, not an error.

### Scope
`lib/services/osint_service.dart`, `lib/services/scanner_service.dart`, `server/.env.example`, and removing a real key still hardcoded in `server/test_security_remediation.py`.
EOF

# ---- Issue 2 ----
cat >"$BODYDIR/issue2.md" <<'EOF'
### Problem
APK scanning is a full, rich analysis flow but it's buried behind its own bottom-navigation tab, disconnected from the primary **Scan** action users reach for.

### Expected
The Scan entry point (the "Scan Now" bottom sheet) should offer **Scan APK / App** alongside text/URL/voice/screenshot, launching the complete APK scanner. This frees the bottom-nav slot (see the Email-Breach change) and puts APK scanning where users look for scanning.

### Scope
`lib/widgets/scan_now_bottom_sheet.dart` — add a "Scan APK / App" option that pushes `ApkScanScreen`.
EOF

# ---- Issue 3 ----
cat >"$BODYDIR/issue3.md" <<'EOF'
### Problem
On the APK screen, after a scan completes and you scroll the results, the **"Select Android APK binary"** picker card stays pinned at the top and never disappears. Root cause: the picker card was a fixed sibling *above* a separately-bounded scroll region for the report, so it couldn't scroll away.

### Expected
Once results are present, the picker card should scroll together with (and out of view above) the report. A compact "scanned file" header replaces it while scanning/after results.

### Scope
`lib/screens/apk_scan_screen.dart` — put the picker header and the report in a **single** `SingleChildScrollView`. (This PR also carries the client-side rendering of the honest VirusTotal / Safe Browsing status cards, since they live in this screen.)
EOF

# ---- Issue 4 ----
cat >"$BODYDIR/issue4.md" <<'EOF'
### Problem
With APK scanning moving into the Scan flow, the freed bottom-nav tab should host a user-facing **Email Breach** checker. The current breach screen also lacks the "scale of the problem" framing and follow-up guidance users expect (à la XposedOrNot / HIBP).

### Expected
- Bottom-nav **BREACH** tab (replaces APK SCAN).
- Two sub-tabs: **Email Breach Check** (default) and **Recent Breaches**.
- Email tab opens with a hero "scale of the problem" panel (data breaches, exposed records, exposed emails, exposed passwords — derived honestly from the real breach dataset) and a "What to do" guidance section.
- Home-screen deep links and the `main.dart` nav wiring updated to match.

### Scope
`lib/services/breach_service.dart` (breach-stats aggregation), `lib/screens/breach_screen.dart` (UI), `lib/main.dart` (nav), `lib/screens/home_screen.dart` (deep links).
EOF

# ---- Issue 5 ----
cat >"$BODYDIR/issue5.md" <<'EOF'
### Problem
The default Material typography is too generic for a security product.

### Expected
A cohesive cybersecurity-themed type system, applied app-wide:
- **Orbitron** — angular, techy display face for headings and the app-bar title.
- **Rajdhani** — condensed, highly legible UI face for body text and controls.

Because every screen uses hardcoded `TextStyle`s (no `textTheme` slot lookups), the Rajdhani text theme is set as the base so those styles inherit the new family, while Orbitron is wired into the heading/app-bar surfaces the theme controls directly.

### Scope
`lib/theme.dart`, `pubspec.yaml` (adds `google_fonts`). Run `flutter pub get` after checkout.
EOF

# ---- PR bodies (each closes its issue; %ISSUE% is replaced at runtime) ----
cat >"$BODYDIR/pr1.md" <<'EOF'
Closes #%ISSUE%

## What & why
Makes the threat-intelligence layer **honest** and **secret-free**.

- **Removed hardcoded live API keys** from `lib/services/osint_service.dart` (VirusTotal / Google Safe Browsing / AbuseIPDB). Keys are server-side only now.
- `OsintResult` gains an `available` flag so callers can tell "provider ran and found nothing" apart from "provider never ran." A `false` result no longer masquerades as a clean bill of health.
- `scanner_service.dart` on-device fallback returns clearly-worded, same-shaped `virustotal` and `safe_browsing` status objects (`checked: false` + a neutral explanation) instead of "service unavailable / not configured."
- Documented every server key in `server/.env.example`.
- Removed a real Google API key still hardcoded in `server/test_security_remediation.py` (replaced with a format-valid dummy; the redaction test still passes).

## Notes
Live verdicts require the backend OSINT proxy (`/osint/*`) with keys configured; without it, the client degrades honestly to "not run."

## Testing
Static analysis only in this environment (no Flutter SDK). Delimiter/scope verified. Please `flutter analyze` + run the app on the branch.
EOF

cat >"$BODYDIR/pr2.md" <<'EOF'
Closes #%ISSUE%

## What & why
Adds **Scan APK / App** to the "Scan Now" bottom sheet, launching the full `ApkScanScreen`. APK scanning now lives where users reach to scan, instead of a separate tab.

## Changes
- `lib/widgets/scan_now_bottom_sheet.dart`: new fourth option (Android icon) that closes the sheet and pushes `ApkScanScreen`.

## Testing
Static-verified. Pairs with the Email-Breach PR, which reclaims the vacated bottom-nav slot.
EOF

cat >"$BODYDIR/pr3.md" <<'EOF'
Closes #%ISSUE%

## What & why
Fixes the picker card that wouldn't scroll away on the APK results screen.

- Picker header and report now share **one** `SingleChildScrollView`, so the "Select Android APK binary" card scrolls up and out of view with the results (previously it was pinned above a separately-bounded scroll region).
- Adds a stale-result guard so a slow scan can't overwrite a newer one.
- Carries the **client-side rendering** of the honest VirusTotal / Safe Browsing cards (data-layer fix is in the threat-intel PR); cards read `checked`/`available` and default gracefully.

## Testing
Static-verified (single scroll owner; balanced widget tree). Please scroll a completed report on-device to confirm the picker card leaves the viewport.
EOF

cat >"$BODYDIR/pr4.md" <<'EOF'
Closes #%ISSUE%

## What & why
Replaces the APK-scan bottom-nav tab with a user-facing **Email Breach** checker.

- `main.dart`: bottom-nav slot APK SCAN → **BREACH**; screen wired to `BreachScreen`.
- `breach_screen.dart`: two sub-tabs — **Email Breach Check** (default) and **Recent Breaches**. Email tab leads with a "scale of the problem" hero (data breaches / exposed records / exposed emails / exposed passwords + latest-breach date) and a "What to do" guidance section.
- `breach_service.dart`: `getBreachStats()` aggregates the **real** breach dataset (only counts emails/passwords for breaches whose data classes actually include them) with B/M/K formatting.
- `home_screen.dart`: EMAIL CHECK / BREACHES deep links point at the right sub-tab.

## Testing
Static-verified. Stats derive from live `getRecentBreaches`; offline falls back to the bundled set.
EOF

cat >"$BODYDIR/pr5.md" <<'EOF'
Closes #%ISSUE%

## What & why
Introduces a cybersecurity-themed type system app-wide.

- **Orbitron** for display/heading surfaces and the app-bar title; **Rajdhani** for body/controls.
- Sets the Rajdhani text theme as the base so the many hardcoded `TextStyle`s inherit the new family without per-widget edits; Orbitron is applied to the display/headline/title slots and the app-bar/button themes the theme controls directly.
- Adds `google_fonts` to `pubspec.yaml`.

## Testing
Static-verified. Run `flutter pub get` after checkout. Fonts fetch on first run (google_fonts); consider bundling the .ttf files for fully offline builds as a follow-up.
EOF
}

# ---- execution --------------------------------------------------------------
create_pr() {
  local n="$1" br="$2" issue_title="$3" pr_title="$4"; shift 4
  local files=("$@")

  head "PR$n — $pr_title"

  # 1) issue
  say "Creating issue…"
  local issue_url issue_num
  issue_url="$(gh issue create --title "$issue_title" --body-file "$BODYDIR/issue$n.md")"
  issue_num="$(printf '%s' "$issue_url" | grep -oE '[0-9]+$' || true)"
  ok "Issue #$issue_num — $issue_url"

  # 2) fresh branch off the base
  git checkout -q -B "$br" "$REMOTE/$BASE"

  # 3) bring in ONLY this PR's files from the saved snapshot
  git checkout -q "$SNAP" -- "${files[@]}"
  git add -- "${files[@]}"

  if git diff --cached --quiet; then
    warn "No changes for PR$n versus $BASE — skipping commit/PR (already up to date?)."
    git checkout -q "$ORIG_BRANCH"
    return 0
  fi

  # 4) commit + push
  git commit -q -m "$pr_title" -m "Closes #$issue_num"
  say "Pushing $br…"
  git push -q -u "$REMOTE" "$br" --force-with-lease

  # 5) PR (body references the issue)
  sed "s/%ISSUE%/$issue_num/" "$BODYDIR/pr$n.md" >"$BODYDIR/pr${n}.final.md"
  local pr_url
  pr_url="$(gh pr create --base "$BASE" --head "$br" --title "$pr_title" --body-file "$BODYDIR/pr${n}.final.md")"
  ok "PR — $pr_url"

  git checkout -q "$ORIG_BRANCH"
}

# Save the entire working tree (tracked + untracked) so branch switching is safe
# and your unrelated changes are never touched.
STASH_REF=""
if git stash push -u -m "scamshield-pr-kit-$(date +%s)" >/tmp/_ss_stash 2>&1 && ! grep -q "No local changes" /tmp/_ss_stash; then
  STASH_REF="$(git rev-parse stash@{0})"
  SNAP="$STASH_REF"
  ok "Stashed your working tree (restored automatically at the end)."
else
  SNAP="HEAD"
  warn "Working tree clean — using HEAD as the snapshot (edits assumed committed)."
fi

restore() {
  git checkout -q "$ORIG_BRANCH" 2>/dev/null || true
  if [ -n "$STASH_REF" ]; then
    if git stash list | grep -q "$(printf '%s' "$STASH_REF" | cut -c1-7)"; then :; fi
    git stash pop -q 2>/dev/null && ok "Restored your original working tree." \
      || warn "Could not auto-restore the stash. Run 'git stash list' then 'git stash pop'."
  fi
}
trap 'restore; rm -rf "$BODYDIR"' EXIT

write_bodies

for n in $ONLY; do
  case "$n" in
    1) create_pr 1 "$BR1" "$ISSUE_TITLE1" "$PR_TITLE1" "${FILES1[@]}" ;;
    2) create_pr 2 "$BR2" "$ISSUE_TITLE2" "$PR_TITLE2" "${FILES2[@]}" ;;
    3) create_pr 3 "$BR3" "$ISSUE_TITLE3" "$PR_TITLE3" "${FILES3[@]}" ;;
    4) create_pr 4 "$BR4" "$ISSUE_TITLE4" "$PR_TITLE4" "${FILES4[@]}" ;;
    5) create_pr 5 "$BR5" "$ISSUE_TITLE5" "$PR_TITLE5" "${FILES5[@]}" ;;
    *) warn "Unknown PR number '$n' in ONLY — skipping." ;;
  esac
done

head "Done."
say "Created issues + PRs for: $ONLY  (base: $BASE)"
say "Your working tree and original branch ($ORIG_BRANCH) are restored."
