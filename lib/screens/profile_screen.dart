import 'package:flutter/material.dart';
import '../theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

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
          children: [
            _buildProfileHeader(),
            const SizedBox(height: 24),
            _buildSecurityCards(),
            const SizedBox(height: 32),
            _buildSectionHeader('Intelligence Settings'),
            const SizedBox(height: 16),
            _buildSettingsList([
              _buildSettingItem(Icons.notifications_active_outlined, 'Threat Alerts', 'Real-time scam notifications', true),
              _buildSettingItem(Icons.videocam_outlined, 'Deepfake Filter', 'AI-driven video verification', true),
              _buildSettingItem(Icons.history, 'Scan History', 'Cloud sync enabled', false),
            ]),
            const SizedBox(height: 32),
            _buildSectionHeader('Account Systems'),
            const SizedBox(height: 16),
            _buildSettingsList([
              _buildSettingItem(Icons.credit_card, 'Subscription', 'Premium Plan - Active', false),
              _buildSettingItem(Icons.logout, 'Secure Sign Out', 'Wipe local cache', false, isDestructive: true),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Column(
      children: [
        Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: const CircleAvatar(
                radius: 60,
                backgroundImage: NetworkImage('https://i.pravatar.cc/300?u=alexchen'),
              ),
            ),
            Positioned(
              bottom: 0,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: const Icon(Icons.verified, color: Colors.black, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Alex Chen', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const Text('Intelligence Level: Advanced Protector', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
            ],
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
                Icon(Icons.edit_note, color: Colors.black),
                SizedBox(width: 8),
                Text('EDIT INTELLIGENCE PROFILE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityCards() {
    return Row(
      children: [
        Expanded(child: _buildSecurityCard('ENCRYPTION', 'Military Grade', Icons.lock_outline, 'ACTIVE', AppColors.success)),
        const SizedBox(width: 16),
        Expanded(child: _buildSecurityCard('PRIVACY MODE', 'Stealth Ops', Icons.shield_outlined, 'SECURE', AppColors.success)),
      ],
    );
  }

  Widget _buildSecurityCard(String label, String value, IconData icon, String badge, Color badgeColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: AppColors.primary, size: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(badge, style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSettingsList(List<Widget> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: items),
    );
  }

  Widget _buildSettingItem(IconData icon, String title, String subtitle, bool hasSwitch, {bool isDestructive = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.background, width: 2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: isDestructive ? AppColors.danger.withOpacity(0.7) : AppColors.primary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isDestructive ? AppColors.danger.withOpacity(0.7) : Colors.white)),
                Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          if (hasSwitch)
            Switch(
              value: true,
              onChanged: (v) {},
              activeColor: AppColors.primary,
            )
          else
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}
