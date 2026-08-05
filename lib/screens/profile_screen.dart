import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/user_profile_service.dart';
import '../services/auth_service.dart';
import '../data/repositories/preferences_repository.dart';
import '../data/models/user_preferences.dart';
import 'history_screen.dart';
import 'privacy_data_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final PreferencesRepository _prefsRepo = PreferencesRepository();
  UserPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await _prefsRepo.load();
      if (mounted) setState(() => _prefs = prefs);
    } catch (_) {
      if (mounted) setState(() => _prefs = null);
    }
  }

  Future<void> _updatePreferences(UserPreferences prefs) async {
    setState(() => _prefs = prefs);
    try {
      await _prefsRepo.save(prefs);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save preference.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  void _showEditProfileSheet() {
    final nameController =
        TextEditingController(text: UserProfileService.nameNotifier.value);
    final titleController = TextEditingController(
      text: UserProfileService.titleNotifier.value
          .replaceAll('Intelligence Level: ', ''),
    );
    String selectedAvatar = UserProfileService.avatarNotifier.value;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Edit Profile & Avatar',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text(
                      'Choose how you appear across ScamShield',
                      style:
                          TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    const Text('Choose Avatar:',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: UserProfileService.presetAvatars.map((url) {
                        final isSel = selectedAvatar == url;
                        return GestureDetector(
                          onTap: () =>
                              setSheetState(() => selectedAvatar = url),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSel
                                    ? AppColors.primary
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 26,
                              backgroundImage: NetworkImage(url),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Security Title',
                        prefixIcon: Icon(Icons.shield_outlined),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final newName = nameController.text.trim();
                          final newTitle = titleController.text.trim();
                          await UserProfileService.updateProfile(
                            name: newName.isNotEmpty ? newName : null,
                            title: newTitle.isNotEmpty
                                ? 'Intelligence Level: $newTitle'
                                : null,
                            avatarUrl: selectedAvatar,
                          );
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                        icon: const Icon(Icons.check),
                        label: const Text('Save & Sync'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: BorderSide(
                            color:
                                AppColors.textSecondary.withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
          'Signing out will clear your active session. Local vault notes and scan history remain encrypted on device.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await AuthService.signOut();
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not sign out. Please try again.'),
                    backgroundColor: AppColors.danger,
                  ),
                );
                return;
              }
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
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
          // FIX: Avatar is now tappable — opens the edit profile dialog
          GestureDetector(
            onTap: _showEditProfileSheet,
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
                switchValue: _prefs?.notificationsEnabled ?? true,
                onChanged: (v) => _updatePreferences(
                  (_prefs ?? const UserPreferences()).copyWith(notificationsEnabled: v),
                ),
              ),
              _buildSettingItem(
                Icons.lightbulb_outline,
                'Daily Safety Tips',
                'Show a scam tip on the Learn tab',
                hasSwitch: true,
                switchValue: _prefs?.dailyTipEnabled ?? true,
                onChanged: (v) => _updatePreferences(
                  (_prefs ?? const UserPreferences()).copyWith(dailyTipEnabled: v),
                ),
              ),
              _buildSettingItem(
                Icons.history,
                'Scan History',
                'Stored securely on this device',
                hasSwitch: false,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
              ),
              _buildSettingItem(
                Icons.privacy_tip_outlined,
                'Privacy & Data',
                'Retention, storage and consent',
                hasSwitch: false,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyDataScreen())),
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
          onTap: _showEditProfileSheet,
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
                    radius: 42,
                    backgroundImage: NetworkImage(avatar),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.edit, color: Colors.black, size: 14),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ValueListenableBuilder<String>(
          valueListenable: UserProfileService.nameNotifier,
          builder: (ctx, name, _) => Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
            onPressed: _showEditProfileSheet,
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