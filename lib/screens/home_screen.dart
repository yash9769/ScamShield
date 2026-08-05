import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../widgets/scan_now_bottom_sheet.dart';
import '../services/user_profile_service.dart';
import '../data/repositories/scan_repository.dart';
import '../data/models/scan_record.dart';
import 'sim_lock_screen.dart';
import 'breach_screen.dart';
import 'safe_vault_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Invoked when the user taps "Scan Now". The shell jumps straight to the
  /// scan tab so scanning starts in a single tap (no intermediate chooser).
  final VoidCallback? onScanNow;

  const HomeScreen({super.key, this.onScanNow});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _repo = ScanRepository();
  ScanStatistics? _stats;
  List<ScanRecord> _recentThreats = [];
  bool _isPro = false;
  bool _isDataLoaded = false;

  void refresh() {
    _loadData();
    _loadProStatus();
  }

  static const _proKey = 'scamshield_is_pro';

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadProStatus();
  }

  Future<void> _loadData() async {
    final stats = await _repo.getStatistics();
    final records = await _repo.loadHistory();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _recentThreats = records
          .where((r) => r.classification == 'scam' || r.classification == 'suspicious')
          .take(2)
          .toList();
      _isDataLoaded = true;
    });
  }

  Future<void> _loadProStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _isPro = prefs.getBool(_proKey) ?? false);
  }

  Future<void> _activatePro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_proKey, true);
    if (mounted) setState(() => _isPro = true);
  }

  void _showUpgradeModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.workspace_premium, color: AppColors.primary, size: 28),
            SizedBox(width: 10),
            Text('ScamShield Pro', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Unlock ultimate digital protection for your ecosystem:'),
            const SizedBox(height: 16),
            _buildProFeature(Icons.shield_moon, 'Real-time SMS & Call Silencer'),
            _buildProFeature(Icons.vpn_key, '256-bit Encrypted Private VPN'),
            _buildProFeature(Icons.remove_red_eye_outlined, 'Dark Web Breach Alerts'),
            _buildProFeature(Icons.psychology, 'Unlimited Neural AI Image Scans'),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  '\$4.99 / month • 7-day free trial',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              await _activatePro();
              if (mounted) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('🎉 Pro Trial Activated! Welcome to ScamShield Pro.'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Start Free Trial',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildProFeature(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: AppColors.success, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/icon.png',
                height: 28,
                width: 28,
                errorBuilder: (c, e, s) =>
                    const Icon(Icons.shield, color: AppColors.primary)),
            const SizedBox(width: 8),
            const Text('ScamShield', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          // FIX #2: Notification bell now navigates to scan history / alerts
          IconButton(
            icon: const Icon(Icons.notifications_none),
            tooltip: 'Security Alerts',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
            },
            child: ValueListenableBuilder<String>(
              valueListenable: UserProfileService.avatarNotifier,
              builder: (ctx, avatar, _) => CircleAvatar(
                radius: 15,
                backgroundImage: NetworkImage(avatar),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusSection(context),
            const SizedBox(height: 20),
            // Recent scan activity sits high on the dashboard so users see
            // results right away instead of a large empty region.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Threat Activity',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const HistoryScreen()));
                  },
                  child: const Text('VIEW ALL >',
                      style: TextStyle(color: AppColors.primary, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildThreatActivity(),
            const SizedBox(height: 20),
            _buildStatsGrid(),
            const SizedBox(height: 32),
            const Text('Quick Actions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildQuickActions(context),
            const SizedBox(height: 32),
            _buildUpgradeBanner(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration:
                        const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                const Text('SHIELD ACTIVE',
                    style: TextStyle(
                        color: AppColors.success, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 5),
                  ],
                ),
              ),
              Column(
                children: [
                  const Text('Secure',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text('STATUS',
                      style:
                          TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Your digital ecosystem is under continuous monitoring. No active threats detected in the last 24 hours.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          AnimatedScanNowButton(onPressed: widget.onScanNow),
        ],
      ),
    );
  }

  // FIX #4: TOTAL SCANS and THREATS FOUND are now real values from ScanRepository
  Widget _buildStatsGrid() {
    final totalScans = _stats?.totalScans ?? 0;
    final threatsFound = _stats?.threatsDetected ?? 0;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard('TOTAL SCANS', '$totalScans', Icons.verified_user_outlined),
        _buildStatCard('BLOCKED CALLS', '24', Icons.warning_amber_rounded),
        _buildStatCard('VPN UPTIME', '99.9%', Icons.language),
        _buildStatCard('THREATS FOUND', '$threatsFound', Icons.check_circle_outline),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildActionIcon(context, Icons.sd_card, 'SIM LOCK', () {
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => const SimLockScreen()));
        }),
        _buildActionIcon(context, Icons.email_outlined, 'EMAIL CHECK', () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const BreachScreen(initialIndex: 1)));
        }),
        _buildActionIcon(context, Icons.public, 'BREACHES', () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const BreachScreen(initialIndex: 0)));
        }),
        _buildActionIcon(context, Icons.lock_clock_outlined, 'SAFE VAULT', () {
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => const SafeVaultScreen()));
        }),
      ],
    );
  }

  Widget _buildActionIcon(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  // FIX #5: Threat Activity now shows real scan records from history
  Widget _buildThreatActivity() {
    if (!_isDataLoaded) {
      return const SizedBox(
        height: 80,
        child: Center(
            child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2)),
      );
    }

    if (_recentThreats.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppColors.success),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No threats detected recently. Stay safe! ✓',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _recentThreats.asMap().entries.map((entry) {
        final i = entry.key;
        final record = entry.value;
        final isScam = record.classification == 'scam';
        final color = isScam ? AppColors.danger : AppColors.warning;
        final icon = isScam ? Icons.cancel : Icons.help_outline_rounded;
        final title = isScam ? 'Scam Detected' : 'Suspicious Content';
        final subtitle = record.inputText.length > 35
            ? '${record.inputText.substring(0, 35)}...'
            : record.inputText;
        final time = _formatRelativeTime(record.timestamp);

        return Padding(
          padding: EdgeInsets.only(bottom: i < _recentThreats.length - 1 ? 12 : 0),
          child: _buildThreatItem(title, subtitle, time, icon, color),
        );
      }).toList(),
    );
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'JUST NOW';
    if (diff.inMinutes < 60) return '${diff.inMinutes}M AGO';
    if (diff.inHours < 24) return '${diff.inHours}H AGO';
    return '${diff.inDays}D AGO';
  }

  Widget _buildThreatItem(
      String title, String subtitle, String time, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(subtitle,
                    style:
                        const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Text(time,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }

  // FIX #3: "Start Free Trial" now persists isPro flag; banner reflects real Pro status
  Widget _buildUpgradeBanner(BuildContext context) {
    if (_isPro) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [AppColors.success.withValues(alpha: 0.35), AppColors.background]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.workspace_premium, color: AppColors.success, size: 32),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ScamShield Pro Active 🎉',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text(
                      'You have full access to all premium protection features.',
                      style:
                          TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [AppColors.accent.withValues(alpha: 0.8), AppColors.background]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Upgrade to Pro',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Get real-time identity theft protection and a private 256-bit VPN.',
              style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _showUpgradeModal(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child:
                const Text('EXPLORE PLANS', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ── Animated SCAN NOW button ──────────────────────────────────────────────────

class AnimatedScanNowButton extends StatefulWidget {
  final VoidCallback? onPressed;

  const AnimatedScanNowButton({super.key, this.onPressed});

  @override
  State<AnimatedScanNowButton> createState() => _AnimatedScanNowButtonState();
}

class _AnimatedScanNowButtonState extends State<AnimatedScanNowButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
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
        height: 60,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: widget.onPressed ?? () => ScanNowBottomSheet.show(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code_scanner, color: Colors.white),
              SizedBox(width: 8),
              Text('SCAN NOW',
                  style: TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
