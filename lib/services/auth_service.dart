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

enum AuthResult { success, invalidCredentials, accountExists, noAccount, weakPassword, invalidEmail }

class AuthService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _emailKey = 'scamshield_auth_email';
  static const String _saltKey = 'scamshield_auth_salt';
  static const String _hashKey = 'scamshield_auth_hash';
  static const String _sessionKey = 'scamshield_auth_session';

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

  static Future<bool> hasAccount() async =>
      (await _storage.read(key: _hashKey)) != null;

  static Future<String?> registeredEmail() async =>
      await _storage.read(key: _emailKey);

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
    await _storage.write(key: _sessionKey, value: 'active');
    return AuthResult.success;
  }

  static Future<AuthResult> login(String email, String password) async {
    final storedEmail = await _storage.read(key: _emailKey);
    final storedSalt = await _storage.read(key: _saltKey);
    final storedHash = await _storage.read(key: _hashKey);

    if (storedEmail == null || storedSalt == null || storedHash == null) {
      return AuthResult.noAccount;
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

  static Future<void> logout() async => _storage.delete(key: _sessionKey);

  /// Removes the local account entirely (used by "reset account").
  static Future<void> deleteAccount() async {
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _hashKey);
    await _storage.delete(key: _sessionKey);
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
    }
  }
}
