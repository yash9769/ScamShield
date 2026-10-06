// lib/services/learning_sync_service.dart
//
// Pushes local learning progress up to the account so it can be ranked and can
// follow the user to a new phone.
//
// One-way on purpose. Progress is earned on a device by actually reading and
// answering things, and the local store is the authoritative record of that.
// Pulling a server copy back down would open a door this feature does not need
// — a points total that can be raised without doing the work — and would
// create a merge problem (which streak wins?) for no user-visible benefit.
// If a user moves phones, the honest answer is that they start their streak
// again; that is a much smaller cost than a leaderboard nobody believes.

import 'package:flutter/foundation.dart';

import '../data/education/progress_service.dart';
import 'cloud_account_service.dart';

class LearningSyncService {
  LearningSyncService._();

  static final ProgressService _progress = ProgressService();

  /// Sends this device's totals. No-ops when signed out — the Learn tab works
  /// perfectly well without an account, and this is the only part that needs
  /// one.
  static Future<bool> push() async {
    if (!CloudAccountService.signedIn.value) return false;
    try {
      final progress = await _progress.load();
      return await CloudAccountService.pushLearningProgress(
        totalPoints: progress.totalPoints,
        streakDays: progress.streakDays,
        badgesEarned: progress.badgesEarned.length,
        quizzesPassed: progress.quizzesPassedCount,
        articlesRead: progress.articlesRead.length,
      );
    } catch (e) {
      debugPrint('LearningSyncService.push failed: $e');
      return false;
    }
  }
}
