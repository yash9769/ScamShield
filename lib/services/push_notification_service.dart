// lib/services/push_notification_service.dart
//
// Firebase Cloud Messaging: wakes a relative's phone when someone in their
// family group scans something dangerous.
//
// ── Why push, when the alert is already stored? ────────────────────────────
// The family alert itself is durable on the server and shows up whenever the
// app is next opened. That is fine for a record and useless for a warning: a
// daughter who opens ScamShield on Sunday does not need to learn her father
// was targeted on Friday. The point of this file is the difference between
// those two moments.
//
// ── Entirely optional, by construction ─────────────────────────────────────
// Firebase needs an android/app/google-services.json that only the project's
// owner can generate. Rather than make that a build requirement, everything
// here fails soft: without the file, Firebase.initializeApp() throws, this
// service marks itself unavailable, and every other feature — family alerts
// included — carries on exactly as before. The Gradle plugin is applied
// conditionally for the same reason (see android/app/build.gradle.kts), so a
// fresh clone still builds with no Firebase setup at all.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'cloud_account_service.dart';
import 'settings_service.dart';

/// Handles a message that arrives while the app is terminated or backgrounded.
///
/// Must be a top-level function with this pragma: Flutter spins up a separate
/// background isolate to run it, and the entry point has to survive tree
/// shaking in release builds to be found at all.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // Deliberately does nothing. FCM already displays the `notification` payload
  // itself when the app is not in the foreground, so re-posting it here would
  // show the user the same warning twice. This exists because registering a
  // background handler is what lets data-only messages be delivered at all.
}

class PushNotificationService {
  PushNotificationService._();

  static const String _channelId = 'scamshield_family_alerts';

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static String? _currentToken;

  /// True once Firebase actually came up. Lets Settings tell the difference
  /// between "push is off" and "push was never configured for this build",
  /// which are very different things to show a user.
  static final ValueNotifier<bool> available = ValueNotifier<bool>(false);

  static String? get currentToken => _currentToken;

  /// Brings up Firebase if it is configured, and wires the token to the
  /// account. Safe to call more than once and safe to call when signed out.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      // The expected path on any build without google-services.json.
      debugPrint('PushNotificationService: Firebase not configured ($e)');
      available.value = false;
      return;
    }

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      // On Android 13+ this surfaces the POST_NOTIFICATIONS prompt; below it,
      // it resolves to authorized without showing anything.
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('PushNotificationService: notification permission denied');
        available.value = false;
        return;
      }

      await _ensureChannel();
      available.value = true;

      // A token can rotate at any time (app restore, data clear, FCM's own
      // schedule). Listening is what keeps the server's copy from going stale
      // and silently dropping this device's alerts.
      messaging.onTokenRefresh.listen(_onToken);
      final token = await messaging.getToken();
      if (token != null) await _onToken(token);

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    } catch (e) {
      debugPrint('PushNotificationService.init failed: $e');
      available.value = false;
    }
  }

  /// Registers the current token against the signed-in account. Called after
  /// sign-in, when the token rotates, and at startup.
  static Future<void> syncTokenWithAccount() async {
    final token = _currentToken;
    if (token == null) return;
    if (!CloudAccountService.signedIn.value) return;
    await CloudAccountService.registerPushToken(token);
  }

  /// Detaches this device from the account being signed out of, so the next
  /// person to sign in on this phone does not receive the previous user's
  /// family alerts. Best-effort: sign-out must not be blocked by it.
  static Future<void> clearTokenForSignOut() async {
    final token = _currentToken;
    if (token == null) return;
    await CloudAccountService.unregisterPushToken(token);
  }

  static Future<void> _onToken(String token) async {
    _currentToken = token;
    await syncTokenWithAccount();
  }

  /// FCM does not display anything while the app is in the foreground, so if
  /// we want the user to see a family alert without staring at the right
  /// screen, this has to post it.
  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    if (!SettingsService.threatAlerts.value) return;

    final notification = message.notification;
    final title = notification?.title ?? message.data['title'];
    final body = notification?.body ?? message.data['body'];
    if (title == null && body == null) return;

    await _ensureChannel();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Family Alerts',
        channelDescription: 'Warns when someone in your family group is targeted.',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.recommendation,
      ),
    );

    await _local.show(
      // Stable per message so a resend replaces rather than stacks.
      message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch.hashCode,
      title ?? 'ScamShield alert',
      body ?? '',
      details,
    );
  }

  static bool _channelReady = false;

  static Future<void> _ensureChannel() async {
    if (_channelReady) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(const InitializationSettings(android: androidSettings));
    _channelReady = true;
  }
}
