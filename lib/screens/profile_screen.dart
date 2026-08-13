import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../services/user_profile_service.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../data/repositories/scan_repository.dart';
import '../data/models/scan_record.dart';
import '../services/app_capabilities_service.dart';
import 'login_screen.dart';
import 'history_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ScanRepository _repo = ScanRepository();
  ScanStatistics? _stats;

  @override
  void initState() {
    super.initState();
    SettingsService.init();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final s = await _repo.getStatistics();
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

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
                    onBackgroundImageError: (_, _) {},
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
                if (ctx.mounted) Navigator.pop(ctx);
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
          'You will be returned to the sign-in screen. Your saved data stays on this device.',
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
              await AuthService.logout();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
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

  void _showAboutInfo() {
    final caps = AppCapabilitiesService.capabilities.value;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: AppColors.primary),
            SizedBox(width: 8),
            Text('About ScamShield', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ScamShield v2.1', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('Active Mode: ${caps.modeLabel}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
            const SizedBox(height: 10),
            const Text('Features & Integrations:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              '• Server AI Analysis (Gemini/Groq): ${caps.hasFullAi ? "Active" : "Unavailable"}\n'
              '• Live Threat Intel (VirusTotal/SafeBrowsing/AbuseIPDB): ${caps.hasOsint ? "Active" : "Unavailable"}\n'
              '• APK Pipeline (Androguard & YARA): ${caps.hasFullApkPipeline ? "Server Pipeline Active" : "Local Static Analysis Only"}\n'
              '• Storage: PBKDF2 Auth & Hardware AES-256 Secure Vault',
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Privacy & Limitations Notice:\n'
                      '• Account & Vault items are stored on-device only via hardware encryption. No cloud recovery exists.\n'
                      '• When offline or API keys are missing, scans run local heuristic rules only.',
                      style: TextStyle(fontSize: 11, color: AppColors.textPrimary, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
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

  void _showLimitationsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.gpp_maybe_outlined, color: AppColors.warning),
            SizedBox(width: 8),
            Text('System Limitations', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1. Device-Local Account & Encrypted Vault:\n'
                'Account credentials and vault notes are stored exclusively on this device (Keychain / EncryptedSharedPreferences). There is no remote account server or password recovery mechanism.\n\n'
                '2. Heuristic Offline Fallback:\n'
                'When backend AI (Gemini/Groq) or threat intelligence (VirusTotal, Safe Browsing, AbuseIPDB) is offline or API keys are missing, ScamShield evaluates content locally. Local rules flag suspicious patterns but cannot verify live domain reputation.\n\n'
                '3. APK Static Analysis:\n'
                'Local APK analysis evaluates permissions, certificates, DEX printable strings, and YARA signatures on-device. Deep decompilation and sandbox emulation require the full server pipeline.',
                style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Understood', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
            Text('ScamShield Profile', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Reveal(delay: Reveal.step(0), child: _buildProfileHeader()),
            const SizedBox(height: 24),
            Reveal(delay: Reveal.step(1), child: _buildSecurityCards()),
            const SizedBox(height: 28),
            Reveal(delay: Reveal.step(2), child: _buildSectionHeader('Intelligence Settings')),
            const SizedBox(height: 12),
            Reveal(
              delay: Reveal.step(3),
              child: _buildSettingsList([
              ValueListenableBuilder<bool>(
                valueListenable: SettingsService.threatAlerts,
                builder: (ctx, enabled, _) => _buildSettingItem(
                  Icons.notifications_active_outlined,
                  'Threat Alerts',
                  'Real-time scam notifications',
                  hasSwitch: true,
                  switchValue: enabled,
                  onChanged: (v) => SettingsService.setThreatAlerts(v),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: SettingsService.autoScanClipboard,
                builder: (ctx, enabled, _) => _buildSettingItem(
                  Icons.content_paste_search,
                  'Clipboard Check',
                  'Offer to scan copied links and messages',
                  hasSwitch: true,
                  switchValue: enabled,
                  onChanged: (v) => SettingsService.setAutoScanClipboard(v),
                ),
              ),
              _buildSettingItem(
                Icons.history,
                'Scan History',
                '${_stats?.totalScans ?? 0} record(s) in local SQLite database',
                hasSwitch: false,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()))
                    .then((_) => _loadStats()),
              ),
            ]),
            ),
            const SizedBox(height: 28),
            Reveal(delay: Reveal.step(4), child: _buildSectionHeader('Account & System')),
            const SizedBox(height: 12),
            Reveal(
              delay: Reveal.step(5),
              child: _buildSettingsList([
              _buildSettingItem(
                Icons.info_outline,
                'About ScamShield',
                'Version, AI & threat engines status',
                hasSwitch: false,
                onTap: _showAboutInfo,
              ),
              _buildSettingItem(
                Icons.gpp_maybe_outlined,
                'System Limitations & Privacy',
                'On-device encryption, offline fallback & key boundaries',
                hasSwitch: false,
                onTap: _showLimitationsDialog,
              ),
              _buildSettingItem(
                Icons.logout,
                'Secure Sign Out',
                'Return to authentication screen',
                hasSwitch: false,
                isDestructive: true,
                onTap: _showSignOutDialog,
              ),
            ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Column(
      children: [
        Pressable(
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
                    boxShadow: [
                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 16, spreadRadius: 2),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundImage: NetworkImage(avatar),
                          onBackgroundImageError: (_, _) {},
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.edit, color: Colors.black, size: 14),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ValueListenableBuilder<String>(
          valueListenable: UserProfileService.nameNotifier,
          builder: (ctx, name, _) => Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        ValueListenableBuilder<String>(
          valueListenable: UserProfileService.titleNotifier,
          builder: (ctx, title, _) => Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildSecurityCards() {
    final total = _stats?.totalScans ?? 0;
    return Row(
      children: [
        Expanded(child: _buildSecurityCard('TOTAL SCANS', '$total Executed', Icons.radar_rounded, total > 0 ? '$total LOGS' : '0 LOGS', AppColors.primary)),
        const SizedBox(width: 12),
        Expanded(child: _buildSecurityCard('ENCRYPTION', 'AES-256 KeyStore', Icons.lock_outline, 'LOCAL VAULT', AppColors.success)),
      ],
    );
  }

  Widget _buildSecurityCard(String label, String value, IconData icon, String badge, Color badgeColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: badgeColor, size: 22),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(badge, style: TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1),
      ),
    );
  }

  Widget _buildSettingsList(List<Widget> children) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
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
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (isDestructive ? AppColors.danger : AppColors.primary).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: isDestructive ? AppColors.danger : AppColors.primary, size: 20),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDestructive ? AppColors.danger : AppColors.textPrimary)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: hasSwitch
          ? Switch(
              value: switchValue,
              onChanged: onChanged,
              activeThumbColor: AppColors.primary,
            )
          : const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
    );
  }
}
