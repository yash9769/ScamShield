import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/scan_now_bottom_sheet.dart';
import '../services/user_profile_service.dart';
import 'sim_lock_screen.dart';
import 'breach_screen.dart';
import 'safe_vault_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Pro Trial Activated! Welcome to ScamShield Pro.'),
                  backgroundColor: AppColors.primary,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Start Free Trial', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static Widget _buildProFeature(IconData icon, String text) {
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
            Image.asset('assets/icon.png', height: 28, width: 28, errorBuilder: (c,e,s) => const Icon(Icons.shield, color: AppColors.primary)),
            const SizedBox(width: 8),
            const Text('ScamShield', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No new security notifications.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
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
            const SizedBox(height: 24),
            _buildStatsGrid(),
            const SizedBox(height: 32),
            const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildQuickActions(context),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Threat Activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
                  },
                  child: const Text('VIEW ALL >', style: TextStyle(color: AppColors.primary, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildThreatActivity(),
            const SizedBox(height: 24),
            _buildUpgradeBanner(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
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
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                const Text('SHIELD ACTIVE', style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2),
                  boxShadow: [
                    BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: 5),
                  ],
                ),
              ),
              Column(
                children: [
                  const Text('Secure', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  Text('STATUS', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Your digital ecosystem is currently under continuous monitoring. No active threats detected in the last 24 hours.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          const AnimatedScanNowButton(),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard('APPS MONITORED', '142', Icons.verified_user_outlined),
        _buildStatCard('BLOCKED CALLS', '24', Icons.warning_amber_rounded),
        _buildStatCard('VPN UPTIME', '99.9%', Icons.language),
        _buildStatCard('THREATS KILLED', '1,028', Icons.check_circle_outline),
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
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
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
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SimLockScreen()));
        }),
        _buildActionIcon(context, Icons.email_outlined, 'EMAIL CHECK', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const BreachScreen(initialIndex: 1)));
        }),
        _buildActionIcon(context, Icons.public, 'BREACHES', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const BreachScreen(initialIndex: 0)));
        }),
        _buildActionIcon(context, Icons.lock_clock_outlined, 'SAFE VAULT', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SafeVaultScreen()));
        }),
      ],
    );
  }

  Widget _buildActionIcon(BuildContext context, IconData icon, String label, VoidCallback onTap) {
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
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildThreatActivity() {
    return Column(
      children: [
        _buildThreatItem('Suspicious URL Blocked', 'secure-bank-login.net', '2M AGO', Icons.cancel, AppColors.danger),
        const SizedBox(height: 12),
        _buildThreatItem('Spam Call Silenced', '+1 (555) 0123', '1H AGO', Icons.phone_disabled, AppColors.warning),
      ],
    );
  }

  Widget _buildThreatItem(String title, String subtitle, String time, IconData icon, Color color) {
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
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.accent.withValues(alpha: 0.8), AppColors.background]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Upgrade to Pro', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Get real-time identity theft protection and a private 256-bit VPN.', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _showUpgradeModal(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('EXPLORE PLANS', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
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
        height: 58,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: () => ScanNowBottomSheet.show(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search, color: Colors.white),
              SizedBox(width: 8),
              Text('SCAN NOW', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
