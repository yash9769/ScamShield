// lib/screens/home_screen.dart
//
// Premium cybersecurity command centre - redesigned home dashboard with
// animated radar, comprehensive protection status, statistics, quick actions,
// and recent activity feed. Maintains all existing functionality while
// delivering a visually stunning, modern security experience.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/scan_now_bottom_sheet.dart';
import '../widgets/motion.dart';
import '../widgets/ui_kit.dart';
import '../widgets/animated_radar.dart';
import '../services/user_profile_service.dart';
import 'sim_lock_screen.dart';
import 'breach_screen.dart';
import 'safe_vault_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import '../data/repositories/scan_repository.dart';
import '../data/models/scan_record.dart';
import '../services/scam_detector.dart';
import '../services/data_change_notifier.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final ScanRepository _repo = ScanRepository();
  ScanStatistics? _stats;
  List<ScanRecord> _recent = [];
  final bool _isScanning = false;
  bool _isScanButtonHovered = false;

  late AnimationController _scanButtonController;
  late Animation<double> _scanButtonGlowAnimation;

  @override
  void initState() {
    super.initState();
    _loadStats();
    DataChangeNotifier.version.addListener(_loadStats);

    // Scan button glow animation
    _scanButtonController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _scanButtonGlowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(
        parent: _scanButtonController,
        curve: Curves.easeInOut,
      ),
    );
    _scanButtonController.repeat(reverse: true);
  }

  @override
  void dispose() {
    DataChangeNotifier.version.removeListener(_loadStats);
    _scanButtonController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await _repo.getStatistics();
      final recent = await _repo.loadHistory(limit: 5);
      if (mounted) {
        setState(() {
          _stats = stats;
          _recent = recent;
        });
      }
    } catch (_) {}
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    ).then((_) => _loadStats());
  }

  Future<void> _initiateScan() async {
    if (_isScanning) return; // Prevent duplicate scans
    ScanNowBottomSheet.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _loadStats,
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            AppSpacing.xxxl,
            AppSpacing.screen,
            AppSpacing.huge,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Premium Header with logo and profile actions
              _buildHeader(),
              const SizedBox(height: AppSpacing.xxxl),

              // Hero Protection Status with Animated Radar
              Reveal(delay: Reveal.step(0), child: _buildProtectionHero()),
              const SizedBox(height: AppSpacing.xxl),

              // Primary Scan Now Button
              Reveal(delay: Reveal.step(1), child: _buildScanButton()),
              const SizedBox(height: AppSpacing.xxl),

              // Security Statistics Grid
              Reveal(
                delay: Reveal.step(2),
                child: AppSection(
                  label: 'Security Overview',
                  child: _buildStatisticsGrid(),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Quick Actions Grid
              Reveal(
                delay: Reveal.step(3),
                child: AppSection(
                  label: 'Quick Actions',
                  child: _buildQuickActionsGrid(context),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Recent Activity
              Reveal(
                delay: Reveal.step(4),
                child: AppSection(
                  label: 'Recent Activity',
                  actionLabel: _recent.isEmpty ? null : 'View all',
                  onAction: _recent.isEmpty ? null : _openHistory,
                  child: _buildRecentActivity(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Premium header with ScamShield logo, personalised greeting, and actions
  Widget _buildHeader() {
    return ValueListenableBuilder<String>(
      valueListenable: UserProfileService.avatarNotifier,
      builder: (ctx, avatar, _) {
        return Row(
          children: [
            // Logo and greeting
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          gradient: AppColors.protectionGradient,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        'ScamShield',
                        style: AppText.subheading.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Welcome back, your protection is active',
                    style: AppText.secondary,
                  ),
                ],
              ),
            ),
            // Notification and profile actions
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: AppColors.surfaceLight,
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      const Icon(
                        Icons.notifications_none_rounded,
                        color: AppColors.textSecondary,
                        size: 22,
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    ).then((_) => _loadStats());
                  },
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.surfaceLight,
                    backgroundImage: NetworkImage(avatar),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Hero protection status section with animated radar as focal point
  Widget _buildProtectionHero() {
    final isProtected = _stats != null && (_stats?.scamCount ?? 0) == 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isProtected
              ? AppColors.accent.withValues(alpha: 0.3)
              : AppColors.warning.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isProtected
                ? AppColors.protectedGlow
                : AppColors.warning.withValues(alpha: 0.2),
            blurRadius: 40,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        children: [
          // Status text
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isProtected ? AppColors.success : AppColors.warning,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isProtected ? AppColors.success : AppColors.warning)
                          .withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                isProtected ? "You're protected" : "Review your security",
                style: AppText.subheading.copyWith(
                  color: isProtected ? AppColors.success : AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // Animated Radar - main visual focal point
          Center(
            child: AnimatedRadar(
              size: 220,
              isScanning: _isScanning,
              threatMarkers: !isProtected && _recent.isNotEmpty
                  ? [
                      const Offset(-0.3, -0.2),
                      const Offset(0.4, 0.1),
                    ]
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Security summary
          Text(
            'Real-time threat monitoring active',
            style: AppText.bodyMuted,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Prominent Scan Now button with animated border and glow effects
  Widget _buildScanButton() {
    return StatefulBuilder(
      builder: (context, setState) {
        return AnimatedBuilder(
          animation: _scanButtonGlowAnimation,
          builder: (context, child) {
            return MouseRegion(
              onEnter: (_) => setState(() => _isScanButtonHovered = true),
              onExit: (_) => setState(() => _isScanButtonHovered = false),
              child: GestureDetector(
                onTap: _isScanning ? null : _initiateScan,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
                  decoration: BoxDecoration(
                    gradient: AppColors.protectionGradient,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary
                            .withValues(alpha: _isScanButtonHovered 
                                ? _scanButtonGlowAnimation.value * 1.5 
                                : _scanButtonGlowAnimation.value),
                        blurRadius: _isScanButtonHovered ? 35 : 25,
                        spreadRadius: _isScanButtonHovered ? 8 : 5,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isScanning
                            ? Icons.sync_rounded
                            : Icons.search_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        _isScanning ? 'Scanning...' : 'Scan Now',
                        style: AppText.subheading.copyWith(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Security statistics grid with real data from repository
  Widget _buildStatisticsGrid() {
    if (_stats == null) {
      return AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

    final stats = _stats!;
    final statItems = [
      {
        'label': 'Total Scans',
        'value': stats.totalScans.toString(),
        'icon': Icons.search_rounded,
        'color': AppColors.primary,
      },
      {
        'label': 'Threats Detected',
        'value': (stats.scamCount + stats.suspiciousCount).toString(),
        'icon': Icons.warning_rounded,
        'color': AppColors.danger,
      },
      {
        'label': 'Safe Items',
        'value': (stats.totalScans - stats.scamCount - stats.suspiciousCount)
            .toString(),
        'icon': Icons.check_circle_rounded,
        'color': AppColors.success,
      },
      {
        'label': 'Avg Risk Score',
        'value': stats.averageRiskScore.toStringAsFixed(1),
        'icon': Icons.analytics_rounded,
        'color': AppColors.accent,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        childAspectRatio: 1.5,
      ),
      itemCount: statItems.length,
      itemBuilder: (context, index) {
        final item = statItems[index];
        return AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: (item['color'] as Color).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  item['icon'] as IconData,
                  color: item['color'] as Color,
                  size: 20,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['value'] as String,
                    style: AppText.display.copyWith(fontSize: 28),
                  ),
                  Text(
                    item['label'] as String,
                    style: AppText.secondary,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Quick actions grid for primary feature navigation
  Widget _buildQuickActionsGrid(BuildContext context) {
    final quickActions = [
      {
        'label': 'SIM Lock',
        'description': 'Protect your SIM',
        'icon': Icons.sim_card_rounded,
        'color': AppColors.primary,
        'screen': const SimLockScreen(),
      },
      {
        'label': 'Email Check',
        'description': 'Scan your inbox',
        'icon': Icons.email_rounded,
        'color': AppColors.accent,
        'screen': const BreachScreen(),
      },
      {
        'label': 'Breach Check',
        'description': 'Data leak monitor',
        'icon': Icons.security_rounded,
        'color': AppColors.warning,
        'screen': const BreachScreen(),
      },
      {
        'label': 'Safe Vault',
        'description': 'Secure storage',
        'icon': Icons.lock_rounded,
        'color': AppColors.success,
        'screen': const SafeVaultScreen(),
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        childAspectRatio: 1.4,
      ),
      itemCount: quickActions.length,
      itemBuilder: (context, index) {
        final action = quickActions[index];
        return AppCard(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => action['screen'] as Widget,
              ),
            );
          },
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: (action['color'] as Color).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  action['icon'] as IconData,
                  color: action['color'] as Color,
                  size: 24,
                ),
              ),
              const Spacer(),
              Text(
                action['label'] as String,
                style: AppText.subheading,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                action['description'] as String,
                style: AppText.secondary,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Recent activity feed with scan history
  Widget _buildRecentActivity() {
    if (_recent.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.history_rounded,
                color: AppColors.textSecondary,
                size: 48,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No recent activity',
                style: AppText.bodyMuted,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Your scan history will appear here',
                style: AppText.secondary,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _recent.map((scan) {
        final isDangerous = scan.classification == ScamClassification.scam.name;
        final isSuspicious = scan.classification == ScamClassification.suspicious.name;
        final statusColor = isDangerous
            ? AppColors.danger
            : isSuspicious
                ? AppColors.warning
                : AppColors.success;

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    isDangerous
                        ? Icons.dangerous_rounded
                        : isSuspicious
                            ? Icons.help_rounded
                            : Icons.check_circle_rounded,
                    color: statusColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scan.source ?? 'Unknown scan',
                        style: AppText.subheading.copyWith(fontSize: 14),
                      ),
                      Text(
                        _formatTimestamp(scan.timestamp),
                        style: AppText.secondary,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    isDangerous
                        ? 'Dangerous'
                        : isSuspicious
                            ? 'Suspicious'
                            : 'Safe',
                    style: AppText.label.copyWith(
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Format timestamp for recent activity
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}