import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/scan_now_bottom_sheet.dart';
import '../widgets/motion.dart';
import '../services/user_profile_service.dart';
import 'sim_lock_screen.dart';
import 'breach_screen.dart';
import 'safe_vault_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import '../data/repositories/scan_repository.dart';
import '../data/models/scan_record.dart';

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
  }

  Future<void> _loadStats() async {
    try {
      final stats  = await _repo.getStatistics();
      final recent = await _repo.loadHistory(limit: 3);
      if (mounted) setState(() { _stats = stats; _recent = recent; });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icon.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            const Text('ScamShield', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_outlined, color: AppColors.textPrimary),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No active security notifications.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))
                  .then((_) => _loadStats());
            },
            child: ValueListenableBuilder<String>(
              valueListenable: UserProfileService.avatarNotifier,
              builder: (ctx, avatar, _) => Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 14,
                  backgroundImage: NetworkImage(avatar),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Reveal(delay: Reveal.step(0), child: _buildStatusSection(context)),
              const SizedBox(height: 24),
              Reveal(delay: Reveal.step(1), child: _buildStatsGrid()),
              const SizedBox(height: 28),
              Reveal(
                delay: Reveal.step(2),
                child: const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
              const SizedBox(height: 14),
              Reveal(delay: Reveal.step(3), child: _buildQuickActions(context)),
              const SizedBox(height: 28),
              Reveal(
                delay: Reveal.step(4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Threat Activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    TextButton(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()))
                            .then((_) => _loadStats());
                      },
                      child: const Text('VIEW ALL >', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Reveal(delay: Reveal.step(5), child: _buildThreatActivity()),
              const SizedBox(height: 24),
              Reveal(delay: Reveal.step(6), child: _buildUpgradeBanner(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSection(BuildContext context) {
    final hasScans = (_stats?.totalScans ?? 0) > 0;
    final statusColor = hasScans && (_stats?.scamCount ?? 0) > 0 ? AppColors.warning : AppColors.success;
    final statusText = hasScans && (_stats?.scamCount ?? 0) > 0 ? 'THREATS DETECTED' : 'SHIELD ACTIVE';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.surfaceLight.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Stack(
            alignment: Alignment.center,
            children: [
              // Signature: an ambient radar sweep circling the shield to signal
              // continuous, active monitoring.
              RadarSweep(
                size: 150,
                color: statusColor,
                duration: const Duration(seconds: 4),
              ),
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary.withOpacity(0.6), width: 2),
                  boxShadow: [
                    BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 24, spreadRadius: 4),
                  ],
                ),
              ),
              const Column(
                children: [
                  Icon(Icons.verified_user_outlined, color: AppColors.primary, size: 40),
                  SizedBox(height: 6),
                  Text('Protected', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text('ECOSYSTEM', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, letterSpacing: 1.5)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            hasScans
                ? 'Your device is protected. Total ${_stats!.totalScans} scan(s) performed.'
                : 'Your digital ecosystem is under continuous monitoring. Tap below to run your first scan.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 24),
          const AnimatedScanNowButton(),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final s = _stats;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard('TOTAL SCANS', s == null ? '0' : '${s.totalScans}', Icons.radar_rounded, AppColors.primary),
        _buildStatCard('SCAMS CAUGHT', s == null ? '0' : '${s.scamCount}', Icons.warning_amber_rounded, AppColors.danger),
        _buildStatCard('SUSPICIOUS', s == null ? '0' : '${s.suspiciousCount}', Icons.help_outline_rounded, AppColors.warning),
        _buildStatCard('AVG RISK SCORE', s == null ? '0' : '${s.averageRiskScore.toStringAsFixed(0)}', Icons.analytics_outlined, AppColors.success),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceLight.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: accentColor, size: 20),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: accentColor.withOpacity(0.5), shape: BoxShape.circle),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildActionIcon(context, Icons.sd_card_outlined, 'SIM LOCK', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SimLockScreen()));
        }),
        _buildActionIcon(context, Icons.email_outlined, 'EMAIL CHECK', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const BreachScreen(initialIndex: 0)));
        }),
        _buildActionIcon(context, Icons.public, 'BREACHES', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const BreachScreen(initialIndex: 1)));
        }),
        _buildActionIcon(context, Icons.lock_clock_outlined, 'SAFE VAULT', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SafeVaultScreen()));
        }),
      ],
    );
  }

  Widget _buildActionIcon(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 65,
            height: 65,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceLight.withOpacity(0.6)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: Icon(icon, color: AppColors.primary, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildThreatActivity() {
    if (_recent.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.surfaceLight.withOpacity(0.5)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, color: AppColors.textSecondary, size: 36),
            SizedBox(height: 10),
            Text('No Threat Scans Yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            SizedBox(height: 4),
            Text(
              'Your scan history is completely clean. Tap SCAN NOW to run your first check.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return Column(
      children: _recent.asMap().entries.map((e) {
        final r = e.value;
        final Color color;
        final IconData icon;
        switch (r.classification.toLowerCase()) {
          case 'scam': color = AppColors.danger; icon = Icons.error_outline; break;
          case 'suspicious': color = AppColors.warning; icon = Icons.warning_amber_outlined; break;
          default: color = AppColors.success; icon = Icons.check_circle_outline;
        }
        final diff = DateTime.now().difference(r.timestamp);
        final timeStr = diff.inMinutes < 1 ? 'Just now'
            : diff.inHours < 1 ? '${diff.inMinutes}m ago'
            : diff.inDays < 1 ? '${diff.inHours}h ago'
            : '${diff.inDays}d ago';
        return Padding(
          padding: EdgeInsets.only(bottom: e.key < _recent.length - 1 ? 12 : 0),
          child: _buildThreatItem(
            r.classification.toUpperCase(),
            r.inputText.length > 45 ? '${r.inputText.substring(0, 45)}...' : r.inputText,
            timeStr, icon, color,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildThreatItem(String title, String subtitle, String time, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceLight.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Text(time, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildUpgradeBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withOpacity(0.12), AppColors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.verified, color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text('ScamShield Active Intelligence', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          ...[
            '✓ Explainable Gemini AI threat detection',
            '✓ Static APK analysis (Androguard + YARA)',
            '✓ VirusTotal & Google Safe Browsing APIs',
            '✓ Zero dummy data — real local encrypted storage',
          ].map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(f, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          )),
        ],
      ),
    );
  }
}

class AnimatedScanNowButton extends StatefulWidget {
  const AnimatedScanNowButton({super.key});

  @override
  State<AnimatedScanNowButton> createState() => _AnimatedScanNowButtonState();
}

class _AnimatedScanNowButtonState extends State<AnimatedScanNowButton> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.35),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: () => ScanNowBottomSheet.show(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.center_focus_strong, color: Colors.black, size: 22),
              SizedBox(width: 10),
              Text('SCAN NOW', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
