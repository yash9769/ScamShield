// lib/screens/leaderboard_screen.dart
//
// Ranks learners by the points they have earned working through the Learn
// section.
//
// ── Why a leaderboard at all ───────────────────────────────────────────────
// Scam awareness is the one defence that keeps working when the app isn't
// running, and it is also the part of this app nobody has any reason to come
// back to. A visible rank, a streak worth not breaking, and a family scope you
// can actually compare against are cheap, well-understood ways to make
// learning something people return to rather than something they do once.
//
// ── Two scopes, one important asymmetry ────────────────────────────────────
// Family scope shows people who have already chosen to share a group with each
// other, so the server may fall back to an email address there when someone
// has no display name. Global scope never does — a stranger's email is not a
// display name, and the server substitutes "ScamShield user" instead. The UI
// does not need to enforce that, but it is worth knowing that the difference
// is deliberate and lives server-side, where it can't be bypassed by a client.

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/motion.dart';
import '../services/cloud_account_service.dart';
import '../services/learning_sync_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _loading = true;
  String _scope = 'global';
  List<LeaderboardEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Re-resolve first: the notifier can be stale if the user signed in from
    // another screen, and it decides which empty state is shown below.
    await CloudAccountService.refreshSignedInState();
    // Push this device's progress, so the user's own row reflects the quiz
    // they just finished rather than whatever was last synced.
    await LearningSyncService.push();
    final entries = await CloudAccountService.fetchLeaderboard(scope: _scope);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Reveal(delay: Reveal.step(0), child: _buildScopeSelector()),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (!CloudAccountService.signedIn.value)
              _buildSignedOut()
            else if (_entries == null)
              _buildUnavailable()
            else if (_entries!.isEmpty)
              _buildEmpty()
            else
              ..._buildRows(_entries!),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeSelector() {
    return Row(
      children: [
        for (final scope in const ['global', 'family']) ...[
          Expanded(
            child: GestureDetector(
              onTap: _loading
                  ? null
                  : () {
                      setState(() => _scope = scope);
                      _load();
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _scope == scope ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  scope == 'global' ? 'Everyone' : 'My family',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _scope == scope ? Colors.black : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),
          if (scope == 'global') const SizedBox(width: 8),
        ],
      ],
    );
  }

  List<Widget> _buildRows(List<LeaderboardEntry> entries) {
    return [
      ...entries.asMap().entries.map(
            (e) => Reveal(
              delay: Reveal.step(e.key + 1, stepMs: 45),
              child: _buildRow(e.value),
            ),
          ),
      const SizedBox(height: 20),
      const Text(
        'Points come from articles read and quizzes passed in the Learn tab. '
        'Nothing you have scanned is ever shown here.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.4),
      ),
    ];
  }

  Widget _buildRow(LeaderboardEntry entry) {
    // The top three get a medal tint; everyone else gets a plain rank. Past
    // third place the colour is decoration, not information.
    final Color rankColor = switch (entry.rank) {
      1 => const Color(0xFFFFD75E),
      2 => const Color(0xFFC7CDD6),
      3 => const Color(0xFFCE8946),
      _ => AppColors.textSecondary,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: entry.isYou
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.55))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${entry.rank}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: rankColor,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isYou ? '${entry.displayName} (you)' : entry.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: entry.isYou ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${entry.badgesEarned} badge(s) · ${entry.streakDays}-day streak',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '${entry.totalPoints}',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignedOut() => _notice(
        icon: Icons.person_outline,
        color: AppColors.primary,
        title: 'Sign in to see the leaderboard',
        body: 'Ranking needs an account so your progress can follow you between '
            'devices. Everything in the Learn tab works without one.',
      );

  Widget _buildEmpty() => _notice(
        icon: Icons.emoji_events_outlined,
        color: AppColors.textSecondary,
        title: 'Nobody on the board yet',
        body: 'Read an article or pass a quiz in the Learn tab and you will be '
            'the first name here.',
      );

  Widget _buildUnavailable() => _notice(
        icon: Icons.cloud_off,
        color: AppColors.warning,
        title: 'Leaderboard is unavailable',
        body: 'Could not reach the ScamShield service. Pull down to try again — '
            'your progress is stored on this device either way.',
      );

  Widget _notice({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }
}
