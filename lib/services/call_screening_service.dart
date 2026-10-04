// lib/services/call_screening_service.dart
//
// Scam call screening (Android 10+ only).
//
// SMS screening already covers messages; this covers the other half of how
// scams actually arrive. Voice is the harder channel to defend — there is no
// text to analyse and no time to think — so the win here is narrower and
// honest: tell the user *before they answer* that this number is one they, or
// the community, have already seen behaving badly.
//
// ── Division of labour ─────────────────────────────────────────────────────
// Unlike SMS screening, the screening decision cannot live in Dart: Android
// gives a call-screening service a few seconds to respond and there may be no
// Flutter engine running at all. So:
//
//   Dart (here)  owns the *data*: it decides which numbers count as known-bad
//                and writes that list into shared preferences.
//   Kotlin       owns only the *lookup* at call time — a set membership test
//                (see CallScreeningServiceImpl.kt).
//
// This is the same "one source of truth" principle as SmsScreeningService,
// pointed the other way round by the platform's constraints.
//
// ── Why it never blocks a call ─────────────────────────────────────────────
// The native side always allows the call through and warns instead. A wrongly
// blocked call can be a hospital or a bank's real fraud desk; a wrongly
// allowed one still meets every other defence in the app.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repositories/scan_repository.dart';

class CallScreeningService {
  CallScreeningService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.scamshield/call_screening');

  // These keys are read by CallScreeningServiceImpl.kt, which prefixes them
  // with "flutter." — the prefix shared_preferences adds on Android. Renaming
  // one here without renaming it there silently disables the feature, so they
  // are kept together in this comment on purpose.
  static const String _enabledKey = 'scamshield_call_screening_enabled';
  static const String _blocklistKey = 'scamshield_call_blocklist';
  static const String _silenceKey = 'scamshield_call_silence_known';
  static const String _onlineLookupKey = 'scamshield_call_online_lookup';
  static const String _apiBaseKey = 'scamshield_api_base_url';

  /// Caps the list handed to the native side. A screening callback runs on
  /// every incoming call under a hard time budget, so this stays small enough
  /// to parse and search in microseconds.
  static const int _maxBlocklist = 500;

  /// Lets Profile reflect live state without re-reading prefs on every build.
  static final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  static String get _baseUrl {
    const customUrl = String.fromEnvironment('SCAMSHIELD_BACKEND_URL');
    if (customUrl.isNotEmpty) return customUrl;
    return Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
  }

  /// Android 10+ only. Anything else reports unsupported rather than showing
  /// the user a control that cannot work.
  static Future<bool> isSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException catch (e) {
      debugPrint('CallScreeningService.isSupported failed: $e');
      return false;
    }
  }

  /// Whether Android currently considers ScamShield the call-screening app.
  /// Always re-checked rather than cached: the user can hand the role to
  /// another app at any time, and only one app on the device can hold it.
  static Future<bool> hasRole() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('hasRole') ?? false;
    } on PlatformException catch (e) {
      debugPrint('CallScreeningService.hasRole failed: $e');
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  /// Shows the system role dialog and, if the user grants it, turns screening
  /// on. Returns false without changing anything if they decline — the role
  /// is theirs to give, and a refusal is a valid answer, not an error.
  static Future<bool> requestRoleAndEnable() async {
    if (!await isSupported()) return false;
    bool granted;
    try {
      granted = await _channel.invokeMethod<bool>('requestRole') ?? false;
    } on PlatformException catch (e) {
      debugPrint('CallScreeningService.requestRole failed: $e');
      return false;
    }
    if (!granted) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
    await prefs.setString(_apiBaseKey, _baseUrl);
    isActive.value = true;
    await refreshBlocklist();
    return true;
  }

  /// Turns screening off. The native service stays registered (an app cannot
  /// drop a system role it holds), so the flag is what actually stops it —
  /// which is why the service checks it first thing on every call.
  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    isActive.value = false;
  }

  /// Sends the user to system settings, the only place the role can be handed
  /// back. Offered alongside [disable] so "stop screening my calls" is
  /// completely achievable, not just switched off inside this app.
  static Future<void> openSystemRoleSettings() async {
    try {
      await _channel.invokeMethod<bool>('openRoleSettings');
    } on PlatformException catch (e) {
      debugPrint('CallScreeningService.openRoleSettings failed: $e');
    }
  }

  /// Re-syncs live state at startup, and cleanly turns the feature off if the
  /// role was taken away from behind the app's back.
  static Future<void> initIfEnabled() async {
    if (!Platform.isAndroid) return;
    if (!await isEnabled()) return;
    if (!await hasRole()) {
      await disable();
      return;
    }
    isActive.value = true;
    // Keeps the base URL current across builds that point at a different
    // backend, and refreshes the list with anything scanned since last run.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiBaseKey, _baseUrl);
    await refreshBlocklist();
  }

  static Future<bool> silenceKnownScams() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_silenceKey) ?? false;
  }

  /// Silencing the ringer for a number already on the local list. Off by
  /// default: a silenced call the user needed is a real cost, so it has to be
  /// something they chose.
  static Future<void> setSilenceKnownScams(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_silenceKey, value);
  }

  static Future<bool> onlineLookup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onlineLookupKey) ?? false;
  }

  /// Checking unknown callers against the community reputation API. Off by
  /// default because it discloses who is calling this device to the server —
  /// a real privacy cost that the user, not this app, gets to weigh.
  static Future<void> setOnlineLookup(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onlineLookupKey, value);
  }

  /// Rebuilds the local known-bad list from what this device already knows.
  ///
  /// Sources, both local by design — no wholesale download of a community
  /// blocklist, which would mean shipping every reported number to every
  /// phone:
  ///   * numbers attached to a scan this user's own history flagged as a scam,
  ///   * numbers the user explicitly added via [addNumber].
  static Future<void> refreshBlocklist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final manual = _decodeList(prefs.getString('${_blocklistKey}_manual'));

      final fromHistory = <String>{};
      final history = await ScanRepository().loadHistory(limit: 500);
      for (final record in history) {
        if (record.classification != 'scam') continue;
        final number = _senderNumber(record.source);
        if (number != null) fromHistory.add(number);
      }

      // Manual entries first so a user's own explicit additions survive the
      // cap when history is long.
      final merged = <String>{...manual, ...fromHistory}.take(_maxBlocklist).toList();
      await prefs.setString(_blocklistKey, jsonEncode(merged));
    } catch (e) {
      debugPrint('CallScreeningService.refreshBlocklist failed: $e');
    }
  }

  /// Adds a number the user has explicitly marked as a scam caller.
  static Future<void> addNumber(String raw) async {
    final normalized = normalize(raw);
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final manual = _decodeList(prefs.getString('${_blocklistKey}_manual'));
    if (manual.contains(normalized)) return;
    manual.add(normalized);
    await prefs.setString('${_blocklistKey}_manual', jsonEncode(manual));
    await refreshBlocklist();
  }

  static Future<void> removeNumber(String raw) async {
    final normalized = normalize(raw);
    final prefs = await SharedPreferences.getInstance();
    final manual = _decodeList(prefs.getString('${_blocklistKey}_manual'))
      ..remove(normalized);
    await prefs.setString('${_blocklistKey}_manual', jsonEncode(manual));
    await refreshBlocklist();
  }

  static Future<List<String>> manualNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString('${_blocklistKey}_manual'));
  }

  /// Reduces a number to the form stored on both sides of the channel.
  /// Must stay in step with normalize() in CallScreeningServiceImpl.kt and
  /// _normalize_indicator() in server/main.py — the same real number arrives
  /// as +919876543210, 09876543210 or 9876543210 depending on the caller.
  static String normalize(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) return digits.substring(2);
    if (digits.length == 11 && digits.startsWith('0')) return digits.substring(1);
    return digits;
  }

  /// Pulls a number back out of a scan record's source label, which SMS
  /// screening writes as "SMS from +919876543210". Returns null for sources
  /// that carry no number ("Manual", "Clipboard", plain "SMS").
  static String? _senderNumber(String? source) {
    if (source == null) return null;
    final match = RegExp(r'from\s+(\+?[\d\s\-()]{7,})$').firstMatch(source);
    if (match == null) return null;
    final normalized = normalize(match.group(1)!);
    // Alphanumeric sender IDs ("VM-HDFCBK") normalize to something too short
    // to be a real number; screening on those would match nothing useful.
    return normalized.length >= 7 ? normalized : null;
  }

  static List<String> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<String>().toList();
    } catch (_) {
      return <String>[];
    }
  }
}
