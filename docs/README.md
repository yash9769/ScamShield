# ScamShield 🛡️

**ScamShield** is a Flutter-based mobile application that detects scam messages, phishing links, and social engineering attempts in real time — protecting users from digital fraud using on-device heuristics and optional Gemini AI analysis.

---

## Features

### 🔍 Scam Detection
- Paste any SMS, email excerpt, or URL for instant analysis
- Local keyword + regex heuristic engine (offline-capable, ~18ms)
- Optional Gemini AI-powered analysis for detailed insights
- Risk score 0–100 with colour-coded classification (Safe / Suspicious / Scam)
- Detailed breakdown of detected signals (urgency, financial keywords, shortened URLs, etc.)

### 📋 History
- All scan results auto-saved to local SQLite database
- Filter by All / Threats / Suspicious / Safe
- Full-text search across scanned messages
- Swipe-to-delete individual records
- Live statistics: total scans, threats, safe count, average risk

### 📚 Education Module
- Scam Encyclopedia: 10 in-depth articles (Phishing, Smishing, Vishing, Lottery, Job, Romance, Tech Support, Investment, URL Analysis, Banking Fraud)
- Interactive Quiz: 15 questions with explanations
- 13 unlockable badges
- Daily Scam Tip (30 unique tips, one per day)
- Progress tracker with vigilance score and streak counter

### 🔒 Privacy
- All data stored locally on-device (SQLite + SharedPreferences)
- No data transmitted without explicit user action
- Consent management with on/off toggle
- Auto-delete history: 7, 30, 90 days or never
- One-tap "Delete All Data" option
- Full in-app Privacy Policy

### 📡 Offline Support
- Local heuristic detection works 100% offline
- Offline banner appears automatically when connectivity lost

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | Flutter 3.x / Dart |
| Local Storage | SQLite (`sqflite`) |
| Preferences | `shared_preferences` |
| AI Analysis | Gemini API (FastAPI backend) |
| Connectivity | `connectivity_plus` |
| State | `StatefulWidget` + async repository pattern |

---

## Architecture

```
lib/
├── main.dart                    # App entry + navigation
├── theme.dart                   # Design tokens & theme
├── screens/
│   ├── home_screen.dart         # Dashboard with live DB stats
│   ├── scan_screen.dart         # Message analysis + DB save
│   ├── history_screen.dart      # SQLite history with search/filter
│   ├── learn_screen.dart        # Education module hub
│   └── profile_screen.dart      # Privacy controls & preferences
├── services/
│   ├── scam_detector.dart       # Local heuristic engine
│   └── api_service.dart         # Gemini AI backend client
├── data/
│   ├── models/                  # ScanRecord, UserPreferences
│   ├── database/                # SQLite DatabaseHelper
│   ├── repositories/            # ScanRepository, PreferencesRepository
│   ├── cache/                   # In-memory LRU cache
│   └── education/               # Scam encyclopedia, quiz, tips, progress
└── widgets/
    └── offline_banner.dart      # Connectivity-aware banner
```

---

## Team

| Member | Role | Branch |
|--------|------|--------|
| Kaivalya | Backend / AI | `feature/backend-ai` |
| Swarali | Flutter UI | `feature/flutter-ui` |
| Yash | Data Layer & Features | `feature/data-features` |

---

## Getting Started

See [INSTALLATION_GUIDE.md](INSTALLATION_GUIDE.md) for setup instructions.

## User Manual

See [USER_MANUAL.md](USER_MANUAL.md) for usage instructions.

## Project Report

See [PROJECT_REPORT.md](PROJECT_REPORT.md) for full technical documentation.
