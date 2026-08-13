# ScamShield — Installation Guide

## Prerequisites

| Requirement | Version |
|-------------|---------|
| Flutter SDK | ≥ 3.11.4 |
| Dart SDK | ≥ 3.11.4 |
| Android Studio / Xcode | Latest stable |
| Git | Any |
| Python | ≥ 3.9 (for backend) |

---

## 1. Clone the Repository

```bash
git clone <repo-url>
cd ScamShield
git checkout develop
```

## 2. Install Flutter Dependencies

```bash
flutter pub get
```

## 3. Run the App (Debug)

### Android Emulator
```bash
flutter run
```

### Physical Device
```bash
flutter devices         # list connected devices
flutter run -d <device-id>
```

### iOS (macOS only)
```bash
open ios/Runner.xcworkspace   # open in Xcode first to set signing
flutter run
```

## 4. Set Up the Backend (AI Analysis)

The AI-powered analysis requires the FastAPI backend.

```bash
cd backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env          # set ADMIN_API_KEY (+ optional AI/OSINT keys)
uvicorn app.main:app --reload --port 8000
```

The server starts at `http://127.0.0.1:8000` and applies any pending Alembic
migrations on boot. Point the Flutter app at it via `--dart-define`:

```bash
# Android emulator reaches the host machine via 10.0.2.2
flutter run --dart-define=SCAMSHIELD_BACKEND_URL=http://10.0.2.2:8000
```

## 5. Build APK for Production

Release builds **require** an HTTPS backend URL — they fail fast at startup if
`SCAMSHIELD_BACKEND_URL` is missing or not `https://` (the Android release
network security config blocks cleartext HTTP anyway).

```bash
flutter build apk --release \
  --dart-define=SCAMSHIELD_BACKEND_URL=https://your-api.example.com
# Output: build/app/outputs/flutter-apk/app-release.apk
```

## 6. Run Tests

```bash
cd backend && python -m pytest tests/ -q   # backend suite
cd .. && flutter test                      # Flutter suite
```

## 7. Common Issues

| Issue | Fix |
|-------|-----|
| `sqflite` fails on web | Web is not supported — use Android/iOS |
| API connection refused | Ensure backend is running on correct IP |
| Gradle sync fails | Run `flutter clean && flutter pub get` |
| iOS build signing error | Open Xcode and set development team |
| Release app aborts: "no backend URL" | Rebuild with `--dart-define=SCAMSHIELD_BACKEND_URL=https://...` |
| `/docs` returns 404 in production | Docs are off by default; set `ENABLE_DOCS=true` or `DEBUG=true` |
