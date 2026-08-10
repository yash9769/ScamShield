# ScamShield — Codebase Audit

**Date:** 2026-08-08
**Scope:** Full-repository audit, remediation and completion
**Severity scale:** `CRITICAL` / `HIGH` / `MEDIUM` / `LOW`

---

## 1. Executive Summary

ScamShield presents as an enterprise-grade mobile security platform. The README
advertises MobSF orchestration, JADX decompilation, APKTool unpacking, Gemini
explainable AI, and VirusTotal / Safe Browsing / AbuseIPDB threat intelligence.

The reality on arrival was substantially different. The project contained a
large volume of well-written code, much of which **was never executed**. The
three headline capabilities — AI analysis, APK scanning, and authentication —
were each non-functional, and each failed *silently*, presenting a working
interface over machinery that never ran.

The three defining findings:

1. **Gemini AI had never worked in any deployment.** `requirements.txt` pinned
   `google-generativeai`, which does not provide the `from google import genai`
   import path the code uses. The resulting `ImportError` was caught by a broad
   handler that set `GEMINI_AVAILABLE = False`. Every install ran permanently in
   heuristic-only mode.

2. **The APK scanner never contacted a server.** The client posted to
   `POST /scan`, a route that existed only in an orphaned application tree that
   is never started. Every scan 404'd, was swallowed by a bare `catch`, and fell
   back to on-device analysis — while the UI displayed convincing progress
   checkmarks for MobSF, JADX and VirusTotal, none of which were invoked.

3. **Authentication was theatre.** Login accepted any credentials after a
   cosmetic delay. There was no account, no storage, no verification.

Compounding this, **live third-party API keys were hardcoded in client Dart
source** — extractable from any built APK by precisely the technique ScamShield
performs on other applications.

A structural observation frames all of the above: the repository contains **two
separate backends**. `server/main.py` (337 lines) is what the client actually
targets and what runs. `backend/app/` (~40 files) is a far more sophisticated
application that nothing starts and nothing calls. Most of the advertised
enterprise capability lives in the dead tree. The audit prioritised making the
*live* path genuinely work over resurrecting the dormant one.

**Outcome:** all `P0` items and the substantial majority of `P1`/`P2` items are
fixed and verified. The backend now has a real, tested APK analysis pipeline,
real rate limiting and input validation, no client-side secrets, and real
authentication. 22 automated tests pass; all endpoints verified live.

**Principal caveat:** no Dart/Flutter SDK exists in this environment, so Dart
changes are **not compile-verified**. See §9.

---

## 2. Original Architecture

```
ScamShield/
├── lib/                    Flutter client (13 screens, 10 services)
├── server/                 ACTIVE backend — FastAPI, text analysis  ← client targets this
├── backend/                DEAD backend — FastAPI + MobSF/SQLAlchemy/Redis  ← never started
├── android/ ios/ web/ ...  Platform runners
└── docs/                   Documentation
```

**Stack:** Flutter (Dart) client; FastAPI (Python 3.12) backend; SQLite +
`shared_preferences` on-device; Gemini for AI; Androguard/YARA for static
analysis; PostgreSQL/Redis referenced only by the dead tree.

**Intended product** (inferred from code, routes, schema and UI): a consumer
mobile app that (a) classifies suspicious text/SMS as safe/suspicious/scam with
explanations, (b) performs static security analysis of APK files, (c) checks
credential breaches, and (d) teaches scam recognition through an encyclopedia
and quizzes.

**The critical architectural fact:** `ScannerService` posts to
`http://10.0.2.2:8000/scan`. `server/main.py` — the only backend that runs on
port 8000 — exposed only `/`, `/health` and `/analyze`. The client and server
had never agreed on a contract.

---

## 3. Problems Discovered

### CRITICAL

| # | Finding |
|---|---|
| C1 | Wrong Gemini SDK package pinned; AI silently disabled in every deployment |
| C2 | `POST /scan` did not exist on the live server; all APK scans silently degraded |
| C3 | VirusTotal, Google Safe Browsing and AbuseIPDB API keys hardcoded in client Dart |
| C4 | Authentication entirely simulated; any credentials granted full access |

### HIGH

| # | Finding |
|---|---|
| H1 | No rate limiting anywhere — trivial CPU exhaustion and Gemini quota drain |
| H2 | File upload with no type, size or content validation |
| H3 | `api_service.dart` hardcoded `127.0.0.1`; unreachable from Android emulator |
| H4 | Fabricated scan progress UI asserting tools ran that never ran |
| H5 | Failed analysis invented `riskScore: 50 / suspicious` for unanalysed input |

### MEDIUM

| # | Finding |
|---|---|
| M1 | `allow_origins=["*"]` combined with `allow_credentials=True` (invalid, browser-rejected) |
| M2 | No request-body size limit on `/analyze` |
| M3 | Raw exception strings rendered into user-facing UI |
| M4 | Unreachable OSINT provider indistinguishable from a verified-clean result |
| M5 | `backend/app/routes/scan_endpoints.py` had zero imports — `NameError` on import |
| M6 | `test_models.py` aborted the entire pytest session at collection time |
| M7 | `fastapi==0.110` ↔ `google-genai` dependency conflict via `starlette`/`httpx` |
| M8 | Undeclared runtime dependencies (`python-multipart` et al.) |

### LOW

| # | Finding |
|---|---|
| L1 | Machine-specific `file:///c:/Users/...` links throughout documentation |
| L2 | Hardcoded developer-laptop path in `backend/test_apks.py` |
| L3 | `print()` used for error logging in client code |
| L4 | Inert "Deepfake Filter" toggle for a capability that does not exist |
| L5 | Hardcoded demo scam string in `file_scanner_service.dart` |

---

## 4. Features That Were Missing

- **Server-side APK analysis** — the client's central feature had no server counterpart.
- **Any authentication system** — no account, credential storage or verification existed.
- **OSINT proxy endpoints** — no safe path existed for the client to obtain threat intelligence without embedding secrets.
- **Rate limiting** — absent from every endpoint.
- **Upload validation** — absent entirely.
- **Automated tests for the live backend** — the only `test_*.py` in `server/` was a diagnostic that broke test collection.
- **`.env.example` for `server/`** — only the dead `backend/` had one.

---

## 5. Features That Were Broken

| Feature | Presented as | Actually did |
|---|---|---|
| Gemini AI analysis | AI-powered, `aiPowered: true` | Import failed; heuristics only, always |
| APK server scan | 7-stage MobSF/JADX/YARA pipeline | 404 → silent on-device fallback |
| Scan progress UI | Live per-tool completion | Fixed timers; tools never invoked |
| Login / Register | Account authentication | Accepted anything; stored nothing |
| OSINT lookups | Live threat intelligence | Mock verdicts from hardcoded string checks |
| Text analysis (Android) | Backend AI call | Unreachable host; always error path |
| Error handling | User-friendly | Leaked raw exceptions; invented risk scores |

---

## 6. Security Findings

Ordered by severity, with resolution status.

**CRITICAL — Secret exposure in client binary.** Three live-format API keys were
string literals in `lib/services/osint_service.dart`, shipped inside the APK.
Any attacker could extract them — the same operation ScamShield performs on
other apps. *Resolved:* keys removed from the client; lookups proxied through
server-side `/osint/*` endpoints reading from environment variables.
**These keys must be treated as compromised and rotated immediately.**

**CRITICAL — Broken authentication.** Any email/password combination granted
access to scan history and the Safe Vault. *Resolved:* PBKDF2-HMAC-SHA256
(120k iterations, random per-account salt, constant-time comparison) with
credentials in `flutter_secure_storage`. Implementation cross-validated against
`hashlib.pbkdf2_hmac` — exact byte match.

**HIGH — Unrestricted file upload.** `POST /scan` accepted any file of any size.
*Resolved:* extension check, ZIP-magic content validation, non-empty check,
100 MB cap, secure `NamedTemporaryFile` handling (client filenames are never
used in path construction, preventing traversal), and guaranteed cleanup.

**HIGH — No rate limiting.** *Resolved:* `slowapi` — 30/min on `/analyze` and
`/osint/*`, 10/min on `/scan`. Verified: 429 returned from the 8th rapid call.

**HIGH — SSRF / request injection.** The `/osint/ip/{ip}` path segment would
reach an outbound request. *Resolved:* strict `ipaddress.ip_address()`
validation; hashes constrained by regex to MD5/SHA-1/SHA-256.

**MEDIUM — CORS misconfiguration.** Wildcard origins with credentials enabled.
*Resolved:* `allow_credentials=False`, configurable origins, methods restricted.

**MEDIUM — Denial of service via unbounded input.** *Resolved:* 10,000-character
cap on `/analyze`; 50-URL cap and 2,000-character URL limit on `/osint/urls`.

**MEDIUM — Information disclosure.** Raw exceptions rendered to users and
`/scan` returning internal error text. *Resolved:* internals logged server-side;
users receive generic messages.

**MEDIUM — Misleading security signalling.** An unreachable provider rendered
identically to a verified-clean result — a safety-relevant deception in a
security product. *Resolved:* explicit `available` flag; unverified results are
labelled and visually distinct.

**Not fixed — dependency vulnerability scanning.** No SCA tooling (`pip-audit`,
`osv-scanner`) is available in this environment. Recommended for CI.

---

## 7. Changes Implemented

Full detail in `CHANGELOG.md`. Summary:

**Backend (`server/main.py`)** — implemented `POST /scan` (Androguard, YARA,
secret/URL extraction, hashing, VirusTotal); added `/osint/hash`, `/osint/urls`,
`/osint/ip`; added rate limiting, input validation, upload limits, CORS fix,
structured logging.

**Client (`lib/`)** — new `auth_service.dart` (PBKDF2); rewrote
`osint_service.dart` (secrets removed, honest availability semantics); wired
real auth into login/register; replaced fabricated progress UI; fixed Android
base URL; removed invented risk scores on failure; `debugPrint` for logging.

**Housekeeping** — removed a dead file that could not import; converted a
test-collection-breaking diagnostic into a guarded script; fixed dependency
pins and the FastAPI/httpx conflict; parameterised hardcoded paths; cleaned
documentation links; added `server/.env.example` and `server/test_server.py`.

---

## 8. Testing Performed

Executed in a clean container. Results are actual.

| Activity | Command | Result |
|---|---|---|
| Dependency install | `pip install -r server/requirements.txt` | Clean, no conflicts |
| Import check | `python -c "import main"` | `google-genai SDK loaded` |
| Unit/integration tests | `python -m pytest server/test_server.py -q` | **22 passed** (1.01s) |
| Server startup | `uvicorn main:app` | Clean, 0 tracebacks |
| Endpoint exercise | `curl` across all 7 routes | All 200/expected |
| OpenAPI validation | `GET /openapi.json` | 7 paths, schema valid |
| Negative paths | Oversized, wrong-type, corrupt, malformed | 400/422 as designed |
| Rate limiting | 11 rapid `/scan` calls | 7×200 then 4×429 |
| SSRF guard | `/osint/ip/evil.example.com` | 400 |
| Real APK analysis | Signed 175 KB APK | Parsed; correct package, cert, hashes |
| Malware detection | Crafted trojan-marker APK | `CRITICAL`/90, `Cerberus` YARA hit, 2 secrets |
| Determinism | Repeated identical scans | Identical hash and score |
| Crypto validation | PBKDF2 vs `hashlib` reference | **Exact byte match** |
| Placeholder sweep | `grep` TODO/FIXME/mock/simulate | Clean in `lib/`, `server/` |

**Not performed:** `flutter analyze`, `flutter test`, `flutter build` — no SDK
available. See §9.

---

## 9. Remaining Limitations

**Dart code is not compile-verified.** No Flutter SDK exists here. Dart changes
were checked by delimiter balance and by confirming every invoked API exists —
which did catch one real defect (a call to a non-existent
`UserProfileService.setName`). This is weaker than compilation.
**Run `flutter pub get && flutter analyze && flutter test` before shipping.**

**Third-party success paths are untested.** Without credentials, Gemini,
VirusTotal, Safe Browsing and AbuseIPDB exercise only their no-key fallback
branches.

**MobSF / JADX / APKTool are not integrated.** They require external
containers/binaries. The pipeline no longer claims to run them; Androguard,
YARA and string extraction provide genuine coverage without them.

**`backend/app/` remains dead code.** Roughly 40 files of unreached
functionality. Resolving this changes the deployment model and is a product
decision, not a bug fix.

**Local accounts have no recovery or sync.** No user backend exists, so there is
no password reset and no cross-device continuity.

**The heuristic engine is keyword-based.** Effective on canonical scam text and
fully deterministic, but defeatable by paraphrase and biased toward English and
Indian-context fraud patterns. It is a fallback, not a substitute for the AI path.

---

## 10. Recommended Next Steps

**Immediate**

1. **Rotate the three exposed API keys.** They are in git history and must be assumed compromised.
2. **Run `flutter analyze` and fix anything it surfaces** — the one genuinely unverified area of this work.
3. Provision a `GEMINI_API_KEY` and confirm the AI path end-to-end; it has never run successfully.

**Short term**

4. Decide the fate of `backend/app/` — promote it to the real backend or delete it. Two backends is the root cause of the client/server contract mismatch. *(Still open — the only remaining P1 item; it is a deployment-model decision, not a defect.)*
5. ~~Add CI~~ — **done**: `.github/workflows/ci.yml` runs `pytest`, `pip-audit`, `flutter analyze`, `flutter test`, and a hardcoded-secret gate.
6. ~~Remove or implement the inert "Deepfake Filter" toggle~~ — **done**: removed and replaced with a functional, persisted Clipboard Check setting.
7. ~~Expand `sample_rules.yar`~~ — **done**: five new rules added and a false-positive rule (`TestRule`, matching bare `"Firebase"`) removed.
8. **Implement OCR** if image scanning is to be a real feature. It currently checks only the filename and says so; the backend OCR service exists but lives in the unmounted `backend/app/` tree.

**Medium term**

8. If accounts should sync across devices, add a real auth backend (the current design is deliberately device-local).
9. Persist scan history server-side with per-user authorization — note that IDOR risk arrives with multi-user data, and the schema in the dead tree does not currently enforce ownership.
10. Add caching (hash → report) so repeat APK scans avoid full re-analysis.
11. Instrument detection quality with a labelled corpus; the README's accuracy claims are currently unsubstantiated by any measurement in the repository.
