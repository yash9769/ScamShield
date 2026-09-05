// lib/screens/privacy_settings_screen.dart
//
// Settings > Privacy & Data hub: Privacy Policy, consent management, data
// access/export, retention configuration, and the two erasure flows
// ("Delete My Data" and "Delete Account").

import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/consent_service.dart';
import '../services/auth_service.dart';
import '../services/google_auth_service.dart';
import '../data/repositories/scan_repository.dart';
import '../data/repositories/preferences_repository.dart';
import '../services/data_privacy_service.dart';
import 'privacy_policy_screen.dart';
import 'my_data_screen.dart';
import 'login_screen.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final _consentService = ConsentService();
  final _preferencesRepository = PreferencesRepository();
  final _scanRepository = ScanRepository();
  final _dataPrivacyService = DataPrivacyService();

  bool _aiEnabled = true;
  int _autoDeleteDays = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final aiEnabled = await _consentService.isAiProcessingEnabled();
    final prefs = await _preferencesRepository.load();
    if (mounted) {
      setState(() {
        _aiEnabled = aiEnabled;
        _autoDeleteDays = prefs.autoDeleteDays;
      });
    }
  }

  Future<void> _setAiEnabled(bool value) async {
    setState(() => _aiEnabled = value);
    await _consentService.setAiProcessingEnabled(value);
  }

  Future<void> _setRetention(int days) async {
    setState(() => _autoDeleteDays = days);
    await _preferencesRepository.setAutoDelete(days);
    if (days > 0) {
      final removed = await _scanRepository.deleteOlderThan(days);
      if (mounted && removed > 0) {
        _showSnack('Removed $removed scan record(s) older than $days days.');
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _confirmDeleteMyData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete My Data?'),
        content: const Text(
          'This permanently deletes your scan history, all Safe Vault items, and all '
          'generated reports on this device. Your account stays signed in. This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete Data', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await _dataPrivacyService.deleteAllScanAndVaultData();
    if (!mounted) return;
    setState(() => _busy = false);
    _showSnack('Your scan history, Safe Vault and reports have been deleted.');
  }

  Future<void> _confirmDeleteAccount() async {
    // Deleting an account must be re-authenticated, but a Google-linked
    // account has no password on this device — asking for one would lock
    // those users out of erasing their own data, which is exactly the right
    // they're entitled to. Each provider re-verifies its own way.
    final provider = await AuthService.currentProvider();
    if (!mounted) return;

    final confirmed = provider == AuthProvider.google
        ? await _confirmDeleteWithGoogle()
        : await _confirmDeleteWithPassword();

    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await _dataPrivacyService.deleteAccountAndAllData();
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  /// Re-verifies by signing in with Google again and requiring the returned
  /// address to match the account on this device, so signing in with a
  /// different Google account cannot delete someone else's data.
  Future<bool?> _confirmDeleteWithGoogle() async {
    final registeredEmail = await AuthService.registeredEmail();
    if (!mounted) return false;
    String? error;
    bool verifying = false;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.danger),
              SizedBox(width: 8),
              Expanded(child: Text('Delete Account?')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This permanently deletes your account, profile, scan history, Safe Vault '
                  'and all local data on this device. This cannot be undone.\n\n'
                  'Confirm with Google to continue as ${registeredEmail ?? 'your account'}.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: verifying ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: verifying
                  ? null
                  : () async {
                      setDialogState(() {
                        verifying = true;
                        error = null;
                      });
                      final result = await GoogleAuthService.signIn();
                      if (!ctx.mounted) return;

                      if (!result.isSuccess) {
                        setDialogState(() {
                          verifying = false;
                          if (result.status != GoogleAuthStatus.cancelled) {
                            error = result.message ?? 'Verification failed. Try again.';
                          }
                        });
                        return;
                      }
                      if (result.email?.toLowerCase() != registeredEmail?.toLowerCase()) {
                        setDialogState(() {
                          verifying = false;
                          error = 'That Google account does not match the account on this device.';
                        });
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              child: verifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Verify & Delete',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDeleteWithPassword() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final registeredEmail = await AuthService.registeredEmail();
    emailController.text = registeredEmail ?? '';
    String? error;

    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.danger),
              SizedBox(width: 8),
              Text('Delete Account?'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This permanently deletes your account, profile, scan history, Safe Vault '
                  'and all local data on this device. This cannot be undone. Re-enter your '
                  'password to confirm.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final result = await AuthService.login(
                  emailController.text,
                  passwordController.text,
                );
                if (result == AuthResult.success) {
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } else {
                  setDialogState(() => error = 'Incorrect password. Try again.');
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('Delete Account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Data', style: TextStyle(fontWeight: FontWeight.bold))),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Opacity(
          opacity: _busy ? 0.5 : 1,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionHeader('Transparency'),
              _card([
                _tile(
                  Icons.article_outlined,
                  'Privacy Policy',
                  'What we process and why',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                ),
                _tile(
                  Icons.hub_outlined,
                  'Third-Party Data Sharing',
                  'Groq/Gemini, VirusTotal, Safe Browsing, XposedOrNot',
                  onTap: () => _showThirdPartyInfo(context),
                ),
              ]),
              const SizedBox(height: 24),
              _sectionHeader('Manage Consent'),
              _card([
                SwitchListTile(
                  value: _aiEnabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: _setAiEnabled,
                  title: const Text('AI-Assisted Analysis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text(
                    'When on, scan text may be sent to Groq/Gemini for a more accurate verdict. '
                    'When off, only the on-device heuristic engine is used — scanning still works.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              _sectionHeader('My Data'),
              _card([
                _tile(
                  Icons.folder_open_outlined,
                  'My Data',
                  'View & export what ScamShield stores about you',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyDataScreen())),
                ),
              ]),
              const SizedBox(height: 24),
              _sectionHeader('Data Retention'),
              _card([
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Auto-delete scan history older than:',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: Wrap(
                    spacing: 8,
                    children: [0, 30, 90, 180].map((days) {
                      final selected = _autoDeleteDays == days;
                      return ChoiceChip(
                        label: Text(days == 0 ? 'Never' : '$days days'),
                        selected: selected,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: selected ? Colors.black : AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        backgroundColor: AppColors.background,
                        onSelected: (_) => _setRetention(days),
                      );
                    }).toList(),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              _sectionHeader('Erase Data'),
              _card([
                _tile(
                  Icons.delete_sweep_outlined,
                  'Delete My Data',
                  'Erase scan history, Safe Vault & reports (keep account)',
                  isDestructive: true,
                  onTap: _confirmDeleteMyData,
                ),
                _tile(
                  Icons.no_accounts_outlined,
                  'Delete Account',
                  'Permanently erase your account and all local data',
                  isDestructive: true,
                  onTap: _confirmDeleteAccount,
                ),
              ]),
              const SizedBox(height: 24),
              _sectionHeader('Grievance / Contact'),
              _card([
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'A designated grievance contact has not yet been configured for this build. '
                    'REQUIRES PRODUCT/LEGAL DECISION before production release.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showThirdPartyInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Third-Party Data Sharing'),
        content: const SingleChildScrollView(
          child: Text(
            '• Groq or Google Gemini — scan text you submit, for AI classification (whichever is configured server-side).\n\n'
            '• VirusTotal — the SHA-256 hash of APK files you scan.\n\n'
            '• Google Safe Browsing — URLs found in scanned messages/APKs.\n\n'
            '• XposedOrNot — the email address you enter for breach lookup.\n\n'
            'Full technical detail is in THIRD_PARTY_DATA_PROCESSORS.md in the project repository.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: AppColors.primary))),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1),
        ),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
        ),
        child: Column(children: children),
      );

  Widget _tile(IconData icon, String title, String subtitle,
      {required VoidCallback onTap, bool isDestructive = false}) {
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
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
    );
  }
}
