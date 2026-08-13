# ScamShield

> **Status note (read first):** This repository contains **one canonical Python backend** (`backend/`, a FastAPI service) plus a Flutter mobile app. A legacy monolithic backend existed in earlier iterations and has been **removed**; this README reflects the current single-backend reality.

---

## 1. Project Overview

**Project name:** ScamShield

**What it does:** ScamShield is a mobile-first consumer security app (Flutter) that helps everyday users detect scams, phishing, malicious Android apps, and data-breach exposure. Users paste a suspicious SMS/link, attach a voice note or screenshot, upload an APK file, or look up an email — and the app returns a plain-English risk verdict with a score and the reasons behind it.

**Problem it solves:** Scam/phishing/fraud targeting Indian and global consumers (OTP fraud, UPI scams, fake delivery/courier messages, malicious APKs, credential leaks) is widespread. Most victims lack tooling to evaluate a message or app before acting. ScamShield gives a non-expert a fast, explainable verdict.

**Target users:** Mobile users (currently Android-targeted) who receive suspicious messages, install APK files outside Play Store, or want to know if their email was breached.

**Main purpose:** Turn threat intelligence + AI + static malware analysis into an app a normal person can use in seconds.

**Core value proposition:** "Paste it / upload it / look it up → get an explainable safe/suspicious/scam verdict, with no security expertise required."

**Current project status:** 🟡 **Multi-stage / partially integrated.** The Flutter app and the single `backend/` FastAPI service are functionally connected and runnable.
- Text / voice / image / breach lookups → `backend/app` FastAPI on port `8000`.
- APK scan → `scanner_service.dart` calls `POST /scan` in `backend/app/routes/scan.py` at the port-8000 host (`http://10.0.2.2:8000` on emulator / `http://localhost:8000`).
- **Client auth is ON by default:** every sensitive endpoint requires an anonymous per-install `X-Device-Token` (generated on-device by `lib/services/device_identity.dart`) or a server-side `X-API-Key`. Scans are owned by the creating device.
- Several advanced integrations (MobSF, PostgreSQL, Redis) are wired but require external services to be running to fully work; without them the code degrades gracefully (heuristic-only / on-device fallback).
- Gemini / Groq LLMs are supported. Groq is accessed natively using lightweight `httpx` completions calls to avoid adding SDK weight, routing automatically if `GROQ_API_KEY` is present or if `GEMINI_API_KEY` starts with the `gsk_` prefix.

---

## 2. Key Features

### Runtime Mode & Key Dependency Matrix

| Mode / Feature | Requirements | Behavior when Requirements Unmet |
|---|---|---|
| **Full AI Scam Analysis** | Backend reachable + `GEMINI_API_KEY` or `GROQ_API_KEY` set on backend | Automatically falls back to local heuristic scam detector with clear `[HEURISTIC ONLY - OFFLINE/NO-AI]` labeling. |
| **Live OSINT Enrichment** | Backend reachable + `VIRUSTOTAL_API_KEY` / `GOOGLE_SAFE_BROWSING_API_KEY` / `ABUSEIPDB_API_KEY` set | Skips live cloud reputation lookups and clearly marks report sections as un-checked. |
| **Server APK Pipeline** | Backend reachable + server environment (Androguard, YARA, APKTool, JADX) | Automatically falls back to `ApkAnalyzerService` (on-device static analyzer parsing ZIP/Manifest/DEX bytecode patterns). |
| **Email Breach Check** | Internet connection | Queries XposedOrNot API directly. |
| **Local Account & Vault** | On-device only | Works completely offline; credentials hashed via PBKDF2-HMAC-SHA256 and vault notes encrypted with hardware KeyStore. |

Features are grouped by category. Status values: ✅ implemented, 🟡 partially / depends on external service, 🔵 mocked-or-degraded fallback, 🔴 missing/broken.

### Core features
| Feature | Description | Status |
|---|---|---|
| **Text/sms/links threat scan** | Paste message/link → verdict + score + reasons. Calls `POST /analyze`. | ✅ |
| **Voice note scan** | Upload audio → Whisper transcription + analysis. | 🟡 (backend calls Whisper only if `openai-whisper` installed; otherwise returns heuristic text) |
| **Screenshot / image OCR scan** | Upload image → EasyOCR + analysis. | 🟡 (backend uses EasyOCR; when unavailable, Flutter analyzes filename & metadata only and clearly notifies user) |
| **APK security scanner** | Upload `.apk` → static analysis (permissions, secrets, YARA, VirusTotal, Safe Browsing) + risk score + PDF report. | ✅ (full pipeline) with 🔵 on-device fallback in `ApkAnalyzerService` if backend unreachable |
| **Email breach lookup** | Email → XposedOrNot exposure result. | ✅ |
| **Breach feed / stats** | Global breach list + "scale of the problem" stats. | ✅ (HIBP feed, offline fallback list) |

### User / account features
| Feature | Description | Status |
|---|---|---|
| **Local account (signup/login)** | PBKDF2-HMAC-SHA256 accounts stored in `flutter_secure_storage` (Keychain / EncryptedSharedPreferences). No server account. | ✅ |
| **Session** | "active" flag in secure storage; `AuthService.isLoggedIn()` gates the app nav. | ✅ |
| **Logout / delete account** | Clears session / all local credentials. | ✅ |
| **Encrypted Safe Vault** | Store passwords/PINs/notes encrypted on device. | ✅ |
| **Profile editing** | Name / title / avatar (preset avatar URLs). | ✅ |

### UI / UX features
| Feature | Description | Status |
|---|---|---|
| **Bottom nav (Home/Scan/Breach/History/Learn/Profile)** | Primary navigation in `MainNavigation`. | ✅ |
| **Clipboard monitor** | On app resume, scans clipboard for URLs/OTP/URGENT and shows "SCAN NOW" snackbar. | ✅ |
| **Scan history** | SQLite-backed list, search, filter (All/Threats/Safe), swipe-to-delete, clear-all. | ✅ |
| **Dark themed UI, motion/reveal animations** | Custom `theme.dart`, `widgets/motion.dart`. | ✅ |
| **Educational "Cyber Threat Academy"** | Spot-the-scam quiz + 3 learning modules + vigilance score. | ✅ |
| **SIM/Device guard screen** | Device info, root-status via platform channel, opens OS settings. | 🟡 (root check is best-effort; no actual SIM-lock toggle in app) |

### Backend features
| Feature | Description | Status |
|---|---|---|
| **Unified analysis engine** (`ai_engine`) | Gemini/Groq + heuristic + OSINT → weighted score. | ✅ (backend) |
| **Heuristic scam engine** | Keyword/regex scam detector (always available fallback). | ✅ |
| **Rate limiting** (slowapi) | Per-endpoint limits. | ✅ |
| **Security headers + request-ID logging middleware** | `middleware/`. | ✅ |
| **APK pipeline** (Androguard/APKTool/JADX/MobSF/YARA/Secrets) | `backend/app/routes/scan.py`. | 🟡 (MobSF/Androguard/YARA optional; degrades) |
| **Audit logging** (SQLite) | `backend/app/services/audit.py` writes privacy-preserving audit rows (event type, SHA-256 input fingerprint, length, score — never raw content). | ✅ |

### AI / ML features
| Feature | Description | Status |
|---|---|---|
| **Gemini / Groq LLM verdict** | Structured JSON scam classification w/ category, confidence, reasons. | ✅ (when key set) |
| **Whisper transcription** | Local OpenAI Whisper. | 🔵 optional |
| **EasyOCR** | Image→text (en+hi). | 🔵 optional |
| **AI explanation of APK risk** | `AIExplanationService` summarises findings. | ✅ (when key set) |

### Data features
| Feature | Description | Status |
|---|---|---|
| **Local scan history** (SQLite) | `DatabaseHelper` (`scamshield.db`). | ✅ |
| **Server scan history** (Postgres) | `backend/app/models/schema.py` scans/reports. | 🟡 (requires Postgres) |
| **OSINT cache** (Redis or in-memory) | `osint_service` SimpleCache / Redis. | 🟡 |

### Integrations
| Feature | Description | Status |
|---|---|---|
| **VirusTotal** | Hash/URL reputation. | ✅ (key optional) |
| **Google Safe Browsing** | URL screening. | ✅ (key optional) |
| **AbuseIPDB** | IP abuse check (server). | ✅ (key optional) |
| **XposedOrNot** | Email breach exposure. | ✅ |
| **Have I Been Pwned** | Breach feed + optional per-email (key-gated). | ✅ / 🔵 (feed works; per-email needs key) |
| **URLhaus** | Keyless malware-URL fallback from client. | ✅ |
| **MobSF** | Containerized APK scanning. | 🟡 (requires MobSF container) |
| **WHOIS** | Domain age check. | ✅ |

### Security features
| Feature | Description | Status |
|---|---|---|
| **Local secret storage** | `flutter_secure_storage`. | ✅ |
| **PBKDF2 password hashing** | 120k iters, random salt, constant-time compare. | ✅ |
| **Secret-free client** | Keys live server-side; CI fails on hardcoded keys. | ✅ |
| **Zip-bomb / size guards** (server APK + on-device) | 200MB size cap + entry-count cap + uncompressed-size quota + per-entry compression-ratio guard + scan concurrency cap + analyzer timeouts. | ✅ |
| **Client auth on all endpoints** | `X-Device-Token` / `X-API-Key` required on `/analyze*`, `/scan*`, `/history`, `/breach`, `/osint/*`; scans tied to owning device. | ✅ |
| **Privacy-preserving logs/audit** | Raw message/email text is never logged or stored — only SHA-256 fingerprints + length. | ✅ |
| **Pinned toolchain** | MobSF image pinned to `v4.5.2`; apktool/jadx downloads verified by SHA-256 at build time. | ✅ |

---

## 3. Complete Technology Stack

| Technology | Category | Where Used | Why It Is Used |
|---|---|---|---|
| **Dart / Flutter 3.11** | Mobile framework | `lib/`, `android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/` | Cross-platform (Android-first) mobile UI. |
| **Flutter `http`** | HTTP client | `lib/services/*.dart` | REST calls to backends. |
| **`sqflite`** | Local DB | `lib/data/database/database_helper.dart` | On-device scan history + preferences. |
| **`flutter_secure_storage`** | Secure storage | `auth_service.dart`, `safe_vault_screen.dart` | Encrypted credentials/notes (Keychain/EncryptedSharedPreferences). |
| **`shared_preferences`** | KV storage | settings, vault fallback | Simple flags/preferences. |
| **`crypto`** | Crypto | `auth_service.dart` | PBKDF2-HMAC-SHA256 password hashing. |
| **`file_picker`** | File picking | `apk_scan_screen.dart` | Select APK files. |
| **`image_picker`** | Media | scan screen | Pick screenshots. |
| **`pdf` + `printing`** | PDF gen/preview | `report_generator_service.dart` | APK audit PDF export. |
| **`archive`** | Zip handling | `apk_analyzer_service.dart` | Parse APK (zip) on-device. |
| **`permission_handler` / `device_info_plus` / `app_settings`** | Device | `sim_lock_screen.dart`, `permission_service.dart` | Permissions, device info, open settings. |
| **`connectivity_plus`** | Connectivity | offline banner | Online/offline awareness. |
| **`url_launcher` / `open_filex` / `xml` / `google_fonts`** | Utilities | various | Open links, PDFs, fonts. |
| **Python 3.12** | Backend language | `backend/` | API + analysis. |
| **FastAPI** | Web framework | `backend/app/main.py`, `backend/app/api/` | Async REST API. |
| **Uvicorn** | ASGI server | `backend/app/main.py` | Serve the API. |
| **Pydantic / pydantic-settings** | Validation/config | `backend/` | Request/response models + env config. |
| **SQLAlchemy 2 (async)** | ORM | `backend/app/core/db.py`, `models/schema.py` | Postgres access for scans/reports. |
| **asyncpg / psycopg** | Postgres driver | `backend/requirements.txt` | Async Postgres. |
| **SQLite3 (stdlib)** | Audit DB | `backend/app/services/audit.py` | Privacy-preserving audit log store. |
| **Redis (redis.asyncio)** | Cache/stream | `backend/app/services/progress.py`, `osint` | Scan progress SSE + OSINT cache. |
| **slowapi** | Rate limiting | both | Per-route limits. |
| **google-genai** | LLM SDK | `gemini_service.py` | Gemini 2.0/2.5 calls. |
| **Groq (OpenAI-compat httpx)** | LLM SDK | `gemini_service.py`, `ai_explanation.py` | Llama models as alternative AI. |
| **openai-whisper** | Speech-to-text | `backend/app/services/voice_service.py` | Audio transcription. |
| **EasyOCR + pdf2image** | OCR | `backend/app/services/ocr_service.py` | Image/screenshot→text. |
| **python-whois** | OSINT | `backend/app/services/osint_service.py` | Domain age check. |
| **Androguard** | APK analysis | `backend/app/analyzers/` | Manifest/permission/cert parsing. |
| **yara-python** | Signature match | `backend/app/analyzers/yara_analyzer.py` | Malware rule matching. |
| **ApkTool / JADX (binaries)** | Decompile | `backend/app/routes/scan.py` (subprocess) | Resource/DEX extraction. |
| **MobSF (container)** | Mobile security | `backend/app/services/mobsf.py` | Full APK scan via API. |
| **ReportLab** | PDF (server) | `backend/app/reports/generator.py` | Server-side PDF reports. |
| **httpx** | HTTP client | `backend/` | Outbound API calls. |
| **YAML (pyyaml)** | Config | `risk_engine.py` | Risk weights. |
| **Docker / docker-compose** | Deployment | `backend/docker/` | Container stack (api+mobsf+redis+db). |
| **GitHub Actions** | CI | `.github/workflows/ci.yml` | Lint, test, secret-scan. |

---

## 4. Architecture Overview

```
User (Android)
  │  taps / pastes / uploads
  ▼
Flutter app (lib/)
  │  http (10.0.2.2:8000 or localhost:8000)
  ├──────────────┬───────────────┬───────────────────┐
  ▼              ▼               ▼                   ▼
/analyze        /analyze-voice  /scan (APK)         /breach, /osint/*
(text)          (audio)         (upload .apk)        (email/IP/URL)
  │              │               │                   │
  ▼              ▼               ▼                   ▼
backend FastAPI (backend/app)   backend FastAPI      backend FastAPI  (XposedOrNot)
  │  ai_engine                  routes/scan.py        │
  ├─ Gemini/Groq (LLM)          ├─ Androguard         ├─ VirusTotal
  ├─ heuristic_service          ├─ APKTool/JADX       ├─ Google Safe Browsing
  └─ osint_service              ├─ MobSF              └─ AbuseIPDB (server)
     (VirusTotal,                ├─ YARA
      Safe Browsing,             ├─ Secrets
      WHOIS)                     ├─ RiskEngine
     │                           ├─ AIExplanation
     ▼                           └─ PostgreSQL + Redis
  (JSON verdict)                (reports JSON+PDF)
```

**Layers:**
- **Presentation (Flutter):** screens + widgets; talks to services; never holds secrets.
- **Service/network (Flutter):** `api_service`, `scanner_service`, `osint_service`, `breach_service`, `apk_analyzer_service` (on-device fallback).
- **Backend API (FastAPI):** routers aggregate engines; middleware for CORS/security/rate-limit/logging.
- **Engines (backend):** `ai_engine` orchestrates LLM + heuristic + OSINT; `risk_engine` scores APK risk.
- **External services:** LLM providers, VirusTotal, Safe Browsing, AbuseIPDB, XposedOrNot, HIBP, URLhaus, MobSF.
- **Data:** on-device SQLite (history) and server PostgreSQL (scans/reports) + Redis.

The Flutter app's `ApiService`/`OsintService`/`BreachService`/`ScannerService` call the port-8000 host served by the **single** `backend/app` FastAPI service.

---

## 5. Project Structure

```
ScamShield 2/
├── lib/                      # Flutter app source
│   ├── main.dart             # Entry point + bottom nav + clipboard monitor
│   ├── theme.dart            # App colors/theme
│   ├── screens/              # 12 screens (home, scan, apk_scan, breach, history,
│   │                         #   learn, learning_module, login, register, profile,
│   │                         #   safe_vault, sim_lock)
│   ├── services/             # Network + local engines (api, scanner, osint, breach,
│   │                         #   apk_analyzer, auth, settings, user_profile,
│   │                         #   report_generator, scam_detector, file_scanner,
│   │                         #   localization, permission)
│   ├── data/                 # repositories, database helper, models, education
│   ├── widgets/              # motion (animations), offline_banner, scan_now sheet
│   └── utils/                # permission_mapper
├── android/ ios/ web/ ...    # Platform runners (Flutter)
├── backend/                  # Primary and only canonical FastAPI backend
│   ├── app/
│   │   ├── main.py           # App factory, lifespan (create tables), middleware
│   │   ├── api/v1/           # All core endpoints: analyze, voice, image, batch, breach, router, health (supports /analyze, /analyze-voice, /analyze-image, /scan, /breach)
│   │   ├── routes/scan.py     # POST /scan APK pipeline + SSE progress
│   │   ├── services/         # ai_engine, gemini, heuristic, ocr, voice, osint,
│   │   │                     #   osint_service, mobsf, xposedornot, ai_explanation,
│   │   │                     #   risk_engine, progress
│   │   ├── analyzers/        # androguard, apktool, jadx, yara, secrets
│   │   ├── models/           # schema (SQLAlchemy), enums, base
│   │   ├── core/             # config, db, logging, exceptions
│   │   ├── middleware/       # error_handler, rate_limit, security_headers
│   │   ├── reports/          # generator (PDF/JSON)
│   │   └── utils/            # file_utils, text_utils
│   ├── docker/             # Dockerfile + docker-compose.yml
│   ├── tests/              # pytest unit/integration/performance
│   ├── yara_rules/         # sample_rules.yar
│   ├── app/config/risk_weights.yaml (referenced; expected at /app/app/config in Docker)
│   ├── requirements.txt
│   └── .env.example
├── docs/ dataset/ QA/        # Documentation, eval dataset, QA plans
├── pubspec.yaml analysis_options.yaml
└── README.md SECURITY.md CODEBASE_AUDIT.md CHANGELOG.md
```

### Purpose of Important Directories and Files
- `lib/services/apk_analyzer_service.dart`: Client-side APK parser. Extracts Manifest, DEX printable strings, certificates in a separate **Dart Isolate** via `compute()` to prevent blocking the Flutter UI thread.
- `lib/services/auth_service.dart`: Handles local credentials security. Performs PBKDF2-HMAC-SHA256 (120,000 iterations) with random salt on passwords, saving credentials inside Keychain/EncryptedSharedPreferences via `flutter_secure_storage`.
- `backend/app/services/ai_engine.py`: Orchestrates Gemini/Groq + Heuristics + OSINT and computes weighted scores: `score = (ai * 0.55) + (heuristic * 0.30) + (osint * 0.15)`.
- `backend/app/routes/scan.py`: The static and dynamic APK analysis orchestrator. Triggers concurrent static analyzers (Androguard, JADX, APKTool), MobSF containerized analyses, YARA rules compilation/matching, secrets extraction, and publishes real-time progress events over Redis Pub/Sub using Server-Sent Events (SSE).

---

## 6. Frontend Deep Dive

- **Framework:** Flutter 3.11 (Dart). Android-first; other platforms present but untested here.
- **Entry point:** `lib/main.dart` → `main()` initialises `UserProfileService`, `SettingsService`, checks `AuthService.isLoggedIn()`, requests permissions, then runs `ScamShieldApp`. If logged in → `MainNavigation` (bottom nav: Home/Scan/Breach/History/Learn/Profile), else `LoginScreen`.
- **Routing/navigation:** No router package; in-app `Navigator.push` between screens; bottom nav via `IndexedStack`.
- **Screens:** Home (stats + quick actions), Scan (text/url/voice/screenshot tabs), APKScan, Breach (email check + feed), History, Learn (academy), Login, Register, Profile, SafeVault, SimLock, LearningModule.
- **State management:** Mostly local `setState` + `ValueListenableBuilder`/`ChangeNotifier` (`UserProfileService`, `SettingsService`). No Redux/Provider/Bloc.
- **API communication:** `ApiService` (text/voice/image → `backend` on `:8000`), `ScannerService` (APK → `:8000/scan`), `OsintService` (VT/SB/AbuseIPDB/URLhaus), `BreachService` (XposedOrNot + HIBP). Base URL: `http://10.0.2.2:8000` on Android emulator, `http://127.0.0.1:8000` otherwise.
- **Auth handling:** Local only (`auth_service.dart`). Login persists a session flag; protected by `isLoggedIn()` gate at startup.
- **Form handling:** TextField controllers + inline validation (email regex, password rules).
- **Error handling:** `try/catch` → `ScamDetector.analyze` local fallback or "Analysis Unavailable" result; `ScaffoldMessenger` snackbars; `BreachCheckException` states.
- **Loading states:** Spinners, `LinearProgressIndicator`, staged "Static Analysis Pipeline" in APK screen.
- **UI system:** Custom `AppColors` dark theme; cards, chips, `Reveal`/`Pressable`/`RadarSweep` motion widgets.
- **Styling:** Material + custom; `google_fonts`.
- **Responsive:** Single-column scroll; `GridView` for stat cards; not explicitly responsive for tablets.
- **Local storage:** `sqflite` (`scamshield.db`) for history/prefs; `flutter_secure_storage` for auth+vault.

**Screen/Component table:**

| Screen/Component | Purpose | Main Logic | APIs/Services Used |
|---|---|---|---|
| **HomeScreen** | Dashboard + stats summary + quick actions | Loads stats from `ScanRepository`; routes actions. | `sqflite` local database |
| **ScanScreen** | Threat scanner workspace for text, links, voice, screenshot | Manual textbox inputs; dispatches text to service; falls back to `ScamDetector`. | `/analyze` API |
| **ApkScanScreen** | Custom Android APK file picking and scanning dashboard | Pick APK, run scan via server, print staged logs. | `/scan` and `/scan/{id}/progress` (SSE) |
| **BreachScreen** | Checks if emails are leaked in databases; list recent pwns | Email field validation, check breach, display list. | `/api/v1/breach`, HIBP Feed |
| **HistoryScreen** | Local history logs viewer | Query local scans; search/filter/delete logs. | `sqflite` (SQLite repository) |
| **LearnScreen** | Interactive Quiz + educational articles | Challenges scenario state machine + quiz rendering. | None (static client data) |
| **SafeVaultScreen** | Store credentials and secure notes | Reads/writes notes safely to secure storage. | `flutter_secure_storage` |
| **SimLockScreen** | Device details and integrity analyzer | Uses native method channels to check root status/encryption. | Native OS settings, device info |
| **ProfileScreen** | Configure notifications, profile info, settings, sign out | Edit details, choose preset avatars, toggle settings. | Local storage, secure storage |

---

## 7. Backend Deep Dive (`backend/app`)

- **Backend framework:** FastAPI (async Python).
- **Entry point:** `backend/app/main.py` → `create_app()` factory.
- **Server structure:** Lifespan handler initializes SQLAlchemy engine and creates schema; middlewares hook CORS, security headers, Slowapi rate-limiting, and timing details.
- **Routes/endpoints (actually defined):**

| Method | Endpoint | Purpose | Request | Response | Authentication |
|---|---|---|---|---|---|
| **POST** | `/analyze` | Analyze text message for scams | `TextAnalysisRequest` | `AnalysisResult` | Client auth (Rate limited: 60/min) |
| **POST** | `/analyze-voice` | Transcribe + scan audio file | multipart file | `VoiceAnalysisResponse` | Client auth (Rate limited: 10/min) |
| **POST** | `/analyze-image` | OCR extract + scan image/PDF | multipart file | `ImageAnalysisResponse` | Client auth (Rate limited: 10/min) |
| **POST** | `/analyze-batch` | Batch process multiple texts | `BatchAnalysisRequest` | `BatchAnalysisResponse` | Client auth (Rate limited: 20/min) |
| **GET** | `/breach` | Lookup email exposure | query `?email=` | `BreachResponse` | Client auth (Rate limited: 30/min) |
| **POST** | `/scan` | Upload & run full APK analysis | multipart file | full scan JSON | Client auth + concurrency cap |
| **GET** | `/scan/{id}` | Read generated report | path variable | report JSON | Client auth + ownership check |
| **GET** | `/scan/{id}/progress` | Real-time SSE progress events | path variable | SSE Stream (`text/event-stream`) | Client auth + ownership check |
| **DELETE**| `/scan/{id}` | Delete report and uploaded APK | path variable | `{"status": "deleted"}` | Client auth + ownership check |
| **GET** | `/history` | Read server scan history (own device only) | None | `{"history": [...]}` | Client auth + ownership filter |
| **GET** | `/health` | Check backend & downstream health | None | `{"status": "ok"}` | Public |

---

## 8. Database Deep Dive

The system operates two separate databases:

### 1. Client-Side SQLite (`scamshield.db`) — Local
Using the `sqflite` Dart driver. Table details:

| Table | Purpose | Important Fields | Relationships |
|---|---|---|---|
| **`scan_records`** | Store personal history of manual scans | `id` (Auto-inc PK), `input_text`, `classification`, `risk_score`, `summary`, `timestamp`, `source` | None |
| **`user_preferences`** | Singleton configurations on the client | `id` (PK constant 1), `has_consented`, `notifications_enabled`, `daily_tip_enabled` | None |

### 2. Server-Side PostgreSQL — Multi-User
Structured via SQLAlchemy ORM (asyncpg driver) in `backend/app/models/schema.py`:

| Table | Purpose | Important Fields | Relationships |
|---|---|---|---|
| **`users`** | Register UUIDs for API consumer isolation | `id` (UUID PK), `username`, `created_at` | One-to-many with `scans` |
| **`scans`** | Scanned APK details and report links | `id` (UUID PK), `user_id` (FK), `sha256`, `package`, `risk_score`, `status`, `osint_results` | Many-to-one with `users`, One-to-many with `reports`, `scan_logs` |
| **`reports`** | Tracks generated output JSON & PDF paths | `id` (PK), `scan_id` (FK), `json_path`, `pdf_path` | One-to-one with `scans` |
| **`cached_osint`** | Caches API vendor answers for performance | `id` (PK), `ioc_type`, `ioc_value`, `provider`, `data` (JSON), `expires_at` | None |
| **`api_usage`** | Collect API metrics (times, status) | `id` (PK), `provider`, `timestamp`, `response_time_ms`, `success` | None |
| **`scan_logs`** | Logs start/end states of analyzers | `id` (PK), `scan_id` (FK), `analyzer_name`, `success`, `error_message` | Many-to-one with `scans` |

*Data Flow:* User uploads file → `/scan` controller → generates UUID → writes initial Scan in PostgreSQL → runs analyzers → updates Scan details & inserts Report log → returns data.

---

## 9. Authentication & Authorization

Authentication is **local-only and client-side**. ScamShield doesn't send credentials to the server to establish sessions.

```
[Register Screen] 
  │  validate format & passwords
  ▼
[AuthService.register] 
  │  derive PBKDF2 hash (120k iterations, SHA256, 16-byte random salt)
  ▼
[Write to Secure Storage] 
  │  scamshield_auth_email, scamshield_auth_salt, scamshield_auth_hash
  ▼
[Set Session Flag] 
  │  scamshield_auth_session = "active"
  ▼
[Route to Dashboard]
```

- **Login Flow:** Users input credentials. `AuthService` reads the secure storage salt, computes the PBKDF2 hash of the input password, and executes a **length-constant compare** (`_constantTimeEquals`) to mitigate timing side-channels.
- **Bypass Mode:** Users can click "CONTINUE AS GUEST" to bypass local registration. This allows them to run threat scans anonymously, though local secure storage features like the Safe Vault are not accessible or secured by individual password scopes.
- **Server Admin Auth:** Admin routes (`/dashboard`, `/api/audit-logs`, `/api/stats`) check `Authorization: Bearer <ADMIN_API_KEY>` or header `X-Admin-Key`. The admin key is **required** (no default) — the server refuses to start without `ADMIN_API_KEY`.
- **Client API Auth:** All user-facing endpoints require `X-Device-Token` (per-install, generated on-device) or `X-API-Key`. Controlled by `API_AUTH_ENABLED` (default `true`).

---

## 10. AI / ML / Intelligent Features

ScamShield uses zero custom ML model weights. It acts as an orchestrator combining remote Large Language Models (LLM APIs) with static heuristics:

### 1. Scam Text Analysis (Gemini/Groq)
- **Input:** Raw SMS/text string.
- **Processing:** Concurrently fires:
  - Heuristic Regex & Keyword Matcher (financial terms, urgency keywords, shortened URLs, OTP structures).
  - OSINT checkers (VirusTotal, Google Safe Browsing, AbuseIPDB, WHOIS domain registers).
  - LLM Completion client (calls Gemini or Groq Llama depending on key presence).
- **Model:** Gemini-2.0-flash / Gemini-2.5-flash OR Groq `llama-3.3-70b-versatile` / `llama-3.1-70b-versatile`.
- **Output:** Unified verdict (safe, suspicious, scam), a risk score (0-100), categorization labels, and specific reasons.
- **Where Used:** Renders on Scan screen; saved to SQLite history.

### 2. Audio Transcription (OpenAI Whisper)
- **Input:** Raw audio recording file.
- **Processing:** Reads file and calls Whisper model locally (via CPU/GPU).
- **Model:** OpenAI Whisper `base` model.
- **Output:** Text transcript, which is then piped into the text analysis engine.

### 3. Screenshot Extraction (EasyOCR)
- **Input:** JPEG/PNG/PDF.
- **Processing:** Runs OCR on image layout to extract textual lines.
- **Model:** EasyOCR (supporting English and Hindi character maps).
- **Output:** Raw text, which is analyzed by the text analysis engine.

---

## 11. API & Data Flow

### APK Upload & Analysis Flow
```
User uploads APK
  │
  ▼
App sends POST /scan multipart request
  │
  ▼
FastAPI backend:
 1. Saves APK to /app/uploads/{uuid}.apk
 2. Inserts "pending" Scan row in PostgreSQL
 3. Spawns asyncio.gather concurrent tasks:
    ├─ Androguard: Parse Manifest permissions, metadata, certificates
    ├─ APKTool: Extract structures
    ├─ JADX: Decompile classes.dex
    ├─ MobSF: Trigger remote REST scan API
    └─ OSINT: Check hash on VirusTotal
  │
  ▼
Concurrency task completes:
 1. Run YARA rules match on decompiled files
 2. Run Secrets analyzer on Java source files (extract hardcoded API keys)
 3. Call RiskEngine to calculate risk score (YAML weights)
 4. Call AIExplanationService (Gemini/Groq) to write a summary
  │
  ▼
Complete & Save:
 1. ReportGenerator saves JSON & PDF reports to /app/reports/
 2. Update PostgreSQL row to "completed"
 3. Write execution logs to `scan_logs`
  │
  ▼
SSE Stream pushes event "completed" to frontend
  │
  ▼
App displays full scan report; lets user download PDF report
```

---

## 12. External Services & Integrations

| Service | Purpose | Where Used | Authentication | Data Exchanged |
|---|---|---|---|---|
| **Google Gemini** | LLM message analysis | `gemini_service.py` | `GEMINI_API_KEY` | Text prompt → Scam verdict JSON |
| **Groq (Llama)** | LLM fallback message analysis | `gemini_service.py`, `ai_explanation.py` | `GROQ_API_KEY` (or `gsk_` prefix) | Text prompt → Scam verdict JSON |
| **VirusTotal** | Scan APK hashes & extract URLs | `osint_service.py` | `VIRUSTOTAL_API_KEY` | File SHA256 / URL → malicious votes |
| **Google Safe Browsing** | Verify URLs found in APKs/texts | `osint_service.py` | `GOOGLE_SAFE_BROWSING_API_KEY` | URLs list → threat match status |
| **AbuseIPDB** | Check IP addresses for reports | `backend/app/services/osint_service.py` | `ABUSEIPDB_API_KEY` | IP address → abuse score, country |
| **XposedOrNot** | Lookup leaked emails | `xposedornot.py` | `XPOSEDORNOT_API_KEY` | Email → list of breach leaks |
| **Have I Been Pwned** | Fetch breach catalog & statistics | `breach_service.dart` | `hibp-api-key` (optional) | Free breach database JSON feed |
| **URLhaus** | Client fallback domain checking | `osint_service.dart` | None | URL → malware threat status |
| **MobSF** | Deep mobile app security scanning | `mobsf.py` | `MOBSF_API_KEY` | APK binary → XML/DEX reports |

---

## 13. Configuration & Environment Variables

These variables are defined in the backend environment (`backend/.env` or docker-compose files):

| Variable | Purpose | Required? | Example/Format | Used By |
|---|---|---|---|---|
| **`GEMINI_API_KEY`** | Google Gemini API key | No | `AIzaSy...` (39 chars) | `gemini_service.py` |
| **`GROQ_API_KEY`** | Groq API Key | No | `gsk_...` | `gemini_service.py` |
| **`DATABASE_URL`** | Postgres connection URL | Yes | `postgresql+asyncpg://user:pass@host:5432/db` | `db.py` |
| **`VIRUSTOTAL_API_KEY`** | VirusTotal API v3 Key | No | Hex string | `osint_service.py` |
| **`GOOGLE_SAFE_BROWSING_API_KEY`** | GSB API Key | No | Hex string | `osint_service.py` |
| **`XPOSEDORNOT_API_KEY`** | XposedOrNot API Key | No | Hex string | `xposedornot.py` |
| **`REDIS_URL`** | Redis server connection | Yes | `redis://host:6379` | `progress.py` |
| **`WHISPER_MODEL`** | Whisper model size | No | `tiny` \| `base` \| `small` \| `medium` \| `large` | `voice_service.py` |
| **`MOBSF_URL`** | MobSF local engine URL | No | `http://mobsf:8000` | `mobsf.py` |
| **`MOBSF_API_KEY`** | API authorization key | No | Alphanumeric | `mobsf.py` |
| **`ENABLE_DOCS`** | Enable `/docs`, `/redoc`, `/openapi.json` | No (default `false`) | `true` \| `false` | `main.py` |

> [!WARNING]
> **Required secrets:** `ADMIN_API_KEY`, `POSTGRES_PASSWORD`, and `MOBSF_API_KEY` have **no defaults** — the stack refuses to start without them. There are no hardcoded credentials anywhere in the codebase.

> [!NOTE]
> **Interactive API docs are off by default in production.** `/docs`, `/redoc`
> and `/openapi.json` are only served when `ENABLE_DOCS=true` or `DEBUG=true`.

### Flutter client — production backend URL

The mobile app resolves the backend URL from the `SCAMSHIELD_BACKEND_URL`
build-time define. Debug builds fall back to the local dev server
(`http://10.0.2.2:8000` on the Android emulator), but **release builds require
it and fail fast at startup if it is missing or not `https://`** — matching the
Android release network-security config, which forbids cleartext traffic.

```bash
# Local development (Android emulator → host machine)
flutter run --dart-define=SCAMSHIELD_BACKEND_URL=http://10.0.2.2:8000

# Production
flutter build apk --release \
  --dart-define=SCAMSHIELD_BACKEND_URL=https://your-api.example.com
```

If you forget the define on a release build, the app aborts on launch with a
message showing the exact command to run — it never silently talks to a
localhost server that release networking would block anyway.

---

## 14. Security Audit

### ✅ Implemented Security
- **Salted Password Hashing:** Client uses PBKDF2-HMAC-SHA256 with 120,000 iterations to protect passwords locally.
- **Client-Side Secret-Free Architecture:** Threat APIs (VirusTotal, Google Safe Browsing, Gemini, Groq) are queried exclusively through backend proxy endpoints.
- **Zip-Bomb & Size Guards:** The server enforces a strict limit of 200MB on APK uploads and rejects files without a `.apk` suffix. Client-side zip parsing runs checks to ensure uncompressed files do not exceed extraction size bounds.

### ⚠️ Potential Issues & Trade-offs
- **Strict Encrypted Storage Only:** Safe Vault relies strictly on hardware keystore (`FlutterSecureStorage` with EncryptedSharedPreferences). If encryption fails or the keystore is locked, writes fail securely with user guidance rather than writing unencrypted fallback data.
- **`create_all()` on startup:** The backend creates tables via SQLAlchemy `create_all()` on boot (fine for dev). Production schema changes should move to Alembic migrations.
- **Sentry Crash Reporting:** Sentry initialization is active in `main.dart` when `SENTRY_DSN` is supplied at build time via `--dart-define=SENTRY_DSN=...` with privacy-preserving defaults.
- **No Flutter patch-level intelligence:** The SIM/device screen shows security patch level but does not map it to known-vulnerability data.
- **Cleartext HTTP permitted:** `usesCleartextTraffic="true"` is enabled inside the Android Manifest, which allows unencrypted HTTP connections. While useful for local development (`10.0.2.2:8000`), it poses a risk of Man-in-the-Middle (MitM) attacks if left enabled in production.

---

## 15. Error Handling & Reliability

- **Graceful Downstream Degradation:** If API connections to Gemini or Groq fail or time out, `ai_engine.py` adjusts weights automatically:
  - *Standard:* `(gemini * 0.55) + (heuristic * 0.30) + (osint * 0.15)`.
  - *Degraded:* `(heuristic * 0.80) + (osint * 0.20)`.
- **Client Offline Resilience:** The app detects network failures via the `connectivity_plus` package. If the server is unreachable, `ScannerService` switches to local parsing isolates and uses the client-side `ScamDetector` heuristic engine.
- **OSINT Fail-safe:** If Google Safe Browsing keys are missing or the API fails, the service falls back to **URLhaus**, a public keyless malware check.

---

## 16. Testing

### 1. Test Suite (Backend)
Located in `backend/tests/` (run with pytest from `backend/`):
- `tests/unit/` — heuristic engine, text utils, risk engine, AI engine.
- `tests/api/` — endpoint behaviour, including `test_auth.py` (401 without device token, scan ownership isolation).
- `tests/integration/` — full pipeline.
- `tests/performance/` — latency/throughput benchmarks + a labelled detection-accuracy benchmark against `dataset/*.csv`.

### 2. Test Suite (Flutter)
```bash
flutter test
```

---

## 17. Build & Run Instructions

### 1. Prerequisites
- **Flutter SDK** (`3.11.4` or compatible)
- **Python** (`3.12`)
- **Docker & Compose** (required for PostgreSQL, Redis, and MobSF)

### 2. Backend Stack Setup (Docker Compose)
To launch the database, caching layer, MobSF, and dependencies:
```bash
cd backend/docker
docker compose up -d
```

### 3. Run FastAPI Backend locally
To run the primary API service:
```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env with your keys
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### 4. Build and Run Flutter Application
```bash
# Install dependencies
flutter pub get

# Launch on Android emulator or connected device
flutter run
```

---

## 18. Deployment

- **Containerization:** A multi-stage `Dockerfile` is located in `backend/docker/Dockerfile`. It compiles runtime binaries, installs dependencies (`default-jre-headless`, `yara`, `apktool`, `jadx`), creates a non-root system user (`scamshield`), and exposes port 8000.
- **Compose Stack:** `backend/docker/docker-compose.yml` mounts Postgres (with persistent volumes), Redis, MobSF, and the FastAPI application.
- **CI Pipeline:** `.github/workflows/ci.yml` runs static analysis and tests for backend and frontend code on PRs and commits.

---

## 19. User Journeys

### Journey 1: Paste Text Message for Scam Check
1. User copies a suspicious text message from an SMS client.
2. User opens ScamShield (or clicks **SCAN NOW** on the clipboard detection snackbar).
3. User pastes the text into the Threat Scanner and taps **ANALYZE FOR THREATS**.
4. The app sends a request to `/analyze` on the backend.
5. The backend aggregates analysis from the LLM, regex heuristics, and OSINT.
6. The app displays the risk score and a checklist of warning signs.
7. The scan result is saved to the user's local SQLite history.

### Journey 2: Deep Scan an APK File
1. User downloads an APK from a web browser.
2. User navigates to the **APK Scan** screen in the app.
3. User selects the downloaded `.apk` file.
4. The app uploads the file to the backend `/scan` endpoint.
5. The UI displays real-time progress steps via SSE.
6. The backend runs static decompilation, YARA signature matching, secrets scanning, and optional MobSF scans.
7. The user reviews the detailed security report and downloads a generated PDF audit report.

---

## 20. Feature → Code Mapping

| Feature | Frontend | Backend | Database | External Service |
|---|---|---|---|---|
| **Text Scan** | `scan_screen.dart`, `api_service.dart` | `backend/app/api/v1/analyze.py` | Local SQLite | Gemini / Groq |
| **APK Scan** | `apk_scan_screen.dart`, `scanner_service.dart` | `backend/app/routes/scan.py` | Postgres | VT, MobSF, Safe Browsing |
| **Email Breach** | `breach_screen.dart`, `breach_service.dart` | `backend/app/api/v1/breach.py` | None | XposedOrNot |
| **Safe Vault** | `safe_vault_screen.dart` | None | Secure Storage / SharedPrefs | None |
| **Device Integrity** | `sim_lock_screen.dart` | None | None | Android Security APIs |
| **Local Auth** | `login_screen.dart`, `auth_service.dart` | None | Secure Storage | None |

---

## 21. Important Files

| File | Why It Matters |
|---|---|
| 1. [lib/main.dart](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/lib/main.dart) | Application bootstrapper, navigation structure, and clipboard monitoring. |
| 2. [lib/services/auth_service.dart](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/lib/services/auth_service.dart) | Client-side account manager using PBKDF2 cryptography. |
| 3. [lib/services/apk_analyzer_service.dart](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/lib/services/apk_analyzer_service.dart) | Local APK extraction engine running in a background Dart Isolate. |
| 4. [lib/services/api_service.dart](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/lib/services/api_service.dart) | Handles communications with the FastAPI backend. |
| 5. [lib/data/database/database_helper.dart](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/lib/data/database/database_helper.dart) | Defines SQLite tables and schema versioning. |
| 6. [backend/app/main.py](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/backend/app/main.py) | FastAPI entry point, lifespan, CORS, and middleware definitions. |
| 7. [backend/app/core/config.py](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/backend/app/core/config.py) | Pydantic configuration file for validation and env loading. |
| 8. [backend/app/services/ai_engine.py](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/backend/app/services/ai_engine.py) | Orchestration service for threat scoring. |
| 9. [backend/app/routes/scan.py](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/backend/app/routes/scan.py) | Upload handler and pipeline manager for APK scans. |
| 10. [backend/app/services/risk_engine.py](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/backend/app/services/risk_engine.py) | Computes risk scores based on static analysis findings. |
| 11. [backend/app/analyzers/secrets_analyzer.py](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/backend/app/analyzers/secrets_analyzer.py) | Scanning rules for hardcoded keys (AWS, Google, OpenAI). |
| 12. [backend/app/analyzers/yara_analyzer.py](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/backend/app/analyzers/yara_analyzer.py) | Compiles and matches YARA signature rules. |
| 13. [backend/docker/docker-compose.yml](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/backend/docker/docker-compose.yml) | Orchestrates the primary backend container services. |
| 14. [backend/app/services/audit.py](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/backend/app/services/audit.py) | Privacy-preserving audit logger (fingerprints only). |
| 15. [backend/app/middleware/api_auth.py](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/backend/app/middleware/api_auth.py) | Client + admin authentication dependencies. |

---

## 22. Dependencies

### Flutter (`pubspec.yaml`)
- `sqflite`: Local SQLite database.
- `flutter_secure_storage`: Local secure storage.
- `crypto`: Used for PBKDF2 hashing.
- `file_picker`: Opens file explorer dialogues.
- `archive`: Decodes APK ZIP structures on-device.
- `device_info_plus`: Gathers model attributes.

### Backend (`backend/requirements.txt`)
- `fastapi`, `uvicorn`, `pydantic-settings`: Framework and configuration.
- `google-genai`: Official SDK for Gemini API integration.
- `androguard`: APK structure, certificate, and manifest parser.
- `yara-python`: Executes matches on compiled YARA rules.
- `reportlab`: Compiles binary PDF documents.
- `slowapi`: Integrates rate-limiting checks.
- `sqlalchemy`, `asyncpg`: Async PostgreSQL integration.

---

## 23. Current Implementation Status

- ✅ **Fully Implemented:** Local PBKDF2 authentication, local SQLite history, text scanning UI/fallback, local APK decompilation isolate, custom YARA compiler, Groq API completion integrations.
- 🟡 **Partially Implemented:** Local Whisper transcription and EasyOCR (require system libraries to be installed), MobSF analyzer (requires running MobSF container), HIBP email leak scanner (requires an active HIBP subscription API key).
- 🔴 **Missing / Unused:** Server-side user registration (schema declared but not used by app), production HTTPS/SSL configurations.

---

## 24. Known Issues & Technical Debt

- **Safe Vault Storage Fallback:** If secure storage fails, data is written in plain JSON to `SharedPreferences` without encryption.
- **Structural hash ≠ fuzzy similarity:** The DEX structural fingerprint is an exact SHA-256; variant detection needs TLSH/feature-vector similarity (roadmap).
- **API-string detection is a signal, not proof:** Capability indicators from DEX strings must be combined with permissions + manifest + behavioral context before making strong claims.

---

## 25. Performance & Scalability

- **Concurrency:** `ai_engine.py` executes Gemini and OSINT concurrently via `asyncio.create_task`. Static APK scanning runs in parallel using `asyncio.gather`.
- **CPU Bottlenecks:** Local execution of Whisper (audio) and EasyOCR (image) is resource-intensive on CPU-only containers. They are lazy-loaded to optimize startup times.
- **Database Caching:** OSINT checks are cached using a simple TTL cache (3600 seconds) in `osint_service.py` to prevent redundant external API calls.

---

## 26. Complete System Summary

When a user triggers a text scan in ScamShield:
1. The Flutter UI POSTs the text payload to `/analyze`.
2. The FastAPI backend orchestrator (`ai_engine.py`) parses the request.
3. It concurrently invokes:
   - Remote LLM completion (Gemini or Groq Llama depending on credentials).
   - Regex-based heuristics for urgency, financial terms, and link structures.
   - OSINT validation for malicious URLs, domain age, and IP ratings.
4. The engines compute a weighted score. If VirusTotal flags malicious URLs, the classification is overridden to `scam`.
5. The backend returns a unified `AnalysisResult` JSON.
6. The app displays the risk score and list of matches, and writes the result to the local SQLite database.

---

## 27. Developer Quick Reference

- **Frontend Entry:** `lib/main.dart`
- **Backend Entry:** `backend/app/main.py`
- **Main API URL:** `http://10.0.2.2:8000` (Android emulator)
- **Local DB:** `scamshield.db` (SQLite)
- **Local Config Files:** `backend/.env`
- **Commands:**
  - *Start Compose:* `docker compose -f backend/docker/docker-compose.yml up -d`
  - *Start local backend:* `uvicorn app.main:app --port 8000 --reload`
  - *Run backend test suite:* `cd backend && python -m pytest tests/unit tests/api tests/integration -q`
  - *Start Flutter app:* `flutter run`