// lib/services/google_auth_service.dart
//
// Google Sign-In, wrapped so the rest of the app never touches the plugin
// directly and a missing/incorrect Google Cloud configuration degrades into a
// clear message instead of an unhandled PlatformException.
//
// ── Required setup (this cannot be shipped pre-configured) ────────────────────
// Google Sign-In needs an OAuth client that is tied to *your* app signing
// certificate, so it has to be created in your own Google Cloud project:
//
//   1. Google Cloud Console > APIs & Services > Credentials.
//   2. Create an OAuth client ID of type "Android": package name
//      `com.example.scamshield` (see android/app/build.gradle.kts) and the
//      SHA-1 of your signing key (`./gradlew signingReport`). Do this for the
//      debug key too, or sign-in works in release but not in debug.
//   3. Create a second OAuth client ID of type "Web application". Its client ID
//      is the "server client ID" the Android SDK needs in order to return an
//      ID token.
//   4. Pass that Web client ID in at build time:
//        flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
//
// Until step 4 is done, [isConfigured] is false and the UI hides/disables the
// Google button rather than showing a control that always fails.
//
// ── Scope note ───────────────────────────────────────────────────────────────
// ScamShield has no user backend — the server is a stateless analysis API. So
// Google is used purely as an identity provider for the *local* account: we
// take the verified email/name/avatar and hand them to AuthService, which owns
// the on-device account exactly as it does for password accounts. No ID token
// is transmitted anywhere, because there is no server session to establish.

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

enum GoogleAuthStatus { success, cancelled, notConfigured, failed }

class GoogleAuthResult {
  final GoogleAuthStatus status;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String? message;

  const GoogleAuthResult._(
    this.status, {
    this.email,
    this.displayName,
    this.photoUrl,
    this.message,
  });

  const GoogleAuthResult.success({
    required String email,
    String? displayName,
    String? photoUrl,
  }) : this._(
          GoogleAuthStatus.success,
          email: email,
          displayName: displayName,
          photoUrl: photoUrl,
        );

  const GoogleAuthResult.cancelled() : this._(GoogleAuthStatus.cancelled);

  const GoogleAuthResult.notConfigured()
      : this._(
          GoogleAuthStatus.notConfigured,
          message: 'Google Sign-In is not configured for this build. '
              'Rebuild with --dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>.',
        );

  const GoogleAuthResult.failed(String message)
      : this._(GoogleAuthStatus.failed, message: message);

  bool get isSuccess => status == GoogleAuthStatus.success;
}

class GoogleAuthService {
  GoogleAuthService._();

  /// Supplied at build time via --dart-define. Empty means "not configured".
  static const String _serverClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static bool get isConfigured => _serverClientId.isNotEmpty;

  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: _serverClientId);
    _initialized = true;
  }

  /// Runs the interactive Google sign-in flow.
  ///
  /// Never throws: every failure path is mapped onto a [GoogleAuthResult] so
  /// callers can show one message and move on.
  static Future<GoogleAuthResult> signIn() async {
    if (!isConfigured) return const GoogleAuthResult.notConfigured();

    try {
      await _ensureInitialized();

      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        return const GoogleAuthResult.failed(
          'Google Sign-In is not supported on this device.',
        );
      }

      final GoogleSignInAccount account =
          await GoogleSignIn.instance.authenticate();

      return GoogleAuthResult.success(
        email: account.email,
        displayName: account.displayName,
        photoUrl: account.photoUrl,
      );
    } on GoogleSignInException catch (e) {
      debugPrint('GoogleAuthService.signIn failed: $e');
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
          return const GoogleAuthResult.cancelled();
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          // The overwhelmingly common cause here is an OAuth client whose
          // SHA-1/package name doesn't match this build, so say that rather
          // than a generic failure.
          return const GoogleAuthResult.failed(
            'Google rejected this app\'s configuration. Check that the OAuth '
            'client\'s package name and SHA-1 match this build.',
          );
        case GoogleSignInExceptionCode.uiUnavailable:
          return const GoogleAuthResult.failed(
            'Could not open the Google sign-in screen. Please try again.',
          );
        default:
          return const GoogleAuthResult.failed(
            'Google sign-in could not be completed. Please try again.',
          );
      }
    } catch (e) {
      debugPrint('GoogleAuthService.signIn unexpected error: $e');
      return const GoogleAuthResult.failed(
        'Google sign-in could not be completed. Please try again.',
      );
    }
  }

  /// Clears the Google session. Safe to call when never signed in.
  static Future<void> signOut() async {
    if (!isConfigured) return;
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('GoogleAuthService.signOut failed: $e');
    }
  }

  /// Revokes the app's access entirely — used when the account is deleted, so
  /// ScamShield stops appearing in the user's Google "connected apps".
  static Future<void> disconnect() async {
    if (!isConfigured) return;
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.disconnect();
    } catch (e) {
      debugPrint('GoogleAuthService.disconnect failed: $e');
    }
  }
}
