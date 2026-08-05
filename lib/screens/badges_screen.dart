// lib/screens/badges_screen.dart
// Badges & achievements display backed by real ProgressService data.

import 'package:flutter/material.dart' hide Badge;
import '../theme.dart';
import '../data/education/progress_service.dart';
import '../data/education/models/user_progress.dart';

class BadgesScreen extends StatefulWidget {
  const BadgesScreen({super.key});

  @override
  State<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends State<BadgesScreen> {
  final ProgressService _progressService = ProgressService();

  UserProgress? _progress;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final progress = await _progressService.load();
    if (mounted) {
      setState(() {
        _progress = progress;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final progress = _progress!;
    final earnedCount = progress.badgesEarned.length;
    final totalCount = ProgressService.allBadges.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Badges & Achievements', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSummaryCard(progress, earnedCount, totalCount),
            const SizedBox(height: 24),
            const Text(
              'ALL BADGES',
              style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...ProgressService.allBadges.map((badge) {
              final isEarned = progress.badgesEarned.contains(badge.id);
              return _buildBadgeCard(badge, isEarned);
            }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(UserProgress progress, int earnedCount, int totalCount) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.15), AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.military_tech_rounded, color: AppColors.primary, size: 32),
              const SizedBox(width: 8),
              Text(
                '$earnedCount / $totalCount',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Badges Earned', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: totalCount == 0 ? 0 : earnedCount / totalCount,
              minHeight: 8,
              backgroundColor: Colors.black.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _summaryStat('${progress.totalPoints}', 'POINTS'),
              _summaryStat('${progress.quizzesTaken}', 'QUIZZES'),
              _summaryStat('${progress.streakDays}', 'DAY STREAK'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildBadgeCard(Badge badge, bool isEarned) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEarned ? AppColors.primary.withValues(alpha: 0.4) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: isEarned ? 1.0 : 0.25,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isEarned ? AppColors.primary.withValues(alpha: 0.12) : AppColors.background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isEarned ? AppColors.primary.withValues(alpha: 0.4) : Colors.transparent,
                ),
              ),
              child: Center(
                child: Text(badge.emoji, style: const TextStyle(fontSize: 26)),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      badge.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isEarned ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                    if (isEarned) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.verified_rounded, color: AppColors.success, size: 16),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  badge.description,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            isEarned ? 'EARNED' : '+${badge.pointsRequired}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isEarned ? AppColors.success : AppColors.textSecondary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
