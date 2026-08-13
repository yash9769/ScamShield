// lib/services/settings_service.dart
//
// Persisted user-facing app settings.
//
// The Profile screen previously rendered switches backed by `final bool`
// fields with `onChanged: (v) {}` — they could not be toggled, nothing was
// stored, and nothing read them. This service gives those controls real,
// persisted state so a setting the user changes actually survives a restart
// and is readable by the code that depends on it.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _threatAlertsKey = 'scamshield_threat_alerts';
  static const String _autoScanClipboardKey = 'scamshield_auto_scan_clipboard';

  /// Real-time scam notifications.
  static final ValueNotifier<bool> threatAlerts = ValueNotifier<bool>(true);

  /// Offer to analyse links/messages copied to the clipboard.
  static final ValueNotifier<bool> autoScanClipboard = ValueNotifier<bool>(false);

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      threatAlerts.value = prefs.getBool(_threatAlertsKey) ?? true;
      autoScanClipboard.value = prefs.getBool(_autoScanClipboardKey) ?? false;
      _initialized = true;
    } catch (e) {
      debugPrint('SettingsService.init failed, using defaults: $e');
    }
  }

  static Future<void> setThreatAlerts(bool value) async {
    threatAlerts.value = value;
    await _write(_threatAlertsKey, value);
  }

  static Future<void> setAutoScanClipboard(bool value) async {
    autoScanClipboard.value = value;
    await _write(_autoScanClipboardKey, value);
  }

  static Future<void> _write(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('SettingsService failed to persist $key: $e');
    }
  }
}
