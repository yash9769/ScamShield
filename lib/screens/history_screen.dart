import 'package:flutter/material.dart';
import '../theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('History', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            Text('Review your recent scans and security alerts.', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          const CircleAvatar(
            radius: 15,
            backgroundImage: NetworkImage('https://i.pravatar.cc/150?u=alex'),
          ),
          const SizedBox(width: 16),
        ],
        toolbarHeight: 100,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildFilterChips(),
                const SizedBox(height: 24),
                _buildHistoryItem(
                  'SCAM DETECTED',
                  'Phishing SMS',
                  '"Your account has been locked. Click here to verify: bit.ly/secure-auth-4921"',
                  'Today, 2:45 PM',
                  'Source: +1 (555) 012-9923',
                  AppColors.danger,
                  Icons.error_outline,
                ),
                const SizedBox(height: 16),
                _buildHistoryItem(
                  'SAFE SCAN',
                  'Website Verification',
                  'Official Portal: bank-of-america.com/login',
                  'Today, 11:20 AM',
                  'Source: Safari Browser',
                  AppColors.success,
                  Icons.check_circle_outline,
                ),
                const SizedBox(height: 16),
                _buildHistoryItem(
                  'DANGER',
                  'Spoofed Identity',
                  'Suspected IRS Impersonator. High risk of social engineering.',
                  'Yesterday, 9:15 PM',
                  'Source: +1 (202) 555-0144',
                  AppColors.danger,
                  Icons.phone_missed,
                ),
                const SizedBox(height: 16),
                _buildHistoryItem(
                  'SAFE SCAN',
                  'Known Contact',
                  'Inbound call from "Sarah Wilson" (Verified Contact).',
                  'Yesterday, 6:30 PM',
                  'Source: Contact List',
                  AppColors.success,
                  Icons.verified_user_outlined,
                ),
                const SizedBox(height: 24),
                _buildWeeklyProtectionCard(),
                const SizedBox(height: 80), // Space for FAB
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: () {},
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.qr_code_scanner, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Row(
      children: [
        _buildChip('All Scans', true),
        const SizedBox(width: 8),
        _buildChip('Threats Only', false),
        const SizedBox(width: 8),
        _buildChip('Phone Calls', false),
      ],
    );
  }

  Widget _buildChip(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isSelected ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.black : Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildHistoryItem(String tag, String title, String description, String time, String source, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(tag, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Text(time, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 16),
          const Divider(color: AppColors.textSecondary, height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(source, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyProtectionCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface, AppColors.accent.withValues(alpha: 0.1)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Weekly Protection', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('You’ve successfully avoided 14 potential threats this week.', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStat('14', 'BLOCKED', AppColors.primary),
              _buildStat('89', 'VERIFIED', AppColors.success),
              _buildStat('103', 'TOTAL SCANS', Colors.white),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }
}
