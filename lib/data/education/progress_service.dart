// lib/data/education/progress_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'models/user_progress.dart';
import 'models/quiz_question.dart';

/// Manages quiz scores, badge unlocks, streaks, and total points.
/// Persists data via [SharedPreferences].
class ProgressService {
  static const _keyProgress = 'user_progress_v1';

  // All available badges
  static const List<Badge> allBadges = [
    Badge(id: 'badge_phishing', name: 'Phish Buster', description: 'Read the Phishing 101 article', emoji: '🎣', pointsRequired: 10),
    Badge(id: 'badge_smishing', name: 'SMS Guardian', description: 'Read the Smishing guide', emoji: '📱', pointsRequired: 10),
    Badge(id: 'badge_vishing', name: 'Call Blocker', description: 'Read the Vishing article', emoji: '📞', pointsRequired: 10),
    Badge(id: 'badge_lottery', name: 'No Free Lunch', description: 'Read the Lottery Scams article', emoji: '🎰', pointsRequired: 10),
    Badge(id: 'badge_job', name: 'Offer Detector', description: 'Read the Fake Job Offers article', emoji: '💼', pointsRequired: 10),
    Badge(id: 'badge_romance', name: 'Heart Shield', description: 'Read the Romance Scams article', emoji: '💔', pointsRequired: 10),
    Badge(id: 'badge_tech', name: 'Tech Detective', description: 'Read the Tech Support Scams article', emoji: '💻', pointsRequired: 10),
    Badge(id: 'badge_invest', name: 'Smart Investor', description: 'Read the Investment Fraud article', emoji: '📈', pointsRequired: 10),
    Badge(id: 'badge_url', name: 'Link Analyst', description: 'Read the URL Deep Dive article', emoji: '🔗', pointsRequired: 10),
    Badge(id: 'badge_bank', name: 'Bank Protector', description: 'Read the Banking Fraud article', emoji: '🏦', pointsRequired: 10),
    Badge(id: 'badge_quiz_pass', name: 'Quiz Master', description: 'Pass a quiz with 70%+ score', emoji: '🏆', pointsRequired: 50),
    Badge(id: 'badge_streak_7', name: 'Week Warrior', description: 'Maintain a 7-day learning streak', emoji: '🔥', pointsRequired: 70),
    Badge(id: 'badge_elite', name: 'Elite Defender', description: 'Reach 90+ vigilance score', emoji: '🛡️', pointsRequired: 100),
  ];

  // ── Load & Save ─────────────────────────────────────────────────────────

  Future<UserProgress> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyProgress);
    if (raw == null) return const UserProgress();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return UserProgress(
        quizzesTaken: map['quizzesTaken'] as int? ?? 0,
        quizzesPassedCount: map['quizzesPassedCount'] as int? ?? 0,
        badgesEarned: List<String>.from(map['badgesEarned'] ?? []),
        streakDays: map['streakDays'] as int? ?? 0,
        lastActiveDate: map['lastActiveDate'] != null
            ? DateTime.tryParse(map['lastActiveDate'])
            : null,
        totalPoints: map['totalPoints'] as int? ?? 0,
        articlesRead: List<String>.from(map['articlesRead'] ?? []),
      );
    } catch (_) {
      return const UserProgress();
    }
  }

  Future<void> _save(UserProgress progress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyProgress,
      jsonEncode({
        'quizzesTaken': progress.quizzesTaken,
        'quizzesPassedCount': progress.quizzesPassedCount,
        'badgesEarned': progress.badgesEarned,
        'streakDays': progress.streakDays,
        'lastActiveDate': progress.lastActiveDate?.toIso8601String(),
        'totalPoints': progress.totalPoints,
        'articlesRead': progress.articlesRead,
      }),
    );
  }

  // ── Article Read ──────────────────────────────────────────────────────────

  /// Records that the user read an article and awards points + badge.
  Future<UserProgress> markArticleRead(String articleId, String badgeId) async {
    final progress = await load();
    if (progress.articlesRead.contains(articleId)) return progress;

    final newBadges = [...progress.badgesEarned];
    if (!newBadges.contains(badgeId)) newBadges.add(badgeId);

    final updated = progress.copyWith(
      articlesRead: [...progress.articlesRead, articleId],
      badgesEarned: newBadges,
      totalPoints: progress.totalPoints + 10,
    );
    await _save(updated);
    return updated;
  }

  // ── Quiz Complete ─────────────────────────────────────────────────────────

  /// Records the completion of a quiz and awards points.
  Future<UserProgress> recordQuizResult(QuizResult result) async {
    final progress = await load();

    final newBadges = [...progress.badgesEarned];
    int pointsEarned = result.correctAnswers * 5;

    if (result.passed && !newBadges.contains('badge_quiz_pass')) {
      newBadges.add('badge_quiz_pass');
      pointsEarned += 50;
    }

    final updated = progress.copyWith(
      quizzesTaken: progress.quizzesTaken + 1,
      quizzesPassedCount:
          result.passed ? progress.quizzesPassedCount + 1 : progress.quizzesPassedCount,
      badgesEarned: newBadges,
      totalPoints: progress.totalPoints + pointsEarned,
    );
    await _save(updated);
    return updated;
  }

  // ── Streak ────────────────────────────────────────────────────────────────

  /// Updates the daily streak. Should be called once per app open.
  Future<UserProgress> updateStreak() async {
    final progress = await load();
    final now = DateTime.now();
    final last = progress.lastActiveDate;

    int newStreak = progress.streakDays;
    if (last == null) {
      newStreak = 1;
    } else {
      final diff = now.difference(last).inDays;
      if (diff == 1) {
        newStreak += 1; // Consecutive day
      } else if (diff > 1) {
        newStreak = 1; // Streak broken
      }
      // diff == 0 means same day — no change
    }

    final newBadges = [...progress.badgesEarned];
    if (newStreak >= 7 && !newBadges.contains('badge_streak_7')) {
      newBadges.add('badge_streak_7');
    }

    final updated = progress.copyWith(
      streakDays: newStreak,
      lastActiveDate: now,
      badgesEarned: newBadges,
    );
    await _save(updated);
    return updated;
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  Future<void> resetProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyProgress);
  }
}
