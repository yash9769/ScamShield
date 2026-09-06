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

  /// The server rejects any single request carrying more than this many scans
  /// outright (`MAX_SYNC_BATCH` in server/accounts.py) — see the chunking
  /// below.
  static const int _maxBatch = 200;

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
      final entries = localById.entries.toList();

      final since = prefs.getDouble(_sinceKey) ?? 0.0;
      final deviceId = await _deviceId();

      // Every local scan is sent on every sync (there's no local record yet
      // of which ones the server has already accepted), which is why this
      // has to go up in chunks at all: an account with more than
      // `_maxBatch` scans would otherwise send one oversized request the
      // server always rejects, and syncing would fail — permanently, since
      // nothing here ever shrinks the payload — for every account past that
      // size. Sending the same already-synced rows again each time is
      // wasted bandwidth rather than a correctness problem: the server's
      // `ON CONFLICT ... DO UPDATE` upserts them idempotently.
      var pushed = 0;
      var pulled = 0;
      double? serverTime;
      var reachedServer = false;
      var allChunksSucceeded = true;

      for (var i = 0; i < entries.length || i == 0; i += _maxBatch) {
        final end = (i + _maxBatch < entries.length) ? i + _maxBatch : entries.length;
        final chunk = entries.sublist(i, end);
        final payload = chunk
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

        // Only the first request carries the real cursor and is the one
        // whose response is read for what changed server-side; later chunks
        // are pure pushes, so a far-future `since` (same trick pushTombstones
        // uses) keeps the server from handing back a pull result nothing
        // here would look at twice.
        final result = await CloudAccountService.syncScans(
          scans: payload,
          since: i == 0 ? since : 9999999999.0,
          deviceId: deviceId,
          deviceName: 'Android device',
        );

        if (result == null) {
          allChunksSucceeded = false;
          if (!reachedServer) {
            return const SyncOutcome(
              ran: false,
              message: 'Could not reach the sync service. Your scans are still saved on this device.',
            );
          }
          // Later chunk failed after earlier ones already landed — stop here
          // rather than lose track of the response already in hand; whatever
          // didn't get pushed this time goes up on the next sync.
          break;
        }
        reachedServer = true;
        pushed += (result['accepted'] as num?)?.toInt() ?? 0;

        if (i == 0) {
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
          serverTime = (result['server_time'] as num?)?.toDouble();
        }
      }

      // The pull cursor only reflects what was already pulled (from the
      // first, always-attempted chunk), so it advances regardless of
      // whether a later push chunk failed — that failure is about data still
      // waiting to go up, not about anything already read down.
      if (serverTime != null) await prefs.setDouble(_sinceKey, serverTime);
      await prefs.setInt(_lastRunKey, DateTime.now().millisecondsSinceEpoch);

      return SyncOutcome(
        ran: true,
        pushed: pushed,
        pulled: pulled,
        message: allChunksSucceeded
            ? null
            : 'Only part of your scan history synced this time — the rest will go up next time.',
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

  /// The server-side counterpart of every place [records] can be deleted:
  /// the History screen (single delete, "Reset All"), configured retention
  /// cleanup, and Settings > Privacy & Data > Delete My Data.
  ///
  /// [sync] only ever pushes rows as `deleted: false` — it has no concept of
  /// a local deletion at all. Left as-is, that means deleting a scan on the
  /// device does not delete the copy this account already pushed to the
  /// server on an earlier sync: the server row sits there untouched, and
  /// worse, a full re-pull (a new device signing in, or [resetCursor] being
  /// called) hands it straight back down — a "deleted" scan that quietly
  /// reappears is not a sync bug, it is an erasure that didn't happen. This
  /// closes that gap by pushing an explicit tombstone for exactly the records
  /// being removed, at the moment they're removed, rather than leaving the
  /// server to infer a deletion it has no way to observe.
  ///
  /// Best-effort and silent: a signed-out user or an unreachable server must
  /// never turn a local deletion — which has already fully succeeded — into
  /// something that looks like it failed. If this doesn't get through, the
  /// row is stale on the server until the next successful call, not silently
  /// lost track of forever; nothing here is the only copy of the tombstone
  /// intent, since it's derived fresh from local state every time it runs.
  static Future<void> pushTombstones(List<ScanRecord> records) async {
    if (records.isEmpty) return;
    if (!CloudAccountService.signedIn.value) return;

    // Chunked to respect the server's MAX_SYNC_BATCH (200) — "Delete My
    // Data" / "Reset All" can hand this hundreds of records at once.
    const chunkSize = 200;
    for (var i = 0; i < records.length; i += chunkSize) {
      final chunk = records.sublist(i, i + chunkSize > records.length ? records.length : i + chunkSize);
      final payload = chunk
          .map((r) => {
                'id': cloudIdFor(r),
                'input_text': '',
                'classification': r.classification,
                'risk_score': 0,
                'summary': '',
                'source': r.source,
                'scanned_at': r.timestamp.toIso8601String(),
                'deleted': true,
              })
          .toList();
      try {
        // A far-future `since` means "nothing has changed since then" to the
        // server, so the response comes back empty — this call only pushes,
        // it was never going to do anything with a pull result anyway, and a
        // real `since` here would otherwise hand back the account's entire
        // history for no reason.
        await CloudAccountService.syncScans(
          scans: payload,
          since: 9999999999.0,
        );
      } catch (e) {
        debugPrint('CloudSyncService.pushTombstones failed for one batch: $e');
      }
    }
  }
}
