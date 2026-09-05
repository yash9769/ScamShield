// lib/services/sms_screening_service.dart
//
// Real-time SMS scam screening (Android only).
//
// Turns ScamShield from a tool that only helps someone already suspicious
// into one that watches on its own. Every other scan in this app requires the
// user to notice something is wrong, open the app, and paste or share the
// message — which is exactly backwards for the people scams are best at
// fooling. This screens messages the moment they arrive.
//
// ── How a message reaches Dart ────────────────────────────────────────────
// Android delivers SMS_RECEIVED to SmsScreeningReceiver.kt regardless of
// whether the app is running:
//   - App alive:   the native side pushes it over an EventChannel immediately.
//   - App killed:  the native side queues it in SharedPreferences, and this
//                  service drains that queue via a MethodChannel on next start.
// Either way, screening logic itself stays entirely in Dart — the same
// detection engine, consent checks and privacy settings every other scan path
// already uses, so this can't drift into a second, differently-behaved scanner.
//
// ── Explicitly opt-in ────────────────────────────────────────────────────
// RECEIVE_SMS is one of Android's most sensitive permissions and Play Store
// policy restricts it to apps whose core function requires it. This feature
// is off until the user turns it on from Settings and grants the permission;
// nothing here runs by default.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/scan_record.dart';
import '../data/repositories/scan_repository.dart';
import 'api_service.dart';
import 'cloud_account_service.dart';
import 'scam_detector.dart';

class SmsScreeningService {
  SmsScreeningService._();

  static const MethodChannel _methodChannel = MethodChannel('com.example.scamshield/sms');
  static const EventChannel _eventChannel = EventChannel('com.example.scamshield/sms_stream');
  static const String _enabledKey = 'scamshield_sms_screening_enabled';

  static StreamSubscription<dynamic>? _subscription;
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static bool _notificationsReady = false;
  static int _notificationSeq = 0;

  /// Lets Settings reflect the live state without re-reading prefs each build.
  static final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  /// Requests the SMS permission and, if granted, turns screening on.
  /// Returns false without changing anything if the permission is denied.
  static Future<bool> requestPermissionAndEnable() async {
    final status = await Permission.sms.request();
    if (!status.isGranted) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
    await _start();
    return true;
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    await _stop();
  }

  /// Called once at app startup. Re-attaches the listener if the feature was
  /// left on, and cleanly turns it off if the permission has since been
  /// revoked from system Settings behind the app's back.
  static Future<void> initIfEnabled() async {
    if (!await isEnabled()) return;
    if (!await Permission.sms.isGranted) {
      await disable();
      return;
    }
    await _start();
  }

  static Future<void> _start() async {
    await _ensureNotifications();
    _subscription ??= _eventChannel.receiveBroadcastStream().listen(
          _handleLiveEvent,
          onError: (Object e) => debugPrint('SmsScreeningService stream error: $e'),
        );
    isActive.value = true;
    unawaited(_drainQueuedMessages());
  }

  static Future<void> _stop() async {
    await _subscription?.cancel();
    _subscription = null;
    isActive.value = false;
  }

  static void _handleLiveEvent(dynamic event) {
    if (event is! String) return;
    try {
      final map = jsonDecode(event) as Map<String, dynamic>;
      unawaited(_screen(
        sender: map['sender'] as String?,
        body: map['body'] as String? ?? '',
        receivedAt: DateTime.now(),
      ));
    } catch (e) {
      debugPrint('SmsScreeningService: malformed live event ($e)');
    }
  }

  /// Pulls in anything that arrived while the app process was not running.
  static Future<void> _drainQueuedMessages() async {
    try {
      final raw = await _methodChannel.invokeMethod<String>('drainQueuedMessages');
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final tsMs = (map['timestamp'] as num?)?.toInt();
        await _screen(
          sender: map['sender'] as String?,
          body: map['body'] as String? ?? '',
          receivedAt: tsMs != null ? DateTime.fromMillisecondsSinceEpoch(tsMs) : DateTime.now(),
        );
      }
    } on PlatformException catch (e) {
      debugPrint('SmsScreeningService: drain failed ($e)');
    }
  }

  /// Runs one message through the same analysis pipeline every other scan
  /// path uses, saves it to history, and alerts on a dangerous verdict.
  static Future<void> _screen({
    required String? sender,
    required String body,
    required DateTime receivedAt,
  }) async {
    final text = body.trim();
    if (text.isEmpty) return;

    AnalysisResult result;
    try {
      result = await ApiService.analyzeMessage(text);
      if (result.riskScore == 0 &&
          !result.aiPowered &&
          (result.reasons.isEmpty || result.reasons.first.label == 'Analysis Unavailable')) {
        result = ScamDetector.analyze(text);
      }
    } catch (_) {
      result = ScamDetector.analyze(text);
    }

    try {
      final record = ScanRecord.fromAnalysisResult(
        inputText: text,
        result: result,
        source: sender != null && sender.isNotEmpty ? 'SMS from $sender' : 'SMS',
      );
      await ScanRepository().saveScan(record);
    } catch (e) {
      debugPrint('SmsScreeningService: failed to save scan ($e)');
    }

    final isDangerous = result.classification == ScamClassification.scam ||
        (result.classification == ScamClassification.suspicious && result.riskScore >= 60);
    if (!isDangerous) return;

    await _notifyDanger(sender: sender, result: result);
    // Same family-alert relay the manual scan flow uses — best-effort, and a
    // failure here must never be surfaced as an SMS-screening failure.
    unawaited(CloudAccountService.raiseAlert(
      classification: result.classification.name,
      riskScore: result.riskScore,
      summary: result.summary,
    ));
  }

  static Future<void> _ensureNotifications() async {
    if (_notificationsReady) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(
      const InitializationSettings(android: androidSettings),
    );
    _notificationsReady = true;
  }

  static Future<void> _notifyDanger({
    required String? sender,
    required AnalysisResult result,
  }) async {
    await _ensureNotifications();
    final title = result.classification == ScamClassification.scam
        ? 'Scam SMS blocked from reaching you unnoticed'
        : 'Suspicious SMS detected';
    final from = sender != null && sender.isNotEmpty ? ' from $sender' : '';

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'scamshield_sms_alerts',
        'SMS Scam Alerts',
        channelDescription: 'Warns when an incoming SMS looks like a scam.',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.recommendation,
      ),
    );

    // A rolling small id space is enough here — this is a live alert, not a
    // record anyone needs to address by a stable id later.
    _notificationSeq = (_notificationSeq + 1) % 100000;
    await _notifications.show(
      _notificationSeq,
      '$title$from',
      result.summary,
      details,
    );
  }
}
