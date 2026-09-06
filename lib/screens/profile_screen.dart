import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../services/user_profile_service.dart';
import '../services/settings_service.dart';
import '../services/sms_screening_service.dart';
import '../services/call_screening_service.dart';
import '../services/auth_service.dart';
import '../data/repositories/scan_repository.dart';
import '../data/models/scan_record.dart';
import 'login_screen.dart';
import 'history_screen.dart';
import 'privacy_settings_screen.dart';
import 'family_screen.dart';
import 'trends_screen.dart';
import 'language_screen.dart';
import '../services/localization_service.dart';
import '../services/simple_mode_service.dart';
import '../services/data_change_notifier.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ScanRepository _repo = ScanRepository();
  ScanStatistics? _stats;

  /// Android 10+ with the role API present. Resolved once, because it cannot
  /// change while the app is running.
  bool _callScreeningSupported = false;

  @override
  void initState() {
    super.initState();
    SettingsService.init();
    _loadStats();
    _resolveCallScreeningSupport();
    // See data_change_notifier.dart: this screen stays alive in
    // MainNavigation's IndexedStack and needs an explicit signal to refresh
    // after a scan/deletion made from another tab or screen.
    DataChangeNotifier.version.addListener(_loadStats);
  }

  @override
  void dispose() {
    DataChangeNotifier.version.removeListener(_loadStats);
    super.dispose();
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

  Future<void> _onToggleSmsScreening(bool wantsOn) async {
    if (!wantsOn) {
      await SmsScreeningService.disable();
      return;
    }

    // A sensitive permission deserves an explanation before the system
    // prompt, not just after a denial.
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.sms_outlined, color: AppColors.primary),
            SizedBox(width: 8),
            Expanded(child: Text('Read incoming SMS?')),
          ],
        ),
        content: const Text(
          'ScamShield will screen each incoming text message for scam content the '
          'moment it arrives, using the same engine as manual scans, and alert you '
          'if one looks dangerous. Message text stays on this device and is never '
          'sent anywhere except to the same AI analysis service manual scans use.\n\n'
          'This does not make ScamShield your messaging app — it just watches '
          'alongside it.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Allow', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final granted = await SmsScreeningService.requestPermissionAndEnable();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS permission was not granted, so real-time protection stays off.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceLight,
        ),
      );
    }
  }

  Future<void> _resolveCallScreeningSupport() async {
    final supported = await CallScreeningService.isSupported();
    if (mounted) setState(() => _callScreeningSupported = supported);
  }

  Future<void> _onToggleCallScreening(bool wantsOn) async {
    if (!wantsOn) {
      await CallScreeningService.disable();
      if (!mounted) return;
      // Switching the feature off stops the screening, but Android still lists
      // ScamShield as the call-screening app until the user says otherwise.
      // Saying so — and offering the way there — is more honest than letting
      // them think the off switch removed it.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Call screening stopped. Android still lists ScamShield '
              'as your screening app until you change it in system settings.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceLight,
          duration: const Duration(seconds: 7),
          action: SnackBarAction(
            label: 'SETTINGS',
            textColor: AppColors.primary,
            onPressed: CallScreeningService.openSystemRoleSettings,
          ),
        ),
      );
      return;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.phone_in_talk_outlined, color: AppColors.primary),
            SizedBox(width: 8),
            Expanded(child: Text('Screen incoming calls?')),
          ],
        ),
        content: const Text(
          'Android will ask you to make ScamShield your call screening app. When a '
          'number you or the community have already flagged calls you, ScamShield '
          'warns you while it is still ringing.\n\n'
          'It never blocks or rejects a call. A wrongly blocked call could be a '
          'hospital or your bank, so the call always comes through and the warning '
          'is yours to act on.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Continue', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final granted = await CallScreeningService.requestRoleAndEnable();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ScamShield was not made your call screening app, so call '
              'screening stays off.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceLight,
        ),
      );
    }
  }

  Future<void> _onToggleSimpleMode(bool wantsOn) async {
    if (!wantsOn) {
      await SimpleModeService.setEnabled(false);
      return;
    }

    // Worth explaining before switching: this replaces the whole interface,
    // and someone turning it on for a parent should know what that parent will
    // actually see.
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.accessibility_new, color: AppColors.primary),
            SizedBox(width: 8),
            Expanded(child: Text('Turn on Simple Mode?')),
          ],
        ),
        content: const Text(
          'The app becomes a single screen: paste a message, press one button, '
          'and get a large, plain-language answer that says what to do — no '
          'tabs, no risk scores, no jargon.\n\n'
          'Scanning works exactly the same underneath. You can switch back at '
          'any time from a link at the bottom of that screen.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Turn on', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    await SimpleModeService.setEnabled(true);
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
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ScamShield 3.0 Enterprise', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Text('Features & Integrations:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text(
              '- Explainable Gemini AI message evaluation\n'
              '- Static APK Analysis (Androguard & YARA)\n'
              '- VirusTotal & Safe Browsing threat intel APIs\n'
              '- SQLite local database with zero dummy records',
              style: TextStyle(fontSize: 12, height: 1.5),
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
            Reveal(delay: Reveal.step(2), child: _buildSectionHeader('Protection')),
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
              ValueListenableBuilder<bool>(
                valueListenable: SmsScreeningService.isActive,
                builder: (ctx, active, _) => _buildSettingItem(
                  Icons.sms_outlined,
                  'Real-Time SMS Protection',
                  'Screen incoming texts for scams the moment they arrive',
                  hasSwitch: true,
                  switchValue: active,
                  onChanged: _onToggleSmsScreening,
                ),
              ),
              // Hidden rather than shown-and-disabled below Android 10: a
              // control that can never be switched on is just a dead end.
              if (_callScreeningSupported)
                ValueListenableBuilder<bool>(
                  valueListenable: CallScreeningService.isActive,
                  builder: (ctx, active, _) => _buildSettingItem(
                    Icons.phone_in_talk_outlined,
                    'Scam Call Screening',
                    'Warn before you answer a number known for scams',
                    hasSwitch: true,
                    switchValue: active,
                    onChanged: _onToggleCallScreening,
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
            Reveal(delay: Reveal.step(4), child: _buildSectionHeader('Account and data')),
            const SizedBox(height: 12),
            Reveal(
              delay: Reveal.step(5),
              child: _buildSettingsList([
              ValueListenableBuilder<bool>(
                valueListenable: SimpleModeService.enabled,
                builder: (ctx, simple, _) => _buildSettingItem(
                  Icons.accessibility_new,
                  'Simple Mode',
                  'One big button, plain-language warnings, no jargon',
                  hasSwitch: true,
                  switchValue: simple,
                  onChanged: _onToggleSimpleMode,
                ),
              ),
              _buildSettingItem(
                Icons.language,
                LocalizationService.tr('language_title'),
                LocalizationService.current.nativeName,
                hasSwitch: false,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LanguageScreen()))
                    .then((_) => setState(() {})),
              ),
              _buildSettingItem(
                Icons.family_restroom,
                'Family Protection',
                'Get alerted when a relative scans something dangerous',
                hasSwitch: false,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FamilyScreen())),
              ),
              _buildSettingItem(
                Icons.trending_up,
                'Scam Trends',
                'What the community is reporting this week',
                hasSwitch: false,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrendsScreen())),
              ),
              _buildSettingItem(
                Icons.privacy_tip_outlined,
                'Privacy & Data',
                'Consent, retention, export & deletion',
                hasSwitch: false,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacySettingsScreen())),
              ),
              _buildSettingItem(
                Icons.info_outline,
                'About ScamShield',
                'Version, AI & threat engines status',
                hasSwitch: false,
                onTap: _showAboutInfo,
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
        Expanded(child: _buildSecurityCard('ENCRYPTION', 'Military Grade', Icons.lock_outline, 'ACTIVE', AppColors.success)),
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

  /// Section label. Sentence case now — the old version upcased whatever it
  /// was given and added +1 tracking, which turned "Account & System" into
  /// "A C C O U N T   &   S Y S T E M".
  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(title, style: AppText.label),
    );
  }

  Widget _buildSettingsList(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            // Inset hairline: separates rows without slicing the card edge to
            // edge. Previously the rows just stacked with no separation at all.
            if (i != children.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 60, right: AppSpacing.lg),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
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
      // A neutral tile, not a tinted one. Fifteen accent-coloured icons down a
      // settings list is fifteen things asking to be looked at; the icon is
      // there to help you find a row you already know the name of.
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDestructive
              ? AppColors.danger.withValues(alpha: 0.12)
              : AppColors.surfaceLight.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon,
            color: isDestructive ? AppColors.danger : AppColors.textPrimary, size: 19),
      ),
      title: Text(title,
          style: AppText.subheading.copyWith(
              color: isDestructive ? AppColors.danger : AppColors.textPrimary)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(subtitle, style: AppText.secondary),
      ),
      trailing: hasSwitch
          ? Switch(
              value: switchValue,
              onChanged: onChanged,
              activeThumbColor: AppColors.primary,
            )
          : const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 22),
    );
  }
}
