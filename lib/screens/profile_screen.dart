import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Edit Profile & Avatar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose Avatar:', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 12)),
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
                          border: Border.all(color: isSel ? AppColors.cobalt : Colors.transparent, width: 3),
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
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Security Title',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
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
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.cobalt),
              child: Text('Save & Sync', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Secure Sign Out?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        content: Text(
          'You will be returned to the sign-in screen. Your saved data stays on this device.',
          style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
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
            child: Text('Sign Out', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.shield_outlined, color: AppColors.cobalt),
            const SizedBox(width: 8),
            Text('About ScamShield', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ScamShield v2.1', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            Text('Active Mode: ${caps.modeLabel}', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.cobalt)),
            const SizedBox(height: 10),
            Text('Features & Integrations:', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(
              '• Server AI Analysis (Gemini/Groq): ${caps.hasFullAi ? "Active" : "Unavailable"}\n'
              '• Live Threat Intel (VirusTotal/SafeBrowsing): ${caps.hasOsint ? "Active" : "Unavailable"}\n'
              '• APK Pipeline: ${caps.hasFullApkPipeline ? "Active" : "Local Static Analysis"}\n'
              '• Storage: PBKDF2 Auth & Hardware AES-256 Vault',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.5, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.cobalt),
            child: Text('Close', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ScamShield Profile', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
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
                    Icons.content_paste_search_rounded,
                    'Clipboard Check',
                    'Offer to scan copied links and messages',
                    hasSwitch: true,
                    switchValue: enabled,
                    onChanged: (v) => SettingsService.setAutoScanClipboard(v),
                  ),
                ),
                _buildSettingItem(
                  Icons.history_rounded,
                  'Scan History',
                  '${_stats?.totalScans ?? 0} record(s) in local database',
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
                  Icons.info_outline_rounded,
                  'About ScamShield',
                  'Version, AI & threat engine status',
                  hasSwitch: false,
                  onTap: _showAboutInfo,
                ),
                _buildSettingItem(
                  Icons.logout_rounded,
                  'Secure Sign Out',
                  'Return to sign-in screen',
                  hasSwitch: false,
                  isDestructive: true,
                  onTap: _showSignOutDialog,
                ),
              ]),
            ),
            const SizedBox(height: 90),
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
                    border: Border.all(color: AppColors.cobalt, width: 2),
                    boxShadow: [
                      BoxShadow(color: AppColors.cobalt.withValues(alpha: 0.25), blurRadius: 16, spreadRadius: 2),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 46,
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
                  decoration: const BoxDecoration(color: AppColors.cobalt, shape: BoxShape.circle),
                  child: const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ValueListenableBuilder<String>(
          valueListenable: UserProfileService.nameNotifier,
          builder: (ctx, name, _) => Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        ),
        const SizedBox(height: 4),
        ValueListenableBuilder<String>(
          valueListenable: UserProfileService.titleNotifier,
          builder: (ctx, title, _) => Text(title, style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildSecurityCards() {
    final total = _stats?.totalScans ?? 0;
    return Row(
      children: [
        Expanded(child: _buildSecurityCard('TOTAL SCANS', '$total Executed', Icons.radar_rounded, total > 0 ? '$total LOGS' : '0 LOGS', AppColors.cobalt)),
        const SizedBox(width: 12),
        Expanded(child: _buildSecurityCard('ENCRYPTION', 'AES-256 KeyStore', Icons.lock_outline_rounded, 'LOCAL VAULT', AppColors.safeEmerald)),
      ],
    );
  }

  Widget _buildSecurityCard(String label, String value, IconData icon, String badge, Color badgeColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
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
                child: Text(badge, style: GoogleFonts.plusJakartaSans(color: badgeColor, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(label, style: GoogleFonts.plusJakartaSans(color: AppColors.mutedText, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.mutedText, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildSettingsList(List<Widget> children) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
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
          color: (isDestructive ? AppColors.danger : AppColors.cobalt).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: isDestructive ? AppColors.danger : AppColors.cobalt, size: 20),
      ),
      title: Text(title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14, color: isDestructive ? AppColors.danger : AppColors.textPrimary)),
      subtitle: Text(subtitle, style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 12)),
      trailing: hasSwitch
          ? Switch(
              value: switchValue,
              onChanged: onChanged,
              activeThumbColor: AppColors.cobalt,
            )
          : const Icon(Icons.chevron_right_rounded, color: AppColors.mutedText, size: 20),
    );
  }
}
