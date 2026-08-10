# Changelog

All notable changes from the codebase takeover, audit and completion pass.

## [2.2.0] — 2026-08-08 (second pass)

### Implemented

- **Persisted app settings (`lib/services/settings_service.dart` — new).** The Profile screen's switches were backed by `final bool` fields with `onChanged: (v) {}` — physically un-togglable, stored nowhere, read by nothing. They now persist to `SharedPreferences` and drive real `ValueNotifier` state.
- **Working sign-out.** "Secure Sign Out" previously only displayed a snackbar claiming the session was cleared; the user stayed logged in. It now calls `AuthService.logout()` and returns to the login screen via `pushAndRemoveUntil`.
- **Session restore.** `main.dart` always launched the login screen, so a signed-in user re-authenticated on every cold start. It now checks `AuthService.isLoggedIn()` and goes straight to the app.
- **Scan result caching.** `POST /scan` now caches completed reports by APK SHA-256 in a bounded LRU (128 entries), skipping the full Androguard/YARA/VirusTotal pipeline on repeat uploads. Responses carry a `cached` flag. Verified live: first scan `cached=false`, second `cached=true`, identical risk output.
- **CI pipeline (`.github/workflows/ci.yml` — new).** Runs backend tests, `pip-audit`, `flutter analyze`, `flutter test`, plus a grep gate that fails the build if provider API keys reappear in source.
- **Five new YARA rules** — SMS interception, overlay attacks, dynamic code loading, device-admin abuse, and root/emulator evasion.
- **Three new tests** (25 total): cache hit/miss, cache key isolation, and explicit rate-limit enforcement.

### Removed Fabricated Behaviour

- **Fabricated file-scan verdicts.** `pickAndScanFile`, `pickAndScanImage` and `scanClipboard` each caught *all* exceptions and returned a hardcoded scam analysis — a fake overdue invoice, a fake bank-alert screenshot, a fake customs-fee text — presented to the user as the result of scanning *their* file, and written to scan history as though real. All three now return a typed `FileScanResult.failure(...)` with a zero score, and the calling widget surfaces the error instead of recording a verdict.
- **Fabricated OCR.** Image scanning invented "extracted text" describing a wire-transfer scam and ran the detector over it, so *every* image produced the same scam result. There is no OCR in this build; it now analyses only the filename and states that limitation plainly.
- **Fabricated subscription.** The profile screen asserted "Premium Plan – Active … Renews Oct 2026" with 256-bit VPN and dark-web monitoring — none of which exist and none of which the user purchased. Replaced with an honest About dialog describing actual capabilities and where data is stored.
- **Inert "Deepfake Filter" toggle removed.** No deepfake detection exists anywhere in the codebase; the switch advertised a capability the product does not have. Replaced with a functional Clipboard Check setting.
- **False-positive YARA rule removed.** `TestRule` matched the bare string `"Firebase"`, which appears in a large share of legitimate apps — every one would have been labelled a "known-malware signature" match and given a +40 risk penalty. Verified removed: a benign Firebase string now yields no matches.
- **Misleading sign-out copy** claiming "vault notes remain encrypted on device" — the vault does not encrypt — replaced with an accurate description.

### Fixed

- **Rate limiting made configurable** via `RATE_LIMIT_ENABLED`. This surfaced a genuine test-isolation defect: the suite's own `/scan` calls exhausted the 10/min budget and caused unrelated tests to receive 429s. Limits are now disabled during tests and asserted explicitly in a dedicated test.

### Testing (second pass)

| Command | Result |
|---|---|
| `python -m pytest server/test_server.py -q` | **25 passed** (1.10s) |
| YARA compile + false-positive check | Compiles; benign Firebase string → no matches; SMS trojan string → `SMS_Interception` |
| Live cache verification | 1st `cached=false`, 2nd `cached=true`, `CRITICAL`/`Cerberus` preserved |
| Live endpoint sweep | All 200; **0 tracebacks** |

---

## [2.1.0] — 2026-08-08

### Implemented

**Real server-side APK static analysis (`POST /scan`)**
The Flutter client (`ScannerService`) had always posted APKs to `POST /scan` on
port 8000, but that route did not exist in the server that actually runs
(`server/main.py`). It existed only in the orphaned `backend/app/` tree, which
is never mounted or started. Every "server mode" scan therefore returned 404,
was swallowed by a bare `catch`, and silently degraded to the on-device
scanner — while the UI continued to display "MobSF / JADX / APKTool /
VirusTotal" progress steps. The endpoint is now implemented for real:

- Androguard parsing of manifest, permissions, activities and X.509 signer certs
- YARA signature matching against the bundled `backend/yara_rules/sample_rules.yar`
- Hardcoded-secret detection (AWS, Google, Firebase, JWT, Stripe, Supabase, OpenAI, GitHub, private keys)
- URL/endpoint extraction from DEX, native and resource entries
- MD5 / SHA-1 / SHA-256 fingerprinting
- VirusTotal hash reputation lookup (server-side key)
- Weighted risk scoring producing `LOW` / `MEDIUM` / `HIGH` / `CRITICAL`

Verified against a real signed APK and against a crafted sample containing
banking-trojan markers, which correctly produced a `Cerberus` YARA match plus
two hardcoded secrets and scored `CRITICAL` / 90.

**Real local authentication (`lib/services/auth_service.dart` — new)**
Login and registration previously accepted *any* input: a one-second
`Future.delayed("Simulate network delay")` followed by unconditional
navigation into the app. No account existed, nothing was stored, and the
password field was decorative. Replaced with genuine local accounts:

- PBKDF2-HMAC-SHA256, 120,000 iterations, 32-byte derived key
- Cryptographically random 16-byte per-account salt (`Random.secure()`)
- Constant-time hash comparison to avoid timing leaks
- Credentials stored in `flutter_secure_storage` (Keychain / EncryptedSharedPreferences), never plain `SharedPreferences`
- Plaintext passwords are never persisted
- Email format and password strength validation, with distinct, accurate error messages
- Registration now actually persists the chosen display name via `UserProfileService.updateProfile`

The PBKDF2 implementation was validated byte-for-byte against Python's
reference `hashlib.pbkdf2_hmac` — output matches exactly.

**OSINT proxy endpoints (`/osint/hash/{hash}`, `/osint/urls`, `/osint/ip/{ip}`)**
Added so the mobile client can obtain threat intelligence without ever holding
provider API keys. All three degrade honestly when a key is absent.

**Test suite (`server/test_server.py` — new)**
22 tests covering health/metadata, scam and benign classification, payload
limits, heuristic determinism and score bounds, APK validation and report
shape, secret detection, scan determinism, corrupt-archive handling, and all
OSINT validation paths including the SSRF guard.

### Security Fixes

| Severity | Issue | Resolution |
|---|---|---|
| CRITICAL | Live third-party API keys (VirusTotal, Google Safe Browsing, AbuseIPDB) hardcoded as string literals in `lib/services/osint_service.dart`, shipped inside the APK and trivially extractable — by the very technique this app performs on other apps | Keys removed from the client entirely; lookups proxied through new server-side `/osint/*` endpoints where keys live only in environment variables |
| CRITICAL | Authentication was entirely simulated — any email/password combination granted full access to scan history and the Safe Vault | Real PBKDF2-backed local accounts (see above) |
| HIGH | `POST /scan` accepted arbitrary uploads of unbounded size with no type checking | Enforced `.apk` extension, real ZIP-magic validation, non-empty check, and a 100 MB cap |
| HIGH | No rate limiting on any endpoint; unauthenticated callers could exhaust CPU via repeated APK analysis or drain the Gemini quota | `slowapi` limits added: 30/min on `/analyze` and `/osint/*`, 10/min on `/scan`. Verified: the 8th rapid `/scan` call returns 429 |
| HIGH | `/osint/ip/{ip}` path segment would have been interpolated into an outbound request — an SSRF / request-injection vector | Strict `ipaddress.ip_address()` validation before any outbound call; hashes validated against a strict MD5/SHA-1/SHA-256 regex |
| MEDIUM | CORS configured with `allow_origins=["*"]` together with `allow_credentials=True` — an invalid combination browsers reject, and a misconfiguration risk if origins were later narrowed | `allow_credentials=False` (the API is stateless), origins configurable via `ALLOWED_ORIGINS`, methods restricted to GET/POST/OPTIONS |
| MEDIUM | Unbounded request bodies on `/analyze` | 10,000-character cap enforced via a pydantic validator (returns 422) |
| MEDIUM | Raw exception text rendered directly into the user-facing UI (`'Error connecting to backend: $e'`), leaking internal details | Exceptions logged via `debugPrint`; users see a clean, non-leaking message |
| MEDIUM | An unreachable OSINT provider returned `isMalicious: false`, visually identical to a verified-clean result — "we could not check" was silently presented as "safe" | Added an `available` flag; unverified lookups render in grey with explicit "NOT a confirmation of safety" wording |
| LOW | No `.env.example` for the server that actually runs, encouraging ad-hoc secret handling | Added `server/.env.example` documenting every variable and its no-key fallback behaviour |

### UI/UX Fixes

- **Removed the fabricated scan progress animation.** `apk_scan_screen.dart` animated a fixed list — Uploading, APKTool, JADX, MobSF, YARA, VirusTotal, Generating Report — on hardcoded timers (`[2, 4, 6, 6, 4, 4]` seconds), ticking green checkmarks for tools that were never invoked. Replaced with three stages that reflect what genuinely runs, driven by the real request lifecycle rather than a timer.
- **Connection failures no longer invent a risk verdict.** A failed `/analyze` call previously returned `classification: suspicious, riskScore: 50` — a fabricated score for a message that was never analysed. It now returns a neutral, clearly-labelled "Analysis Unavailable" state that explicitly states it is not a verdict of safety.
- **Fixed Android networking.** `api_service.dart` hardcoded `http://127.0.0.1:8000`, which on an Android emulator resolves to the emulator itself, so every text analysis failed. Now resolves `10.0.2.2` on Android, matching the other services.
- Registration surfaces specific, actionable validation errors instead of a single generic message.
- PDF reports render unverified OSINT lookups in grey rather than misleading green.

### Architecture Changes

- Removed `backend/app/routes/scan_endpoints.py` — a dead file with **no import statements at all** (referenced `router`, `select`, `Scan`, `os`, `HTTPException`, `AsyncSession` without importing any of them). It would have raised `NameError` on import and was never mounted by any router.
- Renamed `server/test_models.py` → `server/check_gemini_models.py`. Despite the `test_` prefix it was a manual diagnostic that instantiated a Gemini client at module import time; pytest auto-collected it and aborted the **entire** test session with `ValueError: Missing key inputs argument` whenever `GEMINI_API_KEY` was unset. It is now guarded behind `main()` / `__main__` and exits gracefully with a helpful message.
- Made `backend/test_apks.py` configurable via `SCAMSHIELD_TEST_APK_DIR` / `SCAMSHIELD_BASE_URL` instead of a hardcoded path to a specific developer's laptop.
- Stripped machine-specific `file:///c:/Users/...` links from `README.md` and `docs/README.md`, replacing them with repository-relative links.

### Dependency Fixes

- **`google-generativeai` → `google-genai`.** This was the single most consequential bug in the project. `server/main.py` does `from google import genai`, an import path the pinned `google-generativeai==0.4.1` package does not provide. The import raised `ImportError`, was caught by a broad `except ImportError`, and set `GEMINI_AVAILABLE = False` — so **every deployment ran permanently in heuristic-only mode while reporting itself as AI-powered**. Confirmed the failure and the fix by installing both packages and testing the import directly.
- **`fastapi>=0.115`.** The previous `fastapi==0.110.0` pin brought `starlette 0.36.3`, whose `TestClient` is incompatible with the `httpx>=0.28.1` required by `google-genai`, making the two dependencies mutually unsatisfiable and blocking all HTTP-level testing.
- Added the previously undeclared but required `python-multipart` (needed for file upload), `androguard`, `yara-python`, `slowapi`, `httpx` and `pytest` to `server/requirements.txt`.

### Testing

All commands run from a clean container; results are actual, not projected.

| Command | Result |
|---|---|
| `pip install -r server/requirements.txt` | Success — resolves cleanly with no conflicts |
| `python -c "import main"` | Success — `[ScamShield] google-genai SDK loaded.` (previously fell back to heuristic-only) |
| `python -m pytest server/test_server.py -q` | **22 passed**, 2 warnings, 1.01s |
| `python server/check_gemini_models.py` | Exits 1 with a clear message when no key is set (previously crashed pytest collection) |
| `uvicorn main:app` + live HTTP exercise | All 7 routes 200/expected; **0 tracebacks** in server logs |
| PBKDF2 cross-validation vs `hashlib.pbkdf2_hmac` | Byte-for-byte **MATCH** |

Live endpoint results:

```
health:200  root:200  analyze:200  scan:200
osint_hash:200  osint_ip:200  osint_urls:200
OpenAPI paths: ['/', '/analyze', '/health',
                '/osint/hash/{file_hash}', '/osint/ip/{ip}',
                '/osint/urls', '/scan']
```

Negative-path and security checks, all confirmed:

```
/analyze  20,000-char body        -> 422
/scan     .txt extension          -> 400 "Only .apk files are accepted."
/scan     .apk name, non-ZIP body -> 400 "not a valid ZIP archive"
/scan     empty file              -> 400
/scan     11 rapid calls          -> 200 x7 then 429 x4  (rate limit active)
/osint/hash/notahash              -> 400
/osint/ip/evil.example.com        -> 400  (SSRF guard)
/osint/urls with 60 URLs          -> 422
```

Real detection verified on a crafted APK containing banking-trojan markers:

```json
{ "risk": { "level": "CRITICAL", "score": 90,
            "details": ["Contains hardcoded API keys/secrets inside dex/resource files.",
                        "Extracted 1 remote network endpoint(s).",
                        "Matched 1 known-malware YARA signature(s): Cerberus."] },
  "secrets": { "findings": { "aws_access_key": 1, "openai_api_key": 1 } },
  "yara":    { "matches": ["Cerberus"] } }
```

### Remaining Issues

These could not be completed in this environment, or represent decisions that
should not be made unilaterally.

**Blocked by unavailable tooling**

- **The Flutter application was never compiled.** No Dart/Flutter SDK, Android SDK or Gradle is available here. All Dart changes were verified by delimiter-balance checks and by grepping that every called API actually exists — a method that did catch one real bug (a call to a non-existent `UserProfileService.setName`, corrected to `updateProfile`). **Run `flutter pub get && flutter analyze && flutter test` before shipping.** Treat the Dart changes as unverified until then.
- **No live third-party credentials.** Gemini, VirusTotal, Safe Browsing and AbuseIPDB paths are exercised only along their no-key fallback branches. The success branches are implemented and shape-validated but have not run against the real providers.
- **MobSF, JADX and APKTool are not integrated.** These require external containers/binaries unavailable here. The `/scan` pipeline deliberately does not claim to run them — Androguard, YARA and string-extraction cover manifest, signature and secret analysis without them. The `backend/app/analyzers/{jadx,apktool}.py` wrappers remain for a Docker deployment.
- **PostgreSQL and Redis were not exercised.** No instances available; `server/main.py` does not depend on either.

**Deliberately left for a product decision**

- **The `backend/app/` tree is entirely dead code.** It is a second, much larger FastAPI application (MobSF orchestration, SQLAlchemy models, SSE progress, batch/voice/image endpoints, its own test suite) that nothing starts and the client never calls. It should either become the real backend or be deleted — both are substantial changes that would alter the product's deployment model, so neither was done unilaterally. The active backend remains `server/main.py`, matching what the client targets.
- **`file_scanner_service.dart` contains a hardcoded `sampleText` scam string**, apparently a demo affordance. Left in place pending confirmation of whether it backs a real feature.
- **The profile screen's "Deepfake Filter" toggle is inert** (`final bool _deepfakeFilter = true;`, non-interactive). No deepfake detection exists anywhere in the codebase. It should be removed or implemented; removing an advertised feature was not done without confirmation.
- **Local accounts are per-device and offer no recovery.** There is no user backend, so there is no password reset and no cross-device sync. This is the correct scope for the current architecture but is a genuine product limitation.
