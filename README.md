# ScamShield

> **Status note (read first):** This repository contains **two separate Python backends** plus a Flutter mobile app. They are described honestly below based on what the code actually does — not on optimistic marketing copy. Where the shipped frontend wiring and the backend route definitions disagree, the actual implementation is treated as the source of truth and the discrepancy is called out.

---

## 1. Project Overview

**Project name:** ScamShield

**What it does:** ScamShield is a mobile-first consumer security app (Flutter) that helps everyday users detect scams, phishing, malicious Android apps, and data-breach exposure. Users paste a suspicious SMS/link, attach a voice note or screenshot, upload an APK file, or look up an email — and the app returns a plain-English risk verdict with a score and the reasons behind it.

**Problem it solves:** Scam/phishing/fraud targeting Indian and global consumers (OTP fraud, UPI scams, fake delivery/courier messages, malicious APKs, credential leaks) is widespread. Most victims lack tooling to evaluate a message or app before acting. ScamShield gives a non-expert a fast, explainable verdict.

**Target users:** Mobile users (currently Android-targeted) who receive suspicious messages, install APK files outside Play Store, or want to know if their email was breached.

**Main purpose:** Turn threat intelligence + AI + static malware analysis into an app a normal person can use in seconds.

**Core value proposition:** "Paste it / upload it / look it up → get an explainable safe/suspicious/scam verdict, with no security expertise required."

**Current project status:** 🟡 **Multi-stage / partially integrated.** The Flutter app and the `backend/` FastAPI service are functionally connected and runnable. The `server/` directory is a *second, parallel* backend (described as "v3.0") that overlaps in purpose with `backend/` ("v2.0"). The frontend codebase references **both** backends:
- Text / voice / image / breach lookups → `backend/app` FastAPI on port `8000`.
- APK scan → `scanner_service.dart` calls `POST /scan` which exists in `backend/app/routes/scan.py` **and** in `server/main.py`, but the Dart code points at the port-8000 host (`http://10.0.2.2:8000` / `http://localhost:8000`), i.e. whatever is actually serving there.
- Several advanced integrations (MobSF, PostgreSQL, Redis) are wired but require external services to be running to fully work; without them the code degrades gracefully (heuristic-only / on-device fallback).
- Gemini / Groq LLMs are supported. Groq is accessed natively using lightweight `httpx` completions calls to avoid adding SDK weight, routing automatically if `GROQ_API_KEY` is present or if `GEMINI_API_KEY` starts with the `gsk_` prefix.

---

## 2. Key Features

Features are grouped by category. Status values: ✅ implemented, 🟡 partially / depends on external service, 🔵 mocked-or-degraded fallback, 🔴 missing/broken.

### Core features
| Feature | Description | Status |
|---|---|---|
| **Text/sms/links threat scan** | Paste message/link → verdict + score + reasons. Calls `POST /analyze`. | ✅ |
| **Voice note scan** | Upload audio → Whisper transcription + analysis. | 🟡 (backend calls Whisper only if `openai-whisper` installed; otherwise returns heuristic text) |
| **Screenshot / image OCR scan** | Upload image → EasyOCR + analysis. | 🟡 (backend requires EasyOCR; Flutter falls back to a canned text on OCR failure) |
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
| **Audit logging** (server SQLite) | `server` writes `audit_logs`. | ✅ (server only) |

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
| **Zip-bomb / size guards** (server APK + on-device) | Size + entry-count limits. | ✅ |

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
| **Python 3.12** | Backend language | `backend/`, `server/` | API + analysis. |
| **FastAPI** | Web framework | `backend/app/main.py`, `backend/app/api/` | Async REST API (v2). |
| **Flask-style FastAPI** | Web framework | `server/main.py` | *Second* parallel API (v3) with SQLite audit. |
| **Uvicorn** | ASGI server | both backends | Serve the API. |
| **Pydantic / pydantic-settings** | Validation/config | both | Request/response models + env config. |
| **SQLAlchemy 2 (async)** | ORM | `backend/app/core/db.py`, `models/schema.py` | Postgres access for scans/reports. |
| **asyncpg / psycopg** | Postgres driver | `backend/requirements.txt` | Async Postgres. |
| **SQLite3 (stdlib)** | Audit DB | `server/main.py` | `server_audit.db` log store. |
| **Redis (redis.asyncio)** | Cache/stream | `backend/app/services/progress.py`, `osint` | Scan progress SSE + OSINT cache. |
| **slowapi** | Rate limiting | both | Per-route limits. |
| **google-genai** | LLM SDK | `gemini_service.py`, `server/main.py` | Gemini 2.0/2.5 calls. |
| **Groq (OpenAI-compat httpx)** | LLM SDK | `gemini_service.py`, `ai_explanation.py`, `server/main.py` | Llama models as alternative AI. |
| **openai-whisper** | Speech-to-text | `backend/app/services/voice_service.py` | Audio transcription. |
| **EasyOCR + pdf2image** | OCR | `backend/app/services/ocr_service.py` | Image/screenshot→text. |
| **python-whois** | OSINT | `backend/app/services/osint_service.py` | Domain age check. |
| **Androguard** | APK analysis | `backend/app/analyzers/`, `server/main.py` | Manifest/permission/cert parsing. |
| **yara-python** | Signature match | `backend/app/analyzers/yara_analyzer.py`, `server/main.py` | Malware rule matching. |
| **ApkTool / JADX (binaries)** | Decompile | `backend/app/routes/scan.py` (subprocess) | Resource/DEX extraction. |
| **MobSF (container)** | Mobile security | `backend/app/services/mobsf.py` | Full APK scan via API. |
| **ReportLab** | PDF (server) | `backend/app/reports/generator.py` | Server-side PDF reports. |
| **httpx** | HTTP client | both backends | Outbound API calls. |
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

> **Discrepancy flag:** `server/main.py` (the "v3.0" API) also defines `/analyze`, `/scan`, `/breach`, `/osint/*` and a SQLite audit DB, and is what `server/requirements.txt` + CI test (`test_server.py`) target. The Flutter app's `ApiService`/`OsintService`/`BreachService` call the *port-8000* host, which can be served by **either** `backend/app` or `server`. In this repo the two backends are not unified; pick one to run. The README documents `backend/app` as the primary (it matches the documented weighted-score engine and Docker stack).

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
├── backend/                  # PRIMARY FastAPI backend (v2.0)
│   ├── app/
│   │   ├── main.py           # App factory, lifespan (create tables), middleware
│   │   ├── api/v1/           # analyze, voice, image, batch, breach, router, health
│   │   ├── routes/scan.py     # POST /scan APK pipeline + SSE progress
│   │   ├── services/         # ai_engine, gemini, heuristic, ocr, voice, osint,
│   │   │                     #   osint_service, mobsf, xposedornot, ai_explanation,
│   │   │                     #   risk_engine, progress
│   │   ├── analyzers/        # androguard, apktool, jadx, yara, secrets
│   │   ├── models/           # schema (SQLAlchemy), enums, base
│   │   ├── schemas/          # pydantic request/response
│   │   ├── core/             # config, db, logging, exceptions
│   │   ├── middleware/       # error_handler, rate_limit, security_headers
│   │   ├── reports/          # generator (PDF/JSON)
│   │   └── utils/            # file_utils, text_utils
│   ├── docker/               # Dockerfile + docker-compose.yml
│   ├── tests/                # pytest unit/integration/performance
│   ├── yara_rules/           # sample_rules.yar
│   ├── config/risk_weights.yaml (referenced; expected at /app/app/config)
│   ├── requirements.txt
│   └── .env.example
├── server/                   # SECOND parallel FastAPI API (v3.0) + SQLite audit
│   ├── main.py               # endpoints + audit DB
│   ├── requirements.txt
│   ├── static/dashboard.html # admin dashboard
│   ├── yara_rules/
│   └── test_*.py             # pytest suite (CI target)
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
| **POST** | `/analyze` | Analyze text message for scams | `TextAnalysisRequest` | `AnalysisResult` | None (Rate limited: 60/min) |
| **POST** | `/analyze-voice` | Transcribe + scan audio file | multipart file | `VoiceAnalysisResponse` | None (Rate limited: 10/min) |
| **POST** | `/analyze-image` | OCR extract + scan image/PDF | multipart file | `ImageAnalysisResponse` | None (Rate limited: 10/min) |
| **POST** | `/analyze-batch` | Batch process multiple texts | `BatchAnalysisRequest` | `BatchAnalysisResponse` | None (Rate limited: 20/min) |
| **GET** | `/breach` | Lookup email exposure | query `?email=` | `BreachResponse` | None (Rate limited: 30/min) |
| **POST** | `/scan` | Upload & run full APK analysis | multipart file | full scan JSON | None |
| **GET** | `/scan/{id}` | Read generated report | path variable | report JSON | None |
| **GET** | `/scan/{id}/progress` | Real-time SSE progress events | path variable | SSE Stream (`text/event-stream`) | None |
| **DELETE**| `/scan/{id}` | Delete report and uploaded APK | path variable | `{"status": "deleted"}` | None |
| **GET** | `/history` | Read server scan history | None | `{"history": [...]}` | None |
| **GET** | `/health` | Check backend & downstream health | None | `{"status": "ok"}` | None |

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
- **Bypass Mode:** Users can click "Continue without an account" to bypass local registration. This allows them to run threat scans anonymously, though local secure storage features like the Safe Vault are not accessible or secured by individual password scopes.
- **Server Admin Auth:** Legacy dashboard routes in `/server` check for `Authorization: Bearer <ADMIN_API_KEY>` or header `X-Admin-Key`. Default key is `scamshield_admin_sec_key_2026`.

### Google Sign-In (optional provider)

Google can be used instead of a password. Because there is no ScamShield user
backend, Google acts purely as an **identity provider for the local account**:
the verified email/name/avatar are stored on-device by `AuthService` exactly as
a password account is, and no ID token is transmitted anywhere.

`AuthService.currentProvider()` records which route was used, because the two
re-authenticate differently — deleting a Google account re-verifies through
Google (and requires the returned address to match), since there is no password
to re-enter.

**This requires your own Google Cloud credentials and cannot ship pre-configured:**

1. Google Cloud Console → APIs & Services → Credentials.
2. Create an **Android** OAuth client: package name `com.example.scamshield`
   (see `android/app/build.gradle.kts`) plus the SHA-1 of your signing key
   (`cd android && ./gradlew signingReport`). Add the debug key too, or sign-in
   works in release but fails in debug.
3. Create a **Web application** OAuth client — its client ID is the
   "server client ID" the Android SDK needs to return an ID token.
4. Pass it at build time:

   ```bash
   flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
   ```

Until step 4 is done, `GoogleAuthService.isConfigured` is false and the auth
screens hide the Google button rather than showing a control that always fails.

> Before publishing, replace the placeholder mark in
> `lib/widgets/google_sign_in_button.dart` with Google's official logo asset —
> their Sign-In branding guidelines require it.

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
| **AbuseIPDB** | Check IP addresses for reports | `server/main.py` | `ABUSEIPDB_API_KEY` | IP address → abuse score, country |
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

> [!WARNING]
> **Exposed Key Warning:** The legacy server file `server/main.py` contains a default hardcoded admin auth credential: `ADMIN_API_KEY = "scamshield_admin_sec_key_2026"`. Do not deploy the legacy server with this key unchanged.

### Accounts server (`server/accounts.py`)

| Variable | Purpose | Required? | Notes |
|---|---|---|---|
| **`SESSION_SECRET_KEY`** | Signs session tokens | **Yes in production** | Without it an ephemeral key is generated per process, so every session is invalidated on restart. |
| **`GOOGLE_SERVER_CLIENT_ID`** | Web OAuth client ID the app's Google ID tokens are issued for | Only for Google sign-in | The audience check against this value is what stops `POST /account/google` accepting any email a caller types. |
| **`FCM_SERVICE_ACCOUNT_FILE`** | Path to a Firebase service-account JSON | No | Enables push delivery of family alerts. Unset = alerts are still recorded and still shown, just not pushed. |

### Enabling push notifications for family alerts (optional)

Push is off by default on both sides and each side fails soft, so you can set up
one, both, or neither:

1. **App side.** Create a Firebase project, register the Android app under the
   applicationId in `android/app/build.gradle.kts`, and drop the generated
   `google-services.json` into `android/app/`. That is the whole setup: the
   Gradle plugin is applied only when that file exists (see the comment in
   `android/app/build.gradle.kts`), so a clone without it builds and runs
   normally and `PushNotificationService` reports itself unavailable.
2. **Server side.** Generate a service-account key for the same Firebase
   project and point `FCM_SERVICE_ACCOUNT_FILE` at it. Note that the legacy
   FCM server-key API was shut down in 2024, so there is no keyless path —
   `_dispatch_family_push()` mints an OAuth2 token from this file and calls the
   FCM HTTP v1 API. Also install `google-auth`; it is imported lazily, so the
   module runs fine without it when push is unconfigured.

Push never carries the scanned content — only the verdict, the risk score and
who raised it. The alert row on the server remains the source of truth; a push
that fails to send is logged and dropped rather than failing the alert.

---

## 14. Security Audit

### ✅ Implemented Security
- **Salted Password Hashing:** Client uses PBKDF2-HMAC-SHA256 with 120,000 iterations to protect passwords locally.
- **Client-Side Secret-Free Architecture:** Threat APIs (VirusTotal, Google Safe Browsing, Gemini, Groq) are queried exclusively through backend proxy endpoints.
- **Zip-Bomb & Size Guards:** The server enforces a strict limit of 200MB on APK uploads and rejects files without a `.apk` suffix. Client-side zip parsing runs checks to ensure uncompressed files do not exceed extraction size bounds.

### ⚠️ Potential Issues
- **Safe Vault Plaintext Fallback:** In `safe_vault_screen.dart`, if `FlutterSecureStorage` throws an exception, notes are written to unencrypted `SharedPreferences` as plain JSON under the key `scamshield_vault_notes`.
- **Stateless Analysis Exposure:** Backend analysis endpoints (`/analyze`, `/scan`) do not verify auth headers. They are open to anonymous invocation if the port is exposed without a firewall or API gateway.
- **Typo in Android Manifest:** The Android package label is configured as `"SScamSShield"` inside `AndroidManifest.xml` (line 12).
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

### 1. Test Suite (Server)
Located in `server/`, targeting `server/main.py`:
- `test_server.py`: Checks `/analyze`, `/scan`, `/breach`, and `/osint` endpoints. Runs via `pytest`.
- `test_security_remediation.py`: Tests key redaction and sanitization in log outputs.
- `test_adversarial_qa.py`: Evaluates endpoint robustness against malicious payloads and injection attacks.

### 2. Test Suite (Backend)
Located in `backend/tests/`:
- `run_unit_tests.py`: Launcher script for backend unit tests.

### Running Tests
```bash
# Test the legacy server
cd server
pytest test_server.py

# Test Flutter components
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
| 14. [server/main.py](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/server/main.py) | Monolithic legacy API server containing built-in audit logs. |
| 15. [server/verify_api_services.py](file:///Users/yashodhanrajapkar/Downloads/ScamShield%202/server/verify_api_services.py) | Diagnostics suite for verifying third-party API configurations. |

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

- **Duplicated Backends:** Both `backend/app/` and `server/` implement text scans, APK scans, and OSINT endpoints independently. They need to be consolidated.
- **Safe Vault Storage Fallback:** If secure storage fails, data is written in plain JSON to `SharedPreferences` without encryption.
- **Hardcoded Admin Key:** The legacy server has a hardcoded admin key: `ADMIN_API_KEY = "scamshield_admin_sec_key_2026"`.
- **Manifest Typo:** The app's package label in `AndroidManifest.xml` is misspelled as `"SScamSShield"`.
- **Real-Time SMS Protection and Google Play policy:** `RECEIVE_SMS`/`READ_SMS` are covered by Play Store's restricted "SMS and Call Log" permissions policy. Google generally only approves this for apps that are set as the **default SMS or Dialer handler**, or that qualify for a narrow declared-use exception. A scam-detection feature that is *not* the default SMS app is unlikely to be approved as-is, and Google requires an in-app disclosure plus a Play Console permissions declaration form before submission. Before shipping this feature: either (a) apply for the exception with a clear justification and required in-app disclosure, or (b) gate it as a Play Store-excluded build variant / sideload-only feature, or (c) replace it with Android's [SMS Retriever API](https://developers.google.com/identity/sms-retriever/overview), which reads OTP-style messages without the dangerous permission at all (but only messages containing the app's signing hash, so it cannot screen arbitrary incoming SMS). This is a real submission risk, not a hypothetical one — confirm your compliance path before release.
- **Scam Call Screening and Google Play policy:** unlike SMS screening above, this one has a clean compliance story and is worth understanding as the contrast. `CallScreeningServiceImpl` uses Android 10's `ROLE_CALL_SCREENING`, which the Android documentation states "eliminates the requirement to obtain the `READ_CALL_LOG` permission" — so the app declares **no** restricted call-log permission at all, and the feature is gated to API 29+ rather than taking the pre-10 route of replacing the user's dialer. What it does need is the user granting the role through a system dialog, which only one app on the device can hold. Two consequences worth knowing before shipping: (a) granting the role displaces whatever screening app the user had, so the in-app explanation must be honest about that, and (b) an app **cannot revoke a role it holds** — turning the feature off in Profile stops the screening (the service checks the flag first thing) but Android still lists ScamShield as the screening app until the user changes it in system settings. The Profile toggle says so and links there.
- **Call screening never blocks a call.** `CallScreeningServiceImpl` always responds with `setDisallowCall(false)`. This is a deliberate asymmetry-of-harm decision, not an unfinished feature: a wrongly blocked call can be a hospital or a bank's genuine fraud desk, while a wrongly allowed one still meets every other defence in the app. Silencing the ringer is offered separately, off by default, and only ever for numbers on the device's own local list — never on a community verdict.

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
- **Local Config Files:** `backend/.env` and `server/.env`
- **Commands:**
  - *Start Compose:* `docker compose -f backend/docker/docker-compose.yml up -d`
  - *Start local backend:* `uvicorn app.main:app --port 8000 --reload`
  - *Run test suite:* `pytest server/test_server.py`
  - *Start Flutter app:* `flutter run`
