// lib/services/cloud_sync_service.dart
//
// Bridges the local SQLite scan history to the server's sync endpoint.
//
// ── Why content-derived ids ──────────────────────────────────────────────────
// Local rows are keyed by a SQLite autoincrement int, which is meaningless on
// another device — row 4 on your phone is a different scan from row 4 on your
// tablet. The server therefore needs a stable, device-independent id.
//
// Rather than migrate the local schema to add a cloud_id column (a migration
// on a table already holding real user history), the id is derived from the
// record's own immutable content: SHA-256 over text + timestamp + source. Two
// devices that hold the same scan compute the same id, so it deduplicates
// naturally, and a reinstall that restores the same rows doesn't fork them.
// Scan records are never edited after being written, so the id is stable.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/scan_record.dart';
import '../data/repositories/scan_repository.dart';
import 'cloud_account_service.dart';

class SyncOutcome {
  final bool ran;
  final int pushed;
  final int pulled;
  final String? message;

  const SyncOutcome({
    required this.ran,
    this.pushed = 0,
    this.pulled = 0,
    this.message,
  });

  static const skipped = SyncOutcome(ran: false);
}

class CloudSyncService {
  CloudSyncService._();

  static const String _sinceKey = 'scamshield_sync_since';
  static const String _deviceIdKey = 'scamshield_sync_device_id';

  /// Don't hammer the endpoint on every screen that happens to refresh.
  static const Duration _minInterval = Duration(minutes: 5);
  static const String _lastRunKey = 'scamshield_sync_last_run';

  static final ScanRepository _repo = ScanRepository();

  /// Lets the UI show "syncing…" without threading state through every screen.
  static final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  static String cloudIdFor(ScanRecord record) {
    final material = '${record.inputText}|${record.timestamp.toIso8601String()}|${record.source ?? ''}';
    return sha256.convert(utf8.encode(material)).toString().substring(0, 32);
  }

  static Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      // Random per install, and never sent anywhere but this user's own
      // account — it exists to label devices in the sync list, not to track.
      id = sha256
          .convert(utf8.encode('${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(prefs)}'))
          .toString()
          .substring(0, 24);
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  /// Runs a two-way sync. Safe to call often — it self-rate-limits and returns
  /// [SyncOutcome.skipped] when there's no cloud session.
  static Future<SyncOutcome> sync({bool force = false}) async {
    if (!CloudAccountService.signedIn.value) return SyncOutcome.skipped;
    if (isSyncing.value) return SyncOutcome.skipped;

    final prefs = await SharedPreferences.getInstance();
    final lastRun = prefs.getInt(_lastRunKey) ?? 0;
    final elapsed = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastRun));
    if (!force && elapsed < _minInterval) return SyncOutcome.skipped;

    isSyncing.value = true;
    try {
      final localRecords = await _repo.loadHistory();
      final localById = <String, ScanRecord>{
        for (final r in localRecords) cloudIdFor(r): r,
      };

      final payload = localById.entries
          .map((e) => {
                'id': e.key,
                'input_text': e.value.inputText,
                'classification': e.value.classification,
                'risk_score': e.value.riskScore,
                'summary': e.value.summary,
                'source': e.value.source,
                'scanned_at': e.value.timestamp.toIso8601String(),
                'deleted': false,
              })
          .toList();

      final since = prefs.getDouble(_sinceKey) ?? 0.0;
      final result = await CloudAccountService.syncScans(
        scans: payload,
        since: since,
        deviceId: await _deviceId(),
        deviceName: 'Android device',
      );

      if (result == null) {
        return const SyncOutcome(
          ran: false,
          message: 'Could not reach the sync service. Your scans are still saved on this device.',
        );
      }

      var pulled = 0;
      final remoteScans = (result['scans'] as List?) ?? [];
      for (final raw in remoteScans) {
        final scan = raw as Map<String, dynamic>;
        final id = scan['id'] as String? ?? '';
        if (id.isEmpty) continue;
        if (scan['deleted'] == true) continue; // tombstone: nothing to insert
        if (localById.containsKey(id)) continue; // already here

        final scannedAt = DateTime.tryParse(scan['scanned_at'] as String? ?? '');
        await _repo.saveScan(ScanRecord(
          inputText: scan['input_text'] as String? ?? '',
          classification: scan['classification'] as String? ?? 'safe',
          riskScore: (scan['risk_score'] as num?)?.toInt() ?? 0,
          summary: scan['summary'] as String? ?? '',
          timestamp: scannedAt ?? DateTime.now(),
          source: scan['source'] as String?,
        ));
        pulled++;
      }

      final serverTime = (result['server_time'] as num?)?.toDouble();
      if (serverTime != null) await prefs.setDouble(_sinceKey, serverTime);
      await prefs.setInt(_lastRunKey, DateTime.now().millisecondsSinceEpoch);

      return SyncOutcome(
        ran: true,
        pushed: (result['accepted'] as num?)?.toInt() ?? 0,
        pulled: pulled,
      );
    } catch (e) {
      debugPrint('CloudSyncService.sync failed: $e');
      return const SyncOutcome(ran: false, message: 'Sync failed. Your scans are safe on this device.');
    } finally {
      isSyncing.value = false;
    }
  }

  /// Clears the sync cursor so the next sync re-pulls everything. Used after
  /// signing out, so a different account doesn't inherit this one's cursor.
  static Future<void> resetCursor() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sinceKey);
    await prefs.remove(_lastRunKey);
  }
}
