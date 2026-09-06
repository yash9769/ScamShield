// lib/screens/home_screen.dart
//
// ── What this screen used to be, and why it changed ──────────────────────────
// The previous Home was a security dashboard: a 140px pulsing shield inside an
// ambient radar sweep, a "SHIELD ACTIVE / ECOSYSTEM" badge, a 2×2 grid of four
// stat cards, and a banner listing the engineering ("Androguard + YARA",
// "Zero dummy data"). Roughly the whole first screen was spent before anything
// the user could act on appeared.
//
// None of that answered the question people open this app with, which is
// always the same one: *is this thing I just received safe?*
//
// So the order is inverted. The scan entry point is the first thing on the
// screen and is a real target, not a button that opens a sheet of more buttons.
// Status is one honest sentence instead of a badge and an animation. The four
// vanity stats collapse to the two numbers that mean something, on one line.
// The engineering brag list is gone — it was a README rendered as UI.

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/scan_now_bottom_sheet.dart';
import '../widgets/motion.dart';
import '../widgets/ui_kit.dart';
import '../services/user_profile_service.dart';
import 'sim_lock_screen.dart';
import 'breach_screen.dart';
import 'safe_vault_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import '../data/repositories/scan_repository.dart';
import '../data/models/scan_record.dart';
import '../services/data_change_notifier.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScanRepository _repo = ScanRepository();
  ScanStatistics? _stats;
  List<ScanRecord> _recent = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
    // See data_change_notifier.dart: this screen stays alive in
    // MainNavigation's IndexedStack, so it needs an explicit signal to
    // refresh after a scan/deletion made from another tab or screen.
    DataChangeNotifier.version.addListener(_loadStats);
  }

  @override
  void dispose() {
    DataChangeNotifier.version.removeListener(_loadStats);
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await _repo.getStatistics();
      final recent = await _repo.loadHistory(limit: 3);
      if (mounted) setState(() { _stats = stats; _recent = recent; });
    } catch (_) {}
  }

  void _openHistory() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()))
        .then((_) => _loadStats());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.screen,
        title: const Text('ScamShield'),
        actions: [
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))
                  .then((_) => _loadStats());
            },
            child: ValueListenableBuilder<String>(
              valueListenable: UserProfileService.avatarNotifier,
              builder: (ctx, avatar, _) => CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.surfaceLight,
                backgroundImage: NetworkImage(avatar),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.screen),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.huge,
          ),
          children: [
            Reveal(delay: Reveal.step(0), child: _buildScanPrompt()),
            const SizedBox(height: AppSpacing.xxl),
            Reveal(delay: Reveal.step(1), child: _buildStatusLine()),
            const SizedBox(height: AppSpacing.xxxl),
            Reveal(
              delay: Reveal.step(2),
              child: AppSection(
                label: 'Also check',
                child: _buildTools(context),
              ),
            ),
            const SizedBox(height: AppSpacing.xxxl),
            Reveal(
              delay: Reveal.step(3),
              child: AppSection(
                label: 'Recent checks',
                actionLabel: _recent.isEmpty ? null : 'See all',
                onAction: _recent.isEmpty ? null : _openHistory,
                child: _buildRecent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The primary action, first on the screen.
  ///
  /// Styled as an input rather than a button because that is what it leads to
  /// and what it invites — a field you paste into reads as "put the message
  /// here", where a button labelled SCAN NOW reads as "something will happen,
  /// unclear what". The tap target is the whole card.
  Widget _buildScanPrompt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Is this a scam?', style: AppText.title),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Paste a message, link or number and get an answer in seconds.',
          style: AppText.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          onTap: () => ScanNowBottomSheet.show(context),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.lg,
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text('Check a message or link', style: AppText.body),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Text(
                  'Check',
                  style: TextStyle(
                    color: Color(0xFF08121F),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One line of honest status.
  ///
  /// The old version had a permanent "SHIELD ACTIVE" badge that said the same
  /// thing whether the user had run zero scans or four hundred, plus four stat
  /// cards including "AVG RISK SCORE" — a number nobody can act on. What is
  /// left is what a person would actually want to know: how much have I
  /// checked, and did any of it turn out to be bad.
  Widget _buildStatusLine() {
    final s = _stats;
    final total = s?.totalScans ?? 0;
    final caught = (s?.scamCount ?? 0) + (s?.suspiciousCount ?? 0);

    if (total == 0) {
      return AppCard(
        child: Row(
          children: [
            const Icon(Icons.shield_outlined, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'Nothing checked yet. Your first scan takes about five seconds.',
                style: AppText.secondary,
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      onTap: _openHistory,
      child: Row(
        children: [
          _stat('$total', total == 1 ? 'message checked' : 'messages checked'),
          Container(
            width: 1,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            color: AppColors.surfaceLight,
          ),
          _stat(
            '$caught',
            caught == 1 ? 'threat found' : 'threats found',
            // The only place a verdict colour appears outside an actual
            // verdict — and only when the number is non-zero, so it never
            // colours a reassuring "0".
            color: caught > 0 ? AppColors.warning : null,
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textSecondary, size: 22),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppText.display.copyWith(
            fontSize: 26,
            color: color ?? AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: AppText.caption),
      ],
    );
  }

  /// The secondary tools, as labelled rows rather than a row of cryptic icons.
  ///
  /// "SIM LOCK" and "BREACHES" under 65px tiles told you nothing about what
  /// tapping would do. A row with a sentence under it costs a little more
  /// vertical space and removes the guessing.
  Widget _buildTools(BuildContext context) {
    return AppListGroup(
      children: [
        AppListRow(
          icon: Icons.mark_email_unread_outlined,
          title: 'Was my email leaked?',
          subtitle: 'Check an address against known data breaches',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const BreachScreen(initialIndex: 0))),
        ),
        AppListRow(
          icon: Icons.public_outlined,
          title: 'Recent breaches',
          subtitle: 'What has leaked lately, and who it affects',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const BreachScreen(initialIndex: 1))),
        ),
        AppListRow(
          icon: Icons.lock_outline_rounded,
          title: 'Safe Vault',
          subtitle: 'Notes and codes, encrypted on this device',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SafeVaultScreen())),
        ),
        AppListRow(
          icon: Icons.sim_card_outlined,
          title: 'Device check',
          subtitle: 'SIM and device security status',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SimLockScreen())),
        ),
      ],
    );
  }

  Widget _buildRecent() {
    if (_recent.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: 'Nothing checked yet',
        message: 'Anything you check will show up here so you can find it again.',
        actionLabel: 'Check something now',
        onAction: () => ScanNowBottomSheet.show(context),
      );
    }

    return AppListGroup(
      children: _recent.map(_recentRow).toList(),
    );
  }

  Widget _recentRow(ScanRecord r) {
    final v = verdictStyleFor(r.classification);
    final diff = DateTime.now().difference(r.timestamp);
    final timeStr = diff.inMinutes < 1
        ? 'Just now'
        : diff.inHours < 1
            ? '${diff.inMinutes}m ago'
            : diff.inDays < 1
                ? '${diff.inHours}h ago'
                : '${diff.inDays}d ago';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openHistory,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: v.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(v.icon, color: v.color, size: 19),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          v.label,
                          style: AppText.subheading.copyWith(color: v.color, fontSize: 15),
                        ),
                        const Spacer(),
                        Text(timeStr, style: AppText.caption),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.inputText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.secondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
