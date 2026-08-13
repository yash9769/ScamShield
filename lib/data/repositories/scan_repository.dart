// lib/data/repositories/scan_repository.dart

import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/scan_record.dart';
import '../cache/local_cache.dart';

/// Repository for all CRUD operations on [ScanRecord].
/// All public methods are async and interact with SQLite via [DatabaseHelper].
class ScanRepository {
  final DatabaseHelper _dbHelper;
  final LocalCache<List<ScanRecord>> _cache;

  static const _cacheKey = 'scan_history';

  ScanRepository({
    DatabaseHelper? dbHelper,
    LocalCache<List<ScanRecord>>? cache,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _cache = cache ?? LocalCache();

  // ── Save ─────────────────────────────────────────────────────────────────

  /// Inserts a new [ScanRecord] and returns the auto-generated id.
  Future<int> saveScan(ScanRecord record) async {
    final db = await _dbHelper.database;
    final id = await db.insert(
      DatabaseHelper.tableScanRecords,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _cache.invalidate(_cacheKey);
    return id;
  }

  // ── Load History ─────────────────────────────────────────────────────────

  /// Returns all scans ordered by most-recent first.
  Future<List<ScanRecord>> loadHistory({int? limit}) async {
    if (_cache.get(_cacheKey) != null && limit == null) {
      return _cache.get(_cacheKey)!;
    }
    final db = await _dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.tableScanRecords,
      orderBy: '${DatabaseHelper.colTimestamp} DESC',
      limit: limit,
    );
    final records = maps.map(ScanRecord.fromMap).toList();
    if (limit == null) _cache.set(_cacheKey, records);
    return records;
  }

  // ── Search ────────────────────────────────────────────────────────────────

  /// Full-text search on input_text and summary columns.
  Future<List<ScanRecord>> searchScans(String query) async {
    if (query.trim().isEmpty) return loadHistory();
    final db = await _dbHelper.database;
    final pattern = '%${query.toLowerCase()}%';
    final maps = await db.query(
      DatabaseHelper.tableScanRecords,
      where:
          'LOWER(${DatabaseHelper.colInputText}) LIKE ? OR LOWER(${DatabaseHelper.colSummary}) LIKE ?',
      whereArgs: [pattern, pattern],
      orderBy: '${DatabaseHelper.colTimestamp} DESC',
    );
    return maps.map(ScanRecord.fromMap).toList();
  }

  // ── Filter ────────────────────────────────────────────────────────────────

  /// Returns scans filtered by [classification] ('scam', 'suspicious', 'safe').
  Future<List<ScanRecord>> filterByClassification(
      String classification) async {
    if (classification == 'all') return loadHistory();
    final db = await _dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.tableScanRecords,
      where: '${DatabaseHelper.colClassification} = ?',
      whereArgs: [classification],
      orderBy: '${DatabaseHelper.colTimestamp} DESC',
    );
    return maps.map(ScanRecord.fromMap).toList();
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  /// Deletes a single scan by its [id].
  Future<void> deleteScan(int id) async {
    final db = await _dbHelper.database;
    await db.delete(
      DatabaseHelper.tableScanRecords,
      where: '${DatabaseHelper.colId} = ?',
      whereArgs: [id],
    );
    _cache.invalidate(_cacheKey);
  }

  /// Deletes ALL scan records. Used for "Clear History" and "Delete All Data".
  Future<void> clearHistory() async {
    final db = await _dbHelper.database;
    await db.delete(DatabaseHelper.tableScanRecords);
    _cache.invalidate(_cacheKey);
  }

  /// Deletes records older than [days] days. Called by auto-delete job.
  Future<int> deleteOlderThan(int days) async {
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).toIso8601String();
    final db = await _dbHelper.database;
    final count = await db.delete(
      DatabaseHelper.tableScanRecords,
      where: '${DatabaseHelper.colTimestamp} < ?',
      whereArgs: [cutoff],
    );
    _cache.invalidate(_cacheKey);
    return count;
  }


  // ── Aliases used by HistoryScreen ─────────────────────────────────────────

  /// Deletes a single scan by id (alias for [deleteScan]).
  Future<void> deleteById(int id) => deleteScan(id);

  /// Deletes all history (alias for [clearHistory]).
  Future<void> clearAll() => clearHistory();

  // ── Statistics ────────────────────────────────────────────────────────────

  /// Computes aggregated [ScanStatistics] over all records.
  Future<ScanStatistics> getStatistics() async {
    final db = await _dbHelper.database;

    final totalResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM ${DatabaseHelper.tableScanRecords}');
    final total = (totalResult.first['count'] as int?) ?? 0;

    if (total == 0) {
      return const ScanStatistics(
        totalScans: 0,
        scamCount: 0,
        suspiciousCount: 0,
        safeCount: 0,
        averageRiskScore: 0,
      );
    }

    final classResult = await db.rawQuery('''
      SELECT classification, COUNT(*) as count
      FROM ${DatabaseHelper.tableScanRecords}
      GROUP BY classification
    ''');

    int scam = 0, suspicious = 0, safe = 0;
    for (final row in classResult) {
      switch (row['classification']) {
        case 'scam':
          scam = row['count'] as int;
          break;
        case 'suspicious':
          suspicious = row['count'] as int;
          break;
        case 'safe':
          safe = row['count'] as int;
          break;
      }
    }

    final avgResult = await db.rawQuery(
        'SELECT AVG(${DatabaseHelper.colRiskScore}) as avg FROM ${DatabaseHelper.tableScanRecords}');
    final avg = (avgResult.first['avg'] as double?) ?? 0.0;

    return ScanStatistics(
      totalScans: total,
      scamCount: scam,
      suspiciousCount: suspicious,
      safeCount: safe,
      averageRiskScore: avg,
    );
  }
}
