// lib/data/repositories/preferences_repository.dart

import '../database/database_helper.dart';
import '../models/user_preferences.dart';

/// Repository for reading and writing [UserPreferences] in SQLite.
class PreferencesRepository {
  final DatabaseHelper _dbHelper;

  PreferencesRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  /// Loads the singleton preferences row (id = 1).
  Future<UserPreferences> load() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.tableUserPreferences,
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (maps.isEmpty) return const UserPreferences();
    return UserPreferences.fromMap(maps.first);
  }

  /// Updates the preferences row with values from [prefs].
  Future<void> save(UserPreferences prefs) async {
    final db = await _dbHelper.database;
    await db.update(
      DatabaseHelper.tableUserPreferences,
      prefs.toMap(),
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  /// Convenience: set consent flag only.
  Future<void> setConsent(bool value) async {
    final current = await load();
    await save(current.copyWith(hasConsented: value));
  }

  /// Convenience: set auto-delete period.
  Future<void> setAutoDelete(int days) async {
    final current = await load();
    await save(current.copyWith(autoDeleteDays: days));
  }

  /// Records that the user affirmatively agreed to [policyVersion] just now.
  Future<void> grantConsent(String policyVersion) async {
    final current = await load();
    await save(current.copyWith(
      hasConsented: true,
      consentVersion: policyVersion,
      consentTimestamp: DateTime.now().toIso8601String(),
    ));
  }

  /// Convenience: toggle the optional AI-processing consent.
  Future<void> setAiProcessingEnabled(bool value) async {
    final current = await load();
    await save(current.copyWith(aiProcessingEnabled: value));
  }

  /// Resets all preferences to defaults.
  Future<void> resetToDefaults() async {
    await save(const UserPreferences());
  }
}
