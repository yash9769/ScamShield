# ScamShield — Project Report

## Abstract

ScamShield is a privacy-first, Flutter-based mobile application designed to protect users from digital scams — including phishing, smishing, vishing, lottery fraud, fake job offers, and investment fraud. The app employs a dual-engine detection approach: an offline keyword-heuristic engine for instant on-device analysis, and an optional Gemini AI-powered backend for deeper semantic analysis. All user data is stored locally using SQLite with no external data transmission without explicit consent.

---

## 1. Introduction

### 1.1 Problem Statement
Cybercrime, particularly social engineering fraud, has grown exponentially in India. TRAI and RBI report tens of thousands of scam complaints monthly. Victims are tricked via SMS, WhatsApp, phone calls, and emails into revealing OTPs, account details, and transferring money.

### 1.2 Objective
Build a mobile application that:
1. Analyses suspicious messages in real time
2. Educates users about scam patterns
3. Maintains a secure local history of past analyses
4. Operates primarily offline for privacy and reliability
5. Optionally leverages Gemini AI for enhanced accuracy

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────┐
│                  Flutter App                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │  Screens  │  │ Services │  │  Data Layer  │  │
│  │  home     │  │ scam_    │  │  SQLite DB   │  │
│  │  scan     │  │ detector │  │  Repos       │  │
│  │  history  │  │ api_     │  │  Cache       │  │
│  │  learn    │  │ service  │  │  Education   │  │
│  │  profile  │  └────┬─────┘  └──────────────┘  │
│  └──────────┘       │                           │
└─────────────────────┼───────────────────────────┘
                       │ HTTP (optional, AI only)
              ┌────────▼────────┐
              │  FastAPI Backend │
              │  (Gemini AI)     │
              └─────────────────┘
```

### 2.2 Data Flow

```
User pastes message
       │
       ▼
ScanScreen._analyze()
       │
       ├─ ScamDetector.analyze(text)  ← Local, offline, ~18ms
       │
       ├─ ScanRecord.fromAnalysisResult(...)
       │
       └─ ScanRepository.saveScan(record) → SQLite
```

---

## 3. Data Layer (Yash's Module)

### 3.1 SQLite Schema

**Table: `scan_records`**

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| input_text | TEXT | Raw message content |
| classification | TEXT | 'safe', 'suspicious', 'scam' |
| risk_score | INTEGER | 0–100 |
| summary | TEXT | Human-readable result |
| timestamp | TEXT | ISO 8601 datetime |
| is_flagged | INTEGER | 1 if scam, 0 otherwise |
| source | TEXT | 'Manual', 'Link', 'SMS' |

**Table: `user_preferences`**

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Always 1 (singleton) |
| has_consented | INTEGER | Privacy consent flag |
| notifications_enabled | INTEGER | Alert toggle |
| daily_tip_enabled | INTEGER | Daily tip toggle |
| auto_delete_days | INTEGER | 0/7/30/90 |
| offline_mode_acknowledged | INTEGER | Offline UX flag |

### 3.2 Repository Pattern

All database operations go through typed repositories:
- `ScanRepository` — CRUD, search, filter, statistics
- `PreferencesRepository` — Load/save singleton preferences

### 3.3 Local Cache

An `LocalCache<T>` (in-memory LRU, max 32 entries, optional TTL) prevents redundant SQLite reads on the history screen.

---

## 4. Education Module

| Component | Details |
|-----------|---------|
| Scam Encyclopedia | 10 articles: Phishing, Smishing, Vishing, Lottery, Job, Romance, Tech Support, Investment, URL Analysis, Banking Fraud |
| Quiz | 15 questions with 4 options each + explanations |
| Daily Tips | 30 tips rotating daily |
| Badges | 13 unlockable badges |
| Progress | Vigilance score, streak, points, rank |

---

## 5. Privacy Architecture

- Zero data exfiltration: all scan data lives in on-device SQLite
- AI calls send only the text snippet to backend (no PII stored server-side)
- Consent screen persisted to `user_preferences` table
- Auto-delete: background cleanup deletes records older than configured days
- "Delete All Data" cascades across SQLite + SharedPreferences

---

## 6. Evaluation Results

| Metric | Score |
|--------|-------|
| Accuracy | 89.5% |
| Precision | 90.7% |
| Recall | 88.0% |
| F1 Score | 89.3% |
| Avg Latency | ~18ms |

Full details: [dataset/evaluation/evaluation_report.md](../dataset/evaluation/evaluation_report.md)

---

## 7. Testing

### Unit Tests
- `test/data/scan_repository_test.dart` — CRUD, search, filter, statistics
- `test/data/scam_detector_test.dart` — 15 known scam/safe message tests
- `test/data/progress_service_test.dart` — Badge unlock, streak logic

### User Acceptance Testing
Conducted with 5 test users on Android (Pixel 6, Samsung Galaxy A52, OnePlus 9).
Key findings:
- All test users correctly identified quiz answers after reading articles
- History screen correctly showed all scans
- Offline mode banner triggered correctly in airplane mode

---

## 8. Future Work

1. **ML Model**: Fine-tune DistilBERT for 95%+ accuracy in v2
2. **Multilingual**: Hindi, Marathi keyword sets
3. **Real SMS Integration**: Auto-scan incoming SMS via Android SMS permissions
4. **Push Notifications**: Threat alerts via Firebase Cloud Messaging
5. **Cloud Sync**: Optional opt-in encrypted backup

---

## 9. References

1. TRAI Telecom Fraud Reports 2024–2026
2. RBI Annual Cybercrime Statistics 2025
3. CERT-In Guidelines on Phishing Prevention
4. Flutter Documentation: https://flutter.dev/docs
5. sqflite Package: https://pub.dev/packages/sqflite
