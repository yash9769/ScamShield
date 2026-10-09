// lib/services/simple_mode_service.dart
//
// Simple Mode: a different app for the people this app is most for.
//
// The people scams work best on are, disproportionately, the people the
// standard interface serves worst. Six navigation tabs, a stats grid, "OSINT",
// "Safe Vault", "SIM Lock", and a risk score out of 100 are all fine for
// someone comfortable with security tooling, and are noise — or worse,
// intimidating — for a 70-year-old whose son installed this after they nearly
// lost their savings.
//
// So this is not a font-size slider. Turning it on replaces the whole top
// level of the app with one screen, one action, and a verdict written as an
// instruction rather than a measurement. "SUSPICIOUS · 62/100" tells someone
// nothing they can act on; "Be careful — do not send money or share any code"
// does.
//
// The setting is stored locally and never leaves the device: which interface
// someone needs is not information a server has any business holding.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SimpleModeService {
  SimpleModeService._();

  static const String _prefsKey = 'scamshield_simple_mode';

  /// Watched at the root of the widget tree, so switching modes takes effect
  /// immediately instead of on next launch.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(_prefsKey) ?? false;
      _initialized = true;
    } catch (e) {
      debugPrint('SimpleModeService.init failed, using standard mode: $e');
    }
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (e) {
      debugPrint('SimpleModeService failed to persist: $e');
    }
  }
}
