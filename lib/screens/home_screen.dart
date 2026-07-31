import 'package:flutter/material.dart';
import '../theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.shield, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('ScamShield', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          const Icon(Icons.notifications_none),
          const SizedBox(width: 16),
          const CircleAvatar(
            radius: 15,
            backgroundImage: NetworkImage('https://i.pravatar.cc/150?u=alex'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusSection(),
            const SizedBox(height: 24),
            _buildStatsGrid(),
            const SizedBox(height: 32),
            const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildQuickActions(),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Threat Activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton(onPressed: () {}, child: const Text('VIEW ALL >', style: TextStyle(color: AppColors.primary, fontSize: 12))),
              ],
            ),
            const SizedBox(height: 8),
            _buildThreatActivity(),
            const SizedBox(height: 24),
            _buildUpgradeBanner(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
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
          Container(
            width: double.infinity,
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, color: Colors.white),
                  SizedBox(width: 8),
                  Text('SCAN NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
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

  Widget _buildQuickActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildActionIcon(Icons.sd_card, 'SIM LOCK'),
        _buildActionIcon(Icons.email_outlined, 'EMAIL CHECK'),
        _buildActionIcon(Icons.public, 'BREACHES'),
        _buildActionIcon(Icons.lock_clock_outlined, 'SAFE VAULT'),
      ],
    );
  }

  Widget _buildActionIcon(IconData icon, String label) {
    return Column(
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

  Widget _buildUpgradeBanner() {
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
            onPressed: () {},
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
