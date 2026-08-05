// lib/screens/privacy_data_screen.dart
// Privacy & Data controls: retention, clearing scan history, resetting progress.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../data/repositories/preferences_repository.dart';
import '../data/models/user_preferences.dart';
import '../data/repositories/scan_repository.dart';
import '../data/education/progress_service.dart';

class PrivacyDataScreen extends StatefulWidget {
  const PrivacyDataScreen({super.key});

  @override
  State<PrivacyDataScreen> createState() => _PrivacyDataScreenState();
}

class _PrivacyDataScreenState extends State<PrivacyDataScreen> {
  final PreferencesRepository _prefsRepo = PreferencesRepository();
  final ScanRepository _scanRepo = ScanRepository();
  final ProgressService _progressService = ProgressService();

  UserPreferences? _prefs;
  int _scanCount = 0;
  bool _isLoading = true;

  static const _retentionOptions = <int>[0, 7, 30, 90];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await _prefsRepo.load();
    final stats = await _scanRepo.getStatistics();
    if (mounted) {
      setState(() {
        _prefs = prefs;
        _scanCount = stats.totalScans;
        _isLoading = false;
      });
    }
  }

  String _retentionLabel(int days) {
    if (days == 0) return 'Keep Forever';
    return 'Delete after $days days';
  }

  Future<void> _setAutoDelete(int days) async {
    setState(() {
      _prefs = _prefs?.copyWith(autoDeleteDays: days);
    });
    await _prefsRepo.setAutoDelete(days);
    if (days > 0) {
      await _scanRepo.deleteOlderThan(days);
      await _load();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(days == 0
              ? 'History kept forever.'
              : 'Old scans older than $days days deleted.'),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteAllScans() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete All Scan Data?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'All saved scan records on this device will be permanently removed.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _scanRepo.clearHistory();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All scan data deleted.'),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _resetProgress() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset Learning Progress?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'This clears your badges, points, quiz scores and reading progress.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _progressService.resetProgress();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Learning progress reset.'),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _prefs == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    final prefs = _prefs!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & Data', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Your data stays on this device. All scans are analysed locally and never leave your phone.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 24),
          _sectionTitle('Scan History Retention'),
          const SizedBox(height: 12),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: _retentionOptions.map((days) {
                final isSelected = prefs.autoDeleteDays == days;
                return ListTile(
                  title: Text(_retentionLabel(days), style: const TextStyle(fontSize: 14)),
                  trailing: Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  ),
                  onTap: () => _setAutoDelete(days),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle('Storage'),
          const SizedBox(height: 12),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: AppColors.danger),
                  title: const Text('Delete All Scan History', style: TextStyle(fontSize: 14)),
                  subtitle: Text('$_scanCount scans stored locally', style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                  onTap: _deleteAllScans,
                ),
                const Divider(color: AppColors.background, height: 1),
                ListTile(
                  leading: const Icon(Icons.restart_alt, color: AppColors.warning),
                  title: const Text('Reset Learning Progress', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Badges, points, quiz scores', style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                  onTap: _resetProgress,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: AppColors.primary, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'ScamShield never collects, uploads or shares your scanned content. Encryption, history and preferences are all managed on-device.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
  }
}
