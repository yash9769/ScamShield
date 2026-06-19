// lib/screens/profile_screen.dart

import 'package:flutter/material.dart';
import '../theme.dart';
import '../data/repositories/preferences_repository.dart';
import '../data/repositories/scan_repository.dart';
import '../data/models/user_preferences.dart';
import '../data/education/progress_service.dart';
import '../widgets/offline_banner.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final PreferencesRepository _prefsRepo = PreferencesRepository();
  final ScanRepository _scanRepo = ScanRepository();
  final ProgressService _progressService = ProgressService();

  UserPreferences _prefs = const UserPreferences();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await _prefsRepo.load();
    setState(() {
      _prefs = prefs;
      _isLoading = false;
    });
  }

  Future<void> _updatePref(UserPreferences updated) async {
    await _prefsRepo.save(updated);
    setState(() => _prefs = updated);
  }

  Future<void> _deleteAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete All Data'),
        content: const Text(
          'This will permanently delete:\n• All scan history\n• All quiz progress & badges\n• All preferences\n\nThis cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE ALL', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _scanRepo.clearHistory();
      await _progressService.resetProgress();
      await _prefsRepo.resetToDefaults();
      await _loadPrefs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All data deleted successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OfflineBanner(
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Icon(Icons.shield, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('ScamShield', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : SingleChildScrollView(
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
                      _buildSwitchItem(
                        Icons.notifications_active_outlined,
                        'Threat Alerts',
                        'Real-time scam notifications',
                        _prefs.notificationsEnabled,
                        (v) => _updatePref(_prefs.copyWith(notificationsEnabled: v)),
                      ),
                      _buildSwitchItem(
                        Icons.lightbulb_outline,
                        'Daily Scam Tips',
                        'One tip per day on the Learn tab',
                        _prefs.dailyTipEnabled,
                        (v) => _updatePref(_prefs.copyWith(dailyTipEnabled: v)),
                      ),
                    ]),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Privacy & Data'),
                    const SizedBox(height: 16),
                    _buildSettingsList([
                      _buildSwitchItem(
                        Icons.privacy_tip_outlined,
                        'Data Consent',
                        _prefs.hasConsented
                            ? 'Consented to local data storage'
                            : 'Tap to review and consent',
                        _prefs.hasConsented,
                        (v) => _updatePref(_prefs.copyWith(hasConsented: v)),
                      ),
                      _buildAutoDeleteItem(),
                      _buildTapItem(
                        Icons.policy_outlined,
                        'Privacy Policy',
                        'View our data handling policy',
                        onTap: () => _showPrivacyPolicy(context),
                      ),
                      _buildTapItem(
                        Icons.delete_forever_outlined,
                        'Delete All Data',
                        'Permanently erase all local data',
                        onTap: _deleteAllData,
                        isDestructive: true,
                      ),
                    ]),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Account Systems'),
                    const SizedBox(height: 16),
                    _buildSettingsList([
                      _buildTapItem(
                        Icons.credit_card,
                        'Subscription',
                        'Free Plan — Upgrade for AI analysis',
                        onTap: () {},
                      ),
                      _buildTapItem(
                        Icons.logout,
                        'Secure Sign Out',
                        'Wipe local cache and exit',
                        onTap: () {},
                        isDestructive: true,
                      ),
                    ]),
                    const SizedBox(height: 32),
                    const Text(
                      'ScamShield v1.0.0\nAll scan data is stored locally on your device.\nNo data is shared without your consent.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.6),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
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
                radius: 55,
                backgroundImage: NetworkImage('https://i.pravatar.cc/300?u=yash'),
                backgroundColor: AppColors.surface,
              ),
            ),
            Positioned(
              bottom: 0,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: const Icon(Icons.verified, color: Colors.black, size: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Yash', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const Text('Intelligence Level: Advanced Protector',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          height: 48,
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
                Icon(Icons.edit_note, color: Colors.black, size: 18),
                SizedBox(width: 8),
                Text('EDIT PROFILE',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
        Expanded(
            child: _buildSecurityCard(
                'ENCRYPTION', 'Military Grade', Icons.lock_outline, 'ACTIVE', AppColors.success)),
        const SizedBox(width: 16),
        Expanded(
            child: _buildSecurityCard(
                'STORAGE', 'Local Only', Icons.storage_outlined, 'PRIVATE', AppColors.success)),
      ],
    );
  }

  Widget _buildSecurityCard(
      String label, String value, IconData icon, String badge, Color badgeColor) {
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
              Icon(icon, color: AppColors.primary, size: 22),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(badge,
                    style:
                        TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
      decoration:
          BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(children: items),
    );
  }

  Widget _buildSwitchItem(
      IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.background, width: 2))),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.background, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(subtitle,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeColor: AppColors.primary),
        ],
      ),
    );
  }

  Widget _buildAutoDeleteItem() {
    final options = {0: 'Never', 7: '7 days', 30: '30 days', 90: '90 days'};
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.background, width: 2))),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.background, borderRadius: BorderRadius.circular(10)),
            child:
                const Icon(Icons.auto_delete_outlined, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Auto-Delete History', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Automatically clear old scans',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          DropdownButton<int>(
            value: _prefs.autoDeleteDays,
            dropdownColor: AppColors.surface,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            underline: const SizedBox(),
            items: options.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              if (v != null) _updatePref(_prefs.copyWith(autoDeleteDays: v));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTapItem(IconData icon, String title, String subtitle,
      {required VoidCallback onTap, bool isDestructive = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.background, width: 2))),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.background, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon,
                  color: isDestructive ? AppColors.danger.withOpacity(0.7) : AppColors.primary,
                  size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDestructive
                              ? AppColors.danger.withOpacity(0.85)
                              : Colors.white)),
                  Text(subtitle,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Privacy Policy',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Last updated: July 2026',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 20),
            _policySection('Data Storage',
                'All scan data, quiz progress, and preferences are stored exclusively on your device using SQLite. No data is transmitted to external servers without your explicit action.'),
            _policySection('AI Analysis',
                'When you use the AI-powered scan feature, the text you submit is sent to our backend server for analysis. This text is not logged or retained after analysis is complete.'),
            _policySection('No Data Selling',
                'ScamShield does not sell, share, or monetise your personal data in any form.'),
            _policySection('Data Deletion',
                'You can delete all locally stored data at any time via Profile → Delete All Data. This action is immediate and irreversible.'),
            _policySection('Auto-Delete',
                'You can configure scan history to be automatically deleted after 7, 30, or 90 days.'),
            _policySection('Contact',
                'For privacy concerns, contact: privacy@scamshield.app'),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _policySection(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13, height: 1.6)),
        ],
      ),
    );
  }
}
