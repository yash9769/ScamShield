import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/user_profile_service.dart';
import 'history_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final bool _threatAlerts = true;
  final bool _deepfakeFilter = true;
  final bool _cloudSync = false;

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: UserProfileService.nameNotifier.value);
    final titleController = TextEditingController(
      text: UserProfileService.titleNotifier.value.replaceAll('Intelligence Level: ', ''),
    );
    String selectedAvatar = UserProfileService.avatarNotifier.value;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Edit Profile & Avatar', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose Avatar:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: UserProfileService.presetAvatars.map((url) {
                    final isSel = selectedAvatar == url;
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() => selectedAvatar = url);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: isSel ? AppColors.primary : Colors.transparent, width: 3),
                        ),
                        child: CircleAvatar(
                          radius: 24,
                          backgroundImage: NetworkImage(url),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Security Title',
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = nameController.text.trim();
                final newTitle = titleController.text.trim();
                await UserProfileService.updateProfile(
                  name: newName.isNotEmpty ? newName : null,
                  title: newTitle.isNotEmpty ? 'Intelligence Level: $newTitle' : null,
                  avatarUrl: selectedAvatar,
                );
                if (mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Save & Sync', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Secure Sign Out?'),
        content: const Text(
          'Signing out will clear active session caches. Local vault notes remain encrypted on device.',
          style: TextStyle(color: AppColors.textSecondary),
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
                  content: Text('Session cache cleared. Signed out securely.'),
                  backgroundColor: AppColors.danger,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSubscriptionInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.stars, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Active Subscription', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plan: ScamShield Pro (Annual)', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('Status: Active • Renews Oct 2026', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            SizedBox(height: 12),
            Text('Includes 256-bit VPN, unlimited neural scanning, and dark web monitoring.', style: TextStyle(fontSize: 12, height: 1.4)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Close', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.shield, color: AppColors.primary),
            SizedBox(width: 8),
            Text('ScamShield', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          ValueListenableBuilder<String>(
            valueListenable: UserProfileService.avatarNotifier,
            builder: (ctx, avatar, _) => CircleAvatar(
              radius: 15,
              backgroundImage: NetworkImage(avatar),
            ),
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
              _buildSettingItem(
                Icons.notifications_active_outlined,
                'Threat Alerts',
                'Real-time scam notifications',
                hasSwitch: true,
                switchValue: _threatAlerts,
                onChanged: (v) {},
              ),
              _buildSettingItem(
                Icons.videocam_outlined,
                'Deepfake Filter',
                'AI-driven video verification',
                hasSwitch: true,
                switchValue: _deepfakeFilter,
                onChanged: (v) {},
              ),
              _buildSettingItem(
                Icons.history,
                'Scan History',
                _cloudSync ? 'Cloud sync enabled' : 'Local storage active',
                hasSwitch: false,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
              ),
            ]),
            const SizedBox(height: 32),
            _buildSectionHeader('Account Systems'),
            const SizedBox(height: 16),
            _buildSettingsList([
              _buildSettingItem(
                Icons.credit_card,
                'Subscription',
                'Premium Plan - Active',
                hasSwitch: false,
                onTap: _showSubscriptionInfo,
              ),
              _buildSettingItem(
                Icons.logout,
                'Secure Sign Out',
                'Wipe local cache',
                hasSwitch: false,
                isDestructive: true,
                onTap: _showSignOutDialog,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Column(
      children: [
        GestureDetector(
          onTap: _showEditProfileDialog,
          child: Stack(
            children: [
              ValueListenableBuilder<String>(
                valueListenable: UserProfileService.avatarNotifier,
                builder: (ctx, avatar, _) => Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 60,
                    backgroundImage: NetworkImage(avatar),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.edit, color: Colors.black, size: 16),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ValueListenableBuilder<String>(
          valueListenable: UserProfileService.nameNotifier,
          builder: (ctx, name, _) => Text(name, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        ),
        ValueListenableBuilder<String>(
          valueListenable: UserProfileService.titleNotifier,
          builder: (ctx, title, _) => Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: ElevatedButton(
            onPressed: _showEditProfileDialog,
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
        border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.1)),
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
                  color: badgeColor.withValues(alpha: 0.1),
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

  Widget _buildSettingItem(
    IconData icon,
    String title,
    String subtitle, {
    required bool hasSwitch,
    bool switchValue = false,
    ValueChanged<bool>? onChanged,
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: hasSwitch ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
              child: Icon(icon, color: isDestructive ? AppColors.danger.withValues(alpha: 0.7) : AppColors.primary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isDestructive ? AppColors.danger.withValues(alpha: 0.7) : Colors.white)),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            if (hasSwitch)
              Switch(
                value: switchValue,
                onChanged: onChanged,
                activeThumbColor: AppColors.primary,
              )
            else
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
