// lib/services/breach_watch_service.dart
//
// Turns the breach checker from a one-shot lookup into a standing watch.
//
// A breach check is only useful at the moment you run it — the interesting
// event (your address turning up in a *new* dump) happens weeks later, when
// nobody is looking. This keeps the last known breach count per watched
// address and re-checks on app open, so an increase surfaces on its own.
//
// Deliberately re-checks on app open rather than from a background worker:
// a WorkManager job would need a new dependency, a notifications plugin and
// battery-optimisation exemptions to fire reliably on modern Android, for a
// signal that is not time-critical — a data breach discovered on next launch
// is still discovered in good time. If that changes, this service is the
// single place a background scheduler would hook into.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'breach_service.dart';

/// A newly-detected increase in exposures for one watched address.
class BreachAlert {
  final String email;
  final int previousCount;
  final int currentCount;

  const BreachAlert({
    required this.email,
    required this.previousCount,
    required this.currentCount,
  });

  int get newExposures => currentCount - previousCount;
}

class BreachWatchService {
  BreachWatchService._();

  static const String _watchKey = 'scamshield_breach_watchlist';
  static const String _lastCheckedKey = 'scamshield_breach_last_checked';

  /// Don't re-hit the breach API on every single app resume.
  static const Duration _minInterval = Duration(hours: 6);

  /// A hard cap so a long watchlist can't turn app start into a burst of
  /// network calls (and trip the backend's rate limit).
  static const int maxWatched = 5;

  // ── Watchlist storage ─────────────────────────────────────────────────────
  // Stored as {email: lastKnownBreachCount}.

  static Future<Map<String, int>> _readWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_watchKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (e) {
      debugPrint('BreachWatchService: corrupt watchlist, resetting ($e)');
      return {};
    }
  }

  static Future<void> _writeWatchlist(Map<String, int> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_watchKey, jsonEncode(list));
  }

  static Future<List<String>> watchedEmails() async =>
      (await _readWatchlist()).keys.toList();

  static Future<bool> isWatched(String email) async =>
      (await _readWatchlist()).containsKey(email.trim().toLowerCase());

  /// Starts watching [email], seeded with the count we already know so the
  /// very next check doesn't report the existing breaches as "new".
  static Future<bool> watch(String email, int knownBreachCount) async {
    final clean = email.trim().toLowerCase();
    if (clean.isEmpty) return false;

    final list = await _readWatchlist();
    if (!list.containsKey(clean) && list.length >= maxWatched) return false;

    list[clean] = knownBreachCount;
    await _writeWatchlist(list);
    return true;
  }

  static Future<void> unwatch(String email) async {
    final list = await _readWatchlist();
    list.remove(email.trim().toLowerCase());
    await _writeWatchlist(list);
  }

  // ── The check itself ──────────────────────────────────────────────────────

  /// Re-checks every watched address and returns only those whose exposure
  /// count went **up** since last time.
  ///
  /// Returns an empty list — never throws — when there is nothing to check,
  /// the interval hasn't elapsed, or the network is unavailable: a failed
  /// lookup must not be reported to the user as "no new breaches", it is
  /// simply "not checked".
  static Future<List<BreachAlert>> checkForNewBreaches({bool force = false}) async {
    final watchlist = await _readWatchlist();
    if (watchlist.isEmpty) return const [];

    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastCheckedKey) ?? 0;
    final since = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastMs));
    if (!force && since < _minInterval) return const [];

    final alerts = <BreachAlert>[];
    var anySucceeded = false;

    for (final entry in watchlist.entries) {
      try {
        final result = await BreachService.checkEmailBreach(entry.key);
        anySucceeded = true;

        if (result.breachCount > entry.value) {
          alerts.add(BreachAlert(
            email: entry.key,
            previousCount: entry.value,
            currentCount: result.breachCount,
          ));
        }
        // Store the new count either way, so a count that goes up by one
        // isn't re-reported on every subsequent launch.
        watchlist[entry.key] = result.breachCount;
      } catch (e) {
        // One unreachable lookup shouldn't abort the rest of the watchlist.
        debugPrint('BreachWatchService: check failed for ${entry.key} ($e)');
      }
    }

    if (anySucceeded) {
      await _writeWatchlist(watchlist);
      await prefs.setInt(_lastCheckedKey, DateTime.now().millisecondsSinceEpoch);
    }

    return alerts;
  }
}
