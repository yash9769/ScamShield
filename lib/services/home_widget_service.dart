// lib/services/home_widget_service.dart
//
// The Dart half of the home-screen widget (Android only).
//
// ── Why the widget is worth having ─────────────────────────────────────────
// Unlock, find the app, open it, reach the scan tab, paste: five actions at
// exactly the moment someone is being rushed by a scammer, which is the whole
// tactic. The widget makes it one. The rest of this app is about being right
// about a message; this is about being reachable in the seconds where being
// right still matters.
//
// ── Division of labour ─────────────────────────────────────────────────────
// A widget has no Flutter engine, so ScamShieldWidgetProvider.kt cannot ask
// Dart anything at draw time. Rather than reimplementing the statistics in
// Kotlin — where the two copies would inevitably disagree — Dart writes one
// ready-to-render line of text into shared preferences and asks for a redraw.
// Kotlin reads that string and nothing else.
//
// Refreshes are pushed, never polled: `updatePeriodMillis` is 0 in
// scamshield_widget_info.xml. A tile whose text only changes after a scan has
// no business waking the device on a timer.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/scan_record.dart';
import '../data/repositories/scan_repository.dart';

class HomeWidgetService {
  HomeWidgetService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.scamshield/widget');

  /// Read by ScamShieldWidgetProvider.kt, which prefixes it with "flutter." —
  /// the prefix shared_preferences adds on Android. Renaming it here without
  /// renaming it there silently freezes the widget's text.
  static const String _statusKey = 'scamshield_widget_status';

  static Timer? _debounce;

  /// Recomputes the widget's status line and redraws every placed instance.
  ///
  /// Debounced, because the natural place to call this from is the app's
  /// data-change notifier — and a backup restore fires that once per record.
  /// Five hundred statistics queries and platform calls to end up drawing one
  /// line of text is not a trade worth making; the last one wins anyway.
  ///
  /// Cheap and safe to call after any scan: if the user has not placed the
  /// widget, the native side finds no instances and returns immediately.
  static void refreshSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), refresh);
  }

  static Future<void> refresh() async {
    if (!Platform.isAndroid) return;
    try {
      final stats = await ScanRepository().getStatistics();
      final status = _statusLine(stats);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_statusKey, status);
      await _channel.invokeMethod<bool>('refresh');
    } catch (e) {
      // A widget that failed to redraw is a cosmetic problem. It must never
      // surface as a scan failure.
      debugPrint('HomeWidgetService.refresh failed: $e');
    }
  }

  /// Returns the action the app was launched with, if it came from the widget,
  /// and clears it so a later resume is not mistaken for a fresh tap.
  static Future<String?> consumeLaunchAction() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('consumeLaunchAction');
    } on PlatformException catch (e) {
      debugPrint('HomeWidgetService.consumeLaunchAction failed: $e');
      return null;
    }
  }

  /// One short line, in the user's terms.
  ///
  /// Deliberately not a dashboard. A widget has a couple of seconds of
  /// attention and about forty characters of room; "3 scams caught this week"
  /// earns its space, a grid of counters does not.
  static String _statusLine(ScanStatistics stats) {
    if (stats.totalScans == 0) {
      return 'Tap to scan something suspicious';
    }
    if (stats.scamCount > 0) {
      return '${stats.scamCount} scam(s) caught · ${stats.totalScans} checked';
    }
    return '${stats.totalScans} checked · nothing dangerous found';
  }
}
