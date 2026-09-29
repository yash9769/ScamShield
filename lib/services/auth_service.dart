// lib/services/auth_service.dart
//
// Local account authentication for ScamShield.
//
// Previously the login and registration screens accepted ANY input: they ran a
// one-second `Future.delayed` "simulated network delay" and then navigated to
// the main app regardless of what was typed. Nothing was stored, nothing was
// verified, and there was no account concept at all — the password field was
// decorative. That is a fake feature, and for an app that stores scan history
// and a "Safe Vault" it is also a real security gap.
//
// ScamShield has no user backend (the server is a stateless analysis API), so
// accounts are held locally on the device. Credentials are stored as:
//   PBKDF2-HMAC-SHA256(password, per-user random salt, 120k iterations)
// The plaintext password is never persisted. The salt and derived key live in
// flutter_secure_storage (Keychain / EncryptedSharedPreferences), not in plain
// SharedPreferences.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cloud_account_service.dart';
import 'cloud_sync_service.dart';
import 'google_auth_service.dart';

enum AuthResult {
  success,
  invalidCredentials,
  accountExists,
  noAccount,
  weakPassword,
  invalidEmail,
  /// The account on this device was created with Google, so there is no
  /// password to check — the user has to come back through Google.
  useGoogleSignIn,
}

/// How the local account was established. A Google account has no password on
/// this device, so anything that re-verifies the user (deleting the account,
/// for instance) has to take a different route for each.
enum AuthProvider { password, google }

class AuthService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _emailKey = 'scamshield_auth_email';
  static const String _saltKey = 'scamshield_auth_salt';
  static const String _hashKey = 'scamshield_auth_hash';
  static const String _sessionKey = 'scamshield_auth_session';
  static const String _providerKey = 'scamshield_auth_provider';
  static const String _displayNameKey = 'scamshield_auth_display_name';
  static const String _photoUrlKey = 'scamshield_auth_photo_url';

  static const int _iterations = 120000;
  static const int _keyLength = 32;
  static const int _minPasswordLength = 8;

  static final RegExp _emailRe = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  // ── Validation ─────────────────────────────────────────────────────────────

  static bool isValidEmail(String email) => _emailRe.hasMatch(email.trim());

  /// Returns null when acceptable, otherwise a human-readable reason.
  static String? validatePassword(String password) {
    if (password.length < _minPasswordLength) {
      return 'Password must be at least $_minPasswordLength characters.';
    }
    if (!password.contains(RegExp(r'[A-Za-z]')) || !password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain both letters and numbers.';
    }
    return null;
  }

  // ── Password hashing (PBKDF2-HMAC-SHA256) ─────────────────────────────────

  static Uint8List _pbkdf2(String password, Uint8List salt) {
    final hmac = Hmac(sha256, utf8.encode(password));
    // PBKDF2 with dkLen == hLen, so a single block (i = 1) is sufficient.
    final block = <int>[...salt, 0, 0, 0, 1];
    var u = Uint8List.fromList(hmac.convert(block).bytes);
    final result = Uint8List.fromList(u);
    for (var i = 1; i < _iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return Uint8List.sublistView(result, 0, _keyLength);
  }

  static Uint8List _randomSalt([int length = 16]) {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => rng.nextInt(256)));
  }

  /// Length-constant comparison so verification time does not leak how much of
  /// the hash matched.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  // ── Account lifecycle ─────────────────────────────────────────────────────

  /// True when any local account exists — password-derived or Google-linked.
  static Future<bool> hasAccount() async =>
      (await _storage.read(key: _emailKey)) != null;

  static Future<String?> registeredEmail() async =>
      await _storage.read(key: _emailKey);

  static Future<String?> displayName() async =>
      await _storage.read(key: _displayNameKey);

  static Future<String?> photoUrl() async =>
      await _storage.read(key: _photoUrlKey);

  static Future<AuthProvider> currentProvider() async =>
      (await _storage.read(key: _providerKey)) == 'google'
          ? AuthProvider.google
          : AuthProvider.password;

  /// Records a completed Google sign-in as the device's account.
  ///
  /// Google has already verified the address, so there is no password to
  /// derive or store — the identity itself is the credential. Any previous
  /// password material is cleared so a stale hash can't be used to sign in as
  /// this account afterwards.
  static Future<void> completeGoogleSignIn({
    required String email,
    String? displayName,
    String? photoUrl,
  }) async {
    await _storage.write(key: _emailKey, value: email.trim().toLowerCase());
    await _storage.write(key: _providerKey, value: 'google');
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _hashKey);

    if (displayName != null && displayName.isNotEmpty) {
      await _storage.write(key: _displayNameKey, value: displayName);
    } else {
      await _storage.delete(key: _displayNameKey);
    }
    if (photoUrl != null && photoUrl.isNotEmpty) {
      await _storage.write(key: _photoUrlKey, value: photoUrl);
    } else {
      await _storage.delete(key: _photoUrlKey);
    }

    await _storage.write(key: _sessionKey, value: 'active');
  }

  static Future<AuthResult> register(String email, String password) async {
    final trimmed = email.trim().toLowerCase();
    if (!isValidEmail(trimmed)) return AuthResult.invalidEmail;
    if (validatePassword(password) != null) return AuthResult.weakPassword;
    if (await hasAccount()) return AuthResult.accountExists;

    final salt = _randomSalt();
    final hash = _pbkdf2(password, salt);

    await _storage.write(key: _emailKey, value: trimmed);
    await _storage.write(key: _saltKey, value: base64Encode(salt));
    await _storage.write(key: _hashKey, value: base64Encode(hash));
    await _storage.write(key: _providerKey, value: 'password');
    await _storage.write(key: _sessionKey, value: 'active');
    return AuthResult.success;
  }

  static Future<AuthResult> login(String email, String password) async {
    final storedEmail = await _storage.read(key: _emailKey);
    final storedSalt = await _storage.read(key: _saltKey);
    final storedHash = await _storage.read(key: _hashKey);

    if (storedEmail == null) return AuthResult.noAccount;
    if (storedSalt == null || storedHash == null) {
      // An account exists but carries no password material, which only
      // happens for a Google-linked account.
      return AuthResult.useGoogleSignIn;
    }
    if (email.trim().toLowerCase() != storedEmail) {
      return AuthResult.invalidCredentials;
    }

    final computed = _pbkdf2(password, base64Decode(storedSalt));
    if (!_constantTimeEquals(computed, base64Decode(storedHash))) {
      return AuthResult.invalidCredentials;
    }

    await _storage.write(key: _sessionKey, value: 'active');
    return AuthResult.success;
  }

  static Future<bool> isLoggedIn() async =>
      (await _storage.read(key: _sessionKey)) == 'active';

  /// Ends the session. For a Google account the Google session is dropped too —
  /// otherwise "log out" would leave the provider signed in and the next
  /// sign-in would silently reuse the same account with no account chooser.
  static Future<void> logout() async {
    if (await currentProvider() == AuthProvider.google) {
      await GoogleAuthService.signOut();
    }
    // The cloud session goes too. Leaving it behind on a shared or handed-on
    // device would let the next person's sync pull the previous user's
    // history back down.
    await CloudAccountService.signOut();
    await CloudSyncService.resetCursor();
    await _storage.delete(key: _sessionKey);
  }

  /// Removes the local account entirely (used by "reset account").
  static Future<void> deleteAccount() async {
    // Revoke the app's Google access as well, so deleting the account here
    // also removes ScamShield from the user's Google connected-apps list
    // rather than leaving a dangling grant.
    if (await currentProvider() == AuthProvider.google) {
      await GoogleAuthService.disconnect();
    }
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _hashKey);
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _providerKey);
    await _storage.delete(key: _displayNameKey);
    await _storage.delete(key: _photoUrlKey);
  }

  static String messageFor(AuthResult result) {
    switch (result) {
      case AuthResult.success:
        return 'Success.';
      case AuthResult.invalidCredentials:
        return 'Incorrect email or password.';
      case AuthResult.accountExists:
        return 'An account already exists on this device. Please sign in.';
      case AuthResult.noAccount:
        return 'No account found on this device. Please create one first.';
      case AuthResult.weakPassword:
        return 'Password must be at least $_minPasswordLength characters and include letters and numbers.';
      case AuthResult.invalidEmail:
        return 'Please enter a valid email address.';
      case AuthResult.useGoogleSignIn:
        return 'This account was created with Google. Use "Continue with Google" to sign in.';
    }
  }
}
