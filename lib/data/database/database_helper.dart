// lib/data/database/database_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Singleton SQLite database helper.
/// Manages schema creation and version migrations.
class DatabaseHelper {
  static const _dbName = 'scamshield.db';
  static const _dbVersion = 1;

  // Table names
  static const tableScanRecords = 'scan_records';
  static const tableUserPreferences = 'user_preferences';

  // Column names — scan_records
  static const colId = 'id';
  static const colInputText = 'input_text';
  static const colClassification = 'classification';
  static const colRiskScore = 'risk_score';
  static const colSummary = 'summary';
  static const colTimestamp = 'timestamp';
  static const colIsFlagged = 'is_flagged';
  static const colSource = 'source';

  // Column names — user_preferences
  static const colHasConsented = 'has_consented';
  static const colNotificationsEnabled = 'notifications_enabled';
  static const colDailyTipEnabled = 'daily_tip_enabled';
  static const colAutoDeleteDays = 'auto_delete_days';
  static const colOfflineModeAcknowledged = 'offline_mode_acknowledged';

  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableScanRecords (
        $colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colInputText TEXT NOT NULL,
        $colClassification TEXT NOT NULL,
        $colRiskScore INTEGER NOT NULL DEFAULT 0,
        $colSummary TEXT NOT NULL,
        $colTimestamp TEXT NOT NULL,
        $colIsFlagged INTEGER NOT NULL DEFAULT 0,
        $colSource TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableUserPreferences (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        $colHasConsented INTEGER NOT NULL DEFAULT 0,
        $colNotificationsEnabled INTEGER NOT NULL DEFAULT 1,
        $colDailyTipEnabled INTEGER NOT NULL DEFAULT 1,
        $colAutoDeleteDays INTEGER NOT NULL DEFAULT 0,
        $colOfflineModeAcknowledged INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Seed a single preferences row (id=1 acts as singleton)
    await db.insert(tableUserPreferences, {
      'id': 1,
      colHasConsented: 0,
      colNotificationsEnabled: 1,
      colDailyTipEnabled: 1,
      colAutoDeleteDays: 0,
      colOfflineModeAcknowledged: 0,
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future migrations go here
  }

  /// Closes the database connection. Useful for testing.
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
