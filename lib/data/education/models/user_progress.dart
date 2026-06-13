// lib/data/education/models/user_progress.dart

/// Tracks a user's learning progress within the Education Module.
class UserProgress {
  final int quizzesTaken;
  final int quizzesPassedCount;
  final List<String> badgesEarned; // badge ids
  final int streakDays;
  final DateTime? lastActiveDate;
  final int totalPoints;
  final List<String> articlesRead; // article ids

  const UserProgress({
    this.quizzesTaken = 0,
    this.quizzesPassedCount = 0,
    this.badgesEarned = const [],
    this.streakDays = 0,
    this.lastActiveDate,
    this.totalPoints = 0,
    this.articlesRead = const [],
  });

  int get vigilanceScore {
    // Normalise to 0–100
    final raw = (totalPoints * 0.5 + streakDays * 2 + articlesRead.length * 3)
        .round();
    return raw.clamp(0, 100);
  }

  String get rank {
    final s = vigilanceScore;
    if (s >= 90) return 'Elite Defender';
    if (s >= 70) return 'Advanced Protector';
    if (s >= 50) return 'Aware Guardian';
    if (s >= 30) return 'Rookie Shield';
    return 'Newcomer';
  }

  UserProgress copyWith({
    int? quizzesTaken,
    int? quizzesPassedCount,
    List<String>? badgesEarned,
    int? streakDays,
    DateTime? lastActiveDate,
    int? totalPoints,
    List<String>? articlesRead,
  }) {
    return UserProgress(
      quizzesTaken: quizzesTaken ?? this.quizzesTaken,
      quizzesPassedCount: quizzesPassedCount ?? this.quizzesPassedCount,
      badgesEarned: badgesEarned ?? this.badgesEarned,
      streakDays: streakDays ?? this.streakDays,
      lastActiveDate: lastActiveDate ?? this.lastActiveDate,
      totalPoints: totalPoints ?? this.totalPoints,
      articlesRead: articlesRead ?? this.articlesRead,
    );
  }
}

/// A badge definition shown in the Education module.
class Badge {
  final String id;
  final String name;
  final String description;
  final String emoji;
  final int pointsRequired;

  const Badge({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.pointsRequired,
  });
}
