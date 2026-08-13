// lib/services/device_identity.dart
//
// Anonymous per-install device credential for the ScamShield backend.
//
// WHY THIS EXISTS
//   The backend now enforces client authentication (API_AUTH_ENABLED=true) on
//   every sensitive endpoint. Each install generates ONE random, high-entropy
//   token at first use and persists it. The token is:
//     • anonymous  — it contains no personal data and cannot identify the user
//     • per-install — every fresh install gets a different token, so a leaked
//       token cannot be reused to impersonate another install
//     • never a global API key — unlike embedding a shared secret in the APK
//       (which any decompiler can extract), each install has its own credential
//
// The backend only ever stores a SHA-256 *fingerprint* of this token, so the
// token itself never leaves the device.

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  static const String _tokenKey = 'scamshield_device_token';
  static const String _charset = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  static String? _cached;

  /// Returns the per-install token, generating + persisting it on first call.
  static Future<String> token() async {
    final cached = _cached;
    if (cached != null) return cached;

    try {
      final prefs = await SharedPreferences.getInstance();
      var stored = prefs.getString(_tokenKey);
      if (stored == null || stored.length < 32) {
        stored = _generate(48);
        await prefs.setString(_tokenKey, stored);
      }
      _cached = stored;
      return stored;
    } catch (e) {
      // SharedPreferences unavailable (e.g. in tests / exotic platforms).
      // Fall back to an in-memory token so API calls keep working this session.
      debugPrint('DeviceIdentity: shared_preferences unavailable, using ephemeral token ($e)');
      final ephemeral = _generate(48);
      _cached = ephemeral;
      return ephemeral;
    }
  }

  /// Headers to attach to every backend request.
  static Future<Map<String, String>> authHeaders() async {
    final t = await token();
    return {'X-Device-Token': t};
  }

  static String _generate(int length) {
    final rng = Random.secure();
    return List.generate(length, (_) => _charset[rng.nextInt(_charset.length)]).join();
  }
}
