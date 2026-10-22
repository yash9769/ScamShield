// lib/services/backend_config.dart
//
// Where the ScamShield backend lives, in one place.
//
// VirusTotal, Google Safe Browsing, androguard APK analysis, AI text / voice /
// image analysis, scam trends, verdict feedback and accounts all run on the
// ScamShield server, never inside the app, because their API keys must not ship
// in an APK. Every service used to hardcode "http://10.0.2.2:8000". That
// address only exists inside the Android *emulator* (it is the emulator's alias
// for the developer's computer). On a real phone it points nowhere, so every
// server-backed feature failed silently and the APK scanner quietly fell back
// to its on-device engine, which has no VirusTotal or androguard.
//
// The address is now a setting (Profile > Server address), stored on the
// device, with a connection test. Order of precedence:
//   1. the address saved in the app,
//   2. --dart-define=SCAMSHIELD_BACKEND_URL=... given at build time,
//   3. a development default (emulator alias on Android, localhost elsewhere).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// What a connection test found out.
class BackendStatus {
  final bool reachable;

  /// Human-readable one-liner for the settings dialog.
  final String message;

  /// Which server-side integrations have an API key configured, as reported by
  /// the server's /health endpoint; empty when it doesn't report them.
  final Map<String, bool> integrations;

  /// Result of the server's live /selftest per integration: whether the key
  /// really works, with the reason when it doesn't. Empty when unavailable.
  final Map<String, ({bool ok, String detail})> live;

  const BackendStatus({
    required this.reachable,
    required this.message,
    this.integrations = const {},
    this.live = const {},
  });
}

class BackendConfig {
  static const String _prefsKey = 'scamshield_backend_url';

  static const String _buildTimeUrl = String.fromEnvironment(
    'SCAMSHIELD_BACKEND_URL',
  );

  /// The address saved in the app, or null.
  static final ValueNotifier<String?> savedUrl = ValueNotifier<String?>(null);

  static bool _initialized = false;

  /// Call once at startup, before any network call.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      savedUrl.value = normalize(prefs.getString(_prefsKey));
      _initialized = true;
    } catch (e) {
      debugPrint('BackendConfig.init failed, using defaults: $e');
    }
  }

  /// The address every network call should use.
  static String get baseUrl {
    final saved = savedUrl.value;
    if (saved != null) return saved;
    if (_buildTimeUrl.isNotEmpty) return _buildTimeUrl;
    return developmentDefault;
  }

  static DateTime? _awakeUntil;
  static Future<void>? _warming;

  /// Free hosts (Render) put an idle server to sleep and need 30-60 seconds to
  /// wake it. The short per-request timeouts below that were fine for a local
  /// server made every first request after a quiet spell fail and fall back
  /// to "on-device" or "could not reach". While the server is not known to be
  /// awake, timeouts get extra headroom; once a warm-up has succeeded they
  /// return to normal for 10 minutes. The local development default is never
  /// extended, so a missing server still fails fast.
  static Duration timeout(Duration base) {
    if (isDefault) return base;
    final until = _awakeUntil;
    if (until != null && DateTime.now().isBefore(until)) return base;
    return base + const Duration(seconds: 60);
  }

  /// Wakes the server in the background. Safe to call often; concurrent calls
  /// share one request.
  static Future<void> warmUp() {
    if (isDefault) return Future.value();
    return _warming ??= () async {
      try {
        final r = await http
            .get(Uri.parse('$baseUrl/health'))
            .timeout(const Duration(seconds: 90));
        if (r.statusCode == 200) {
          _awakeUntil = DateTime.now().add(const Duration(minutes: 10));
        }
      } catch (_) {
        // Offline or the address is wrong: the real requests report that.
      } finally {
        _warming = null;
      }
    }();
  }

  /// True when nothing but the development default is in effect, which on a
  /// real phone cannot work.
  static bool get isDefault => savedUrl.value == null && _buildTimeUrl.isEmpty;

  static String get developmentDefault {
    try {
      return Platform.isAndroid
          ? 'http://10.0.2.2:8000'
          : 'http://localhost:8000';
    } catch (_) {
      return 'http://localhost:8000';
    }
  }

  /// Cleans up what a person types: adds http:// when the scheme is missing,
  /// drops a trailing slash. Returns null for empty or unusable input.
  static String? normalize(String? input) {
    var value = (input ?? '').trim();
    if (value.isEmpty) return null;
    if (!value.contains('://')) value = 'http://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// Saves [input] as the backend address; null or empty clears it. Returns
  /// false when [input] isn't a usable address.
  static Future<bool> save(String? input) async {
    final cleaned = normalize(input);
    if ((input ?? '').trim().isNotEmpty && cleaned == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (cleaned == null) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, cleaned);
      }
    } catch (e) {
      debugPrint('BackendConfig.save failed: $e');
      return false;
    }
    savedUrl.value = cleaned;
    _awakeUntil = null;
    warmUp();
    return true;
  }

  /// Server-side integrations the root endpoint reports, with the labels shown
  /// in the settings dialog.
  static const Map<String, String> integrationLabels = {
    'virustotal': 'VirusTotal',
    'safe_browsing': 'Google Safe Browsing',
    'abuseipdb': 'AbuseIPDB',
    'androguard': 'APK analysis (androguard)',
    'yara': 'YARA malware rules',
    'gemini_available': 'AI analysis (Gemini)',
  };

  /// Asks the server at [url] (default: the current address) who it is. The
  /// root endpoint answers with the ScamShield service name and which
  /// integrations have an API key or library available, so the dialog can say
  /// "VirusTotal: not configured on this server" instead of leaving the user
  /// to guess why a lookup came back unavailable.
  static Future<BackendStatus> check([String? url]) async {
    final target = normalize(url) ?? baseUrl;
    const unreachable =
        'Could not connect. Is the ScamShield server running, and is your '
        'phone on the same Wi-Fi as the computer running it?';
    try {
      final response = await http
          .get(Uri.parse('$target/'))
          .timeout(const Duration(seconds: 6));
      Map<dynamic, dynamic>? body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) body = decoded;
      } catch (_) {}
      if (response.statusCode != 200 ||
          body == null ||
          body['service'] == null) {
        return BackendStatus(
          reachable: false,
          message:
              'Something answered at $target, but it is not the ScamShield '
              'server (HTTP ${response.statusCode}). Check the address and '
              'port. The app needs the server/ API, not backend/.',
        );
      }
      final integrations = <String, bool>{};
      for (final key in integrationLabels.keys) {
        final value = body[key];
        if (value is bool) integrations[key] = value;
      }
      if (integrations.isEmpty) {
        // The repo has two backends. backend/ (v2) also answers "ScamShield"
        // but has none of the endpoints this app calls: /scan (APK analysis),
        // /osint/* (VirusTotal, Safe Browsing), /trends, /feedback, accounts.
        // Pointing the app at it makes all of those fail, quietly.
        return BackendStatus(
          reachable: false,
          message:
              'Something is running at $target, but it is not the server the '
              'app needs. It looks like the v2 backend (backend/). Start the '
              'one in the server/ folder instead: it provides APK analysis, '
              'VirusTotal, Safe Browsing, trends and feedback.',
        );
      }
      final live = <String, ({bool ok, String detail})>{};
      try {
        final test = await http
            .get(Uri.parse('$target/selftest'))
            .timeout(const Duration(seconds: 25));
        final decoded = jsonDecode(test.body);
        if (test.statusCode == 200 && decoded is Map) {
          for (final key in integrationLabels.keys) {
            final item = decoded[key];
            if (item is Map && item['ok'] is bool) {
              live[key] = (
                ok: item['ok'] as bool,
                detail: '${item['detail'] ?? ''}',
              );
            }
          }
        }
      } catch (_) {
        // Older servers have no /selftest; the flags above still show.
      }
      return BackendStatus(
        reachable: true,
        message: 'Connected to $target',
        integrations: integrations,
        live: live,
      );
    } on SocketException {
      return const BackendStatus(reachable: false, message: unreachable);
    } on http.ClientException {
      return const BackendStatus(reachable: false, message: unreachable);
    } catch (_) {
      return BackendStatus(
        reachable: false,
        message:
            'No answer from $target within 6 seconds. Check the address, the '
            'port and your connection.',
      );
    }
  }
}
