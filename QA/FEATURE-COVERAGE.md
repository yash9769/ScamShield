# ScamShield — Feature Coverage & Codebase Discovery

## 1. Executive Architecture Mapping

| Layer | Technology | Primary Files / Components | Status |
| :--- | :--- | :--- | :--- |
| **Mobile App (Frontend)** | Flutter 3.x / Dart | `lib/main.dart`, `lib/screens/*`, `lib/services/*` | IMPLEMENTED |
| **Android Native Layer** | Kotlin / MethodChannel | `android/app/src/main/kotlin/com/example/scamshield/MainActivity.kt` | IMPLEMENTED |
| **Backend Server** | Python 3.9 / FastAPI | `server/main.py`, `server/test_all_endpoints.py` | IMPLEMENTED |
| **Static Analysis Engines**| Androguard & YARA | `androguard` (Python module), `server/yara_rules/sample_rules.yar` | IMPLEMENTED |
| **Threat Intelligence** | OSINT APIs | VirusTotal v3, Google Safe Browsing v4, AbuseIPDB v2 | IMPLEMENTED |
| **Database & Audit** | SQLite | `server/server_audit.db` (`audit_logs` table), Flutter SQLite (`scan_history`) | IMPLEMENTED |
| **Web SOC Dashboard** | HTML5 / JavaScript | `server/static/dashboard.html` (`GET /dashboard`) | IMPLEMENTED |
| **Localization Engine** | Custom i18n | `lib/services/localization_service.dart` (EN, HI, ES, FR) | IMPLEMENTED |

---

## 2. Component Inventory & Audit Target Summary

### A. Backend API & Engine (`server/main.py`)
- **Endpoints**:
  - `GET /` : System info & engine availability flags.
  - `GET /health` : Liveness check.
  - `GET /stats` : Telemetry, cache count, and audit event metrics.
  - `POST /analyze` : Text scam & phishing analysis.
  - `POST /analyze-voice` : Audio note scam analysis.
  - `POST /analyze-image` : Screenshot OCR text scam analysis.
  - `POST /scan` : Full APK static analysis (Androguard + YARA + OSINT).
  - `POST /scan-batch` : Multi-APK parallel batch scanning.
  - `GET /dashboard` : Web SOC threat portal HTML.
  - `GET /api/audit-logs` : Real-time security audit log stream.
  - `GET /osint/hash/{file_hash}` : VirusTotal SHA-256 lookup.
  - `POST /osint/urls` : Google Safe Browsing URL threat check.
  - `GET /osint/ip/{ip}` : AbuseIPDB IP reputation lookup.

### B. Mobile UI & Services (`lib/`)
- **Screens**:
  - `home_screen.dart` : Threat dashboard & dynamic scan counters.
  - `scan_screen.dart` : Multimodal scanner (SMS/Text, URL/Link, Voice Note, Screenshot OCR).
  - `apk_scan_screen.dart` : APK upload & PDF report generator.
  - `history_screen.dart` : Filterable scan history with SQLite backing.
  - `sim_lock_screen.dart` : Hardware SIM guard & Native MethodChannel root posture auditor.
- **Services**:
  - `api_service.dart` : Backend HTTP client wrapper.
  - `localization_service.dart` : Multi-language translation engine.
  - `permission_service.dart` : Android permission handler.

---

## 3. Adversarial Test Scope & Environment Matrix

- **Server Environment**: macOS Darwin ARM64, Python 3.9, Uvicorn, FastAPI.
- **Emulator Environment**: Android SDK `emulator-5554` (gphone64 arm64, API 36).
- **Physical Device**: Not attached in current workspace environment (Noted for certification).
