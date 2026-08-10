# ScamShield System Architecture

This document describes the architectural layout of the ScamShield system, detailing the components, data flows, and security design patterns used across the Flutter application and the backend services.

---

## 1. System Topology

ScamShield follows a client-server architecture:

```mermaid
graph TD
    Client[Flutter Mobile App]
    Server[Active FastAPI Server (server/)]
    DormantServer[Dormant Backend (backend/)]
    
    VT[VirusTotal API]
    GSB[Google Safe Browsing]
    AbuseIP[AbuseIPDB API]
    HIBP[Have I Been Pwned]

    Client -- HTTP Requests --> Server
    Server -- API Lookups --> VT
    Server -- API Lookups --> GSB
    Server -- API Lookups --> AbuseIP
    Server -- API Lookups --> HIBP
    
    style Server fill:#1e293b,stroke:#0f766e,stroke-width:2px,color:#fff
    style DormantServer fill:#0f172a,stroke:#334155,stroke-dasharray: 5 5,color:#94a3b8
```

- **Client (Flutter)**: Handles the user interface, secure local credential storage (Safe Vault), native Android device integrity checks, and clipboard scans.
- **Server (Active FastAPI)**: Stateless API gateway that compiles YARA rules, scans APK files, performs OSINT reputation lookups, and parses breach records.
- **Dormant Backend (backend/)**: Deprecated/Dormant codebase containing modular routers, Celery async task queue setups, and database models. **It is not active in production.**

---

## 2. Component Audits & Responsibilities

### 2.1. Active Server: `server/`
The active server code is located in the `server/` directory and runs on port `8000`. Its main entry point is `server/main.py`.

- **Responsibilities**:
  - `/analyze`: Scans text messages using Gemini/Groq LLMs or fallbacks on local YARA heuristic rules.
  - `/scan`: Accepts uploaded APK files, validates entries, runs YARA rules, and outputs file scanning results.
  - `/osint/hash/{file_hash}`: Proxies file hash checking to VirusTotal.
  - `/osint/urls`: Proxies list of URLs to Google Safe Browsing.
  - `/osint/ip/{ip}`: Proxies IP reputation checks to AbuseIPDB.
  - `/api/v1/breach`: Proxies email checks to XposedOrNot.
  - `/dashboard` & `/api/audit-logs`: Admin audit portal backed by a local SQLite database (`server_audit.db`).
- **Tests**: Monitored by `server/test_server.py`.

### 2.2. Dormant Backend: `backend/`
The code inside the `backend/` folder represents a heavier, stateful application architecture that was designed to support asynchronous task queues but was never fully integrated.

- **Responsibilities**:
  - Relational database management using SQLAlchemy and alembic migrations.
  - Asynchronous background tasks (decompilation via MobSF, OCR scanning, transcription) utilizing Celery and Redis.
- **Current Status**: **Dormant**. Do not run in production.

---

## 3. Core Security & Privacy Controls

### 3.1. Secrets Management
- Production credentials and API keys (such as `ADMIN_API_KEY`, `VIRUSTOTAL_API_KEY`, `GOOGLE_SAFE_BROWSING_KEY`, etc.) are resolved strictly from environment variables.
- If `ADMIN_API_KEY` is not provided in a non-testing production environment, the server will raise a `ValueError` and fail to start.

### 3.2. Safe Vault Fail-Closed Design
- The Safe Vault screen (`lib/screens/safe_vault_screen.dart`) uses `FlutterSecureStorage` (keychain/keystore) to encrypt user credentials on-disk.
- It contains **no fallbacks** to unencrypted storage (like `SharedPreferences`). If secure storage read/write operations fail, it raises a user-facing error dialog and cancels the operation (fails closed).

### 3.3. APK Analysis Hardening
- **Subprocess Isolation**: Subprocesses launched during decompilation (e.g. `apktool` and `jadx`) have a strict `timeout=60` execution limit to prevent hung processes from exhausting server threads.
- **Decompression Guard (Zip Bomb Prevention)**: Zip files uploaded for static analysis are checked for maximum uncompressed file sizes (`100 MB` total, `15 MB` per file), maximum entry counts (`10,000`), and path traversals (`..` file names).
- **Temporary Storage Cleanup**: Decompiled and extracted files are placed in isolated directories and completely removed using `shutil.rmtree` in a `finally` block once the analysis completes.

### 3.4. Clipboard Privacy
- The system clipboard is only accessed when the user's `autoScanClipboard` setting is explicitly enabled in Settings/Profile. If disabled, the client returns immediately without querying the clipboard.

---

## 4. Backend Migration Roadmap

If the ScamShield backend needs to support relational database persistence or asynchronous task processing in the future:
1. Port stateless routers from `server/main.py` directly into `backend/app/api/v1/endpoints/`.
2. Configure environment variable injection for PostgreSQL and Redis in `backend/app/core/config.py`.
3. Switch the deployment scripts to target `backend/app/main.py` instead of `server/main.py`.
4. Run python database migrations using `alembic upgrade head`.
