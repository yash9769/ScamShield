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

The AI-powered analysis requires the FastAPI backend (Kaivalya's module).

```bash
cd server
pip install -r requirements.txt
python main.py
```

The server starts at `http://127.0.0.1:8000`. The Flutter app will connect automatically. If running on Android Emulator, update `_baseUrl` in `lib/services/api_service.dart` to `http://10.0.2.2:8000`.

## 5. Build APK for Testing

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

## 6. Run Tests

```bash
flutter test
```

## 7. Common Issues

| Issue | Fix |
|-------|-----|
| `sqflite` fails on web | Web is not supported — use Android/iOS |
| API connection refused | Ensure backend is running on correct IP |
| Gradle sync fails | Run `flutter clean && flutter pub get` |
| iOS build signing error | Open Xcode and set development team |
