# ScamShield 🛡️

**ScamShield** is a comprehensive, production-ready Mobile Application Security Platform. It combines a mobile-first Flutter UI with a powerful FastAPI backend that orchestrates industry-standard reverse engineering tools to provide deep, explainable analysis of Android APKs.

---

## Features

### 🔍 Deep APK Analysis
- Decompilation & Resource Extraction (APKTool, JADX)
- Static Analysis (Androguard, MobSF)
- Threat Intelligence Correlation (VirusTotal, Google Safe Browsing, AbuseIPDB)
- Signature & Secrets Detection (YARA)

### 🧠 Explainable AI & Risk Engine
- Custom Weighted Risk Engine for overall severity scoring
- AI-powered (Gemini) summaries explaining *why* an app is dangerous
- Evidence-based findings rather than opaque scores

### 📄 Professional Reporting
- Detailed, downloadable PDF reports for each scan
- Comprehensive JSON exports for automated workflows
- Real-time SSE (Server-Sent Events) progress streaming during scans

### 📋 Scan History & Caching
- All scan results and OSINT intelligence cached via PostgreSQL and Redis
- Lightning-fast retrieval of previously analyzed SHA256 hashes

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **UI** | Flutter 3.x / Dart |
| **Backend API** | FastAPI / Python 3.12 |
| **Analyzers** | MobSF, JADX, APKTool, Androguard, YARA |
| **OSINT** | VirusTotal, Google Safe Browsing, AbuseIPDB |
| **Database** | PostgreSQL (asyncpg), Alembic |
| **Caching/PubSub** | Redis |
| **Infrastructure** | Docker, Docker Compose |

---

## Architecture

```
Flutter App
    │
    ▼ (HTTP POST /scan, SSE /scan/{id}/progress)
    │
FastAPI Backend (scamshield_api) ◄────► Redis (Pub/Sub & OSINT Cache)
    │                                ◄────► PostgreSQL (History & Logs)
    ▼ (Asyncio Gather)
    ├── MobSF (scamshield_mobsf container)
    ├── APKTool & JADX (Decompilation)
    ├── Androguard (Static Analysis)
    ├── YARA (Malware Signatures)
    └── OSINT Services (VirusTotal, etc.)
    │
    ▼
ScamShield Risk Engine
    │
    ▼
AI Explanation Service (Gemini)
    │
    ▼
PDF & JSON Report Generation
```

---

## Getting Started

1. **Clone the repository.**
2. **Configure Environment Variables:**
   - Copy `backend/docker/.env.example` to `backend/.env`
   - Add your `GEMINI_API_KEY` and optional OSINT API keys (e.g., `VIRUSTOTAL_API_KEY`).
3. **Start the Infrastructure:**
   ```bash
   cd backend/docker
   docker compose up -d --build
   ```
4. **Access the API:**
   - FastAPI Docs: [http://localhost:8000/docs](http://localhost:8000/docs)
   - MobSF UI: [http://localhost:8001](http://localhost:8001)

## Testing
To run the automated QA suite against the test APKs:
```bash
cd backend
python3 test_apks.py
```

## Documentation

- [INSTALLATION_GUIDE.md](INSTALLATION_GUIDE.md)
- [PROJECT_REPORT.md](PROJECT_REPORT.md)
- [USER_MANUAL.md](USER_MANUAL.md)
