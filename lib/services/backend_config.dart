// lib/services/backend_config.dart
//
// Single source of truth for the ScamShield backend URL.
//
// The URL is injected at build time:
//   flutter run  --dart-define=SCAMSHIELD_BACKEND_URL=http://10.0.2.2:8000
//   flutter build apk --dart-define=SCAMSHIELD_BACKEND_URL=https://api.example.com
//
// In DEBUG builds an absent define falls back to the local dev server
// (10.0.2.2 for the Android emulator, localhost elsewhere). Release builds
// MUST provide an HTTPS endpoint: without it the Android release network
// security config blocks cleartext anyway, so we fail fast at startup with a
// clear message instead of surfacing confusing network errors later.

import 'dart:io';

import 'package:flutter/foundation.dart';

class BackendConfig {
  BackendConfig._();

  /// The backend base URL, e.g. `https://api.example.com` (no trailing slash).
  static const String backendUrlOverride = String.fromEnvironment(
    'SCAMSHIELD_BACKEND_URL',
  );

  /// Effective base URL used for all API calls.
  static String get baseUrl {
    if (backendUrlOverride.isNotEmpty) {
      return _stripTrailingSlash(backendUrlOverride);
    }
    if (kIsWeb) return 'http://localhost:8000';
    // Dev fallbacks only — never reachable in release builds (see [validate]).
    return Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
  }

  /// Throws at startup in release builds when no backend URL was supplied.
  ///
  /// Also rejects plain-HTTP endpoints in release mode, matching the Android
  /// network security config which forbids cleartext traffic.
  static void validate() {
    if (!kReleaseMode) return;
    if (backendUrlOverride.isEmpty) {
      throw StateError(
        'This release build has no backend URL. Rebuild with:\n'
        '  flutter build ... --dart-define=SCAMSHIELD_BACKEND_URL=https://your-api.example.com\n'
        'The local fallback (http://10.0.2.2:8000) is blocked in release builds.',
      );
    }
    final uri = Uri.tryParse(backendUrlOverride);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw StateError(
        'SCAMSHIELD_BACKEND_URL must be an https:// URL in release builds. '
        'Got: "$backendUrlOverride"',
      );
    }
  }

  static String _stripTrailingSlash(String value) {
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
