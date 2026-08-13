# 🛡️ ScamShield Backend (Kaivalya v2)

Production-grade, high-performance REST API backend for ScamShield built with **FastAPI**, **Python 3.12**, **Google Gemini 2.0**, **OpenAI Whisper**, **EasyOCR**, **VirusTotal OSINT**, and **Redis**.

---

## 🏗️ Architecture Overview

The backend follows **Clean Architecture** principles to separate business logic, infrastructure, API presentation, and data schemas:

```
backend/
├── app/
│   ├── api/          # REST API endpoints (v1)
│   ├── core/         # Settings, logging, custom exceptions
│   ├── middleware/   # Security headers, rate limiting, error handling
│   ├── models/       # Domain enums & data structures
│   ├── schemas/      # Pydantic v2 request/response models
│   ├── services/     # Gemini, Heuristic, OSINT, Whisper, EasyOCR, AI Engine
│   ├── utils/        # Text sanitization, JSON extraction, file management
│   └── main.py       # FastAPI application factory
├── docker/           # Dockerfile & Docker Compose
├── tests/            # Unit, API, and Integration tests
├── .github/          # GitHub Actions CI workflow
├── requirements.txt  # Pinned dependencies
└── README.md
```

---

## ⚡ Key Features

- **Hybrid AI Engine**: Combines Google Gemini 2.0 with a fallback heuristic keyword engine. If Gemini is unavailable, it automatically switches to heuristic mode without crashing.
- **Voice Scam Analysis (`POST /analyze-voice`)**: Accepts audio files (`.mp3`, `.wav`, `.m4a`, `.aac`), transcribes using local OpenAI Whisper, and passes the transcript to the AI engine.
- **Image OCR Analysis (`POST /analyze-image`)**: Accepts images (`.jpg`, `.png`, `.pdf`), extracts text using EasyOCR (English + Hindi), and evaluates threat level.
- **Batch Processing (`POST /analyze-batch`)**: Processes up to 20 text messages concurrently with isolated error handling per item.
- **OSINT Enrichment**: Queries VirusTotal API and WHOIS domain age to detect malicious links and fresh scam domains.
- **Production DevOps**: Includes multi-stage Docker build, Docker Compose with Redis, GitHub Actions CI pipeline, security headers, rate limiting, and structured JSON logging.
- **Flutter Compatibility**: Maintains 100% backward compatibility with the ScamShield Flutter frontend schema while adding additive v2 metadata.

---

## 🚀 Quick Start

### 1. Requirements
- Python 3.12+
- ffmpeg (required for audio transcription)
- poppler-utils (required for PDF OCR)

### 2. Local Setup

```bash
cd backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment variables
cp .env.example .env
# Edit .env and set GEMINI_API_KEY=your_key_here
```

### 3. Run Development Server

```bash
uvicorn app.main:app --reload --port 8000
```

Access Swagger Documentation: `http://localhost:8000/docs`

> **Docs / OpenAPI:** `/docs`, `/redoc` and `/openapi.json` are **disabled by
> default in production** to avoid exposing the full route surface (admin
> endpoints included). Enable them with `ENABLE_DOCS=true`, or they turn on
> automatically when `DEBUG=true`.

---

## 🗄️ Database Migrations (Alembic)

Schema changes are managed with **Alembic** — `create_all()` is a development
convenience only (used when `DEBUG=true`). In production the schema is applied
automatically on startup via `alembic upgrade head`, or manually:

```bash
cd backend

# Apply all pending migrations
alembic upgrade head

# Autogenerate a new migration after editing app/models/
alembic revision --autogenerate -m "describe the change"

# Review the SQL a migration will emit (offline mode, no DB write)
alembic upgrade head --sql
```

Notes:

- Migrations run against the same `DATABASE_URL` as the API; the async driver
  is swapped for a sync one automatically (`asyncpg → psycopg2`,
  `aiosqlite → pysqlite`). `psycopg2-binary` is installed via requirements.
- A database created by the old `create_all()` bootstrap has no
  `alembic_version` table. On first boot the runner detects this and **stamps**
  head (adopts the existing tables as-is) instead of re-running DDL.

---

## 🛡️ Admin Dashboard & Audit Logs

The admin surface is protected by `ADMIN_API_KEY` (`Authorization: Bearer` or
`X-Admin-Key` header — no default key is shipped):

| Endpoint | Description |
|---|---|
| `GET /dashboard` | Self-contained HTML dashboard (operator enters the key) |
| `GET /api/audit-logs?limit=N` | Recent audit events, newest first |
| `GET /api/stats` | Operational counters (audit volume, LLM cache) |

Audit rows are **privacy-preserving by design**: raw messages, emails, OTPs
and reset links are never stored — only a SHA-256 fingerprint prefix, length,
risk score and level.

---

## 🐳 Docker Deployment

```bash
cd backend

# Copy env
cp .env.example .env

# Build and start API + Redis services
docker-compose -f docker/docker-compose.yml up --build -d
```

Check health:
```bash
curl http://localhost:8000/health
```

---

## 🧪 Testing

Run pytest suite with coverage:

```bash
cd backend
pytest tests/ -v --cov=app --cov-report=term-missing
```

---

## 📌 API Endpoints Summary

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/analyze` | Text scam analysis (Flutter compatible) |
| `POST` | `/analyze-voice` | Audio upload → Whisper → Scam score |
| `POST` | `/analyze-image` | Image/PDF upload → OCR → Scam score |
| `POST` | `/analyze-batch` | Batch analysis (max 20 messages) |
| `GET` | `/health` | System uptime & service health status |
