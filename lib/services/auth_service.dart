// lib/services/auth_service.dart
// Local account & session management for ScamShield.
// Accounts are stored on-device with hashed passwords; the active session
// is persisted so users stay signed in across app restarts.

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const _sessionKey = 'scamshield_session_email';
  static const _accountKey = 'scamshield_account';

  /// Whether a signed-in session currently exists.
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionKey) != null;
  }

  /// Email address of the active session, if any.
  static Future<String?> currentEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionKey);
  }

  /// The locally registered account, or null if none was ever created.
  static Future<Map<String, String>?> getAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
    } catch (_) {
      return null;
    }
  }

  static String _hashPassword(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  /// Creates a new local account. Returns an error message, or null on success.
  static Future<String?> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanEmail = email.trim().toLowerCase();
    final existing = await getAccount();
    if (existing != null && existing['email'] == cleanEmail) {
      return 'An account with this email already exists. Please sign in instead.';
    }
    await prefs.setString(
      _accountKey,
      jsonEncode({
        'name': name.trim(),
        'email': cleanEmail,
        'password': _hashPassword(password),
      }),
    );
    return null;
  }

  /// Signs the user in. Validates against the registered account when one
  /// exists; otherwise auto-provisions a session so the app works out of the
  /// box. Returns an error message, or null on success.
  static Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanEmail = email.trim().toLowerCase();
    final account = await getAccount();

    if (account != null) {
      if (account['email'] != cleanEmail) {
        return 'No account found for this email. Please create one first.';
      }
      if (account['password'] != _hashPassword(password)) {
        return 'Incorrect password. Please try again.';
      }
      await prefs.setString(_sessionKey, cleanEmail);
      return null;
    }

    // First-time user: persist the account and open a session.
    await prefs.setString(
      _accountKey,
      jsonEncode({
        'name': cleanEmail.split('@').first,
        'email': cleanEmail,
        'password': _hashPassword(password),
      }),
    );
    await prefs.setString(_sessionKey, cleanEmail);
    return null;
  }

  /// Clears the active session.
  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
}
