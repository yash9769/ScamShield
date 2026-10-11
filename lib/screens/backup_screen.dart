// lib/screens/backup_screen.dart
//
// Create and restore an encrypted backup. See backup_service.dart for the
// format and the reasoning behind it.
//
// The passphrase warning on this screen is not boilerplate. The backup is
// encrypted with a key derived from that passphrase and nothing else — there
// is no recovery path, by design, because any recovery path would mean someone
// other than the user could open the file. Saying that plainly before they
// choose a passphrase is the only honest option.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../theme.dart';
import '../services/backup_service.dart';
import '../services/data_change_notifier.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String? _status;
  bool _statusIsError = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _card(
            icon: Icons.lock_outline,
            color: AppColors.primary,
            title: 'Encrypted backup',
            body: 'Your scan history, profile and settings are encrypted with a '
                'passphrase you choose, then written to a file you keep. It works '
                'offline and needs no account.',
          ),
          const SizedBox(height: 12),
          _card(
            icon: Icons.shield_outlined,
            color: AppColors.warning,
            title: 'What is not included',
            body: 'Safe Vault contents and your sign-in details stay out of the '
                'backup. The vault is held in your phone\'s secure hardware '
                'storage, and moving it into a file protected only by a typed '
                'passphrase would weaken it, not protect it.',
          ),
          const SizedBox(height: 24),
          _button(
            label: 'Create backup',
            icon: Icons.save_alt,
            filled: true,
            onPressed: _busy ? null : _createBackup,
          ),
          const SizedBox(height: 12),
          _button(
            label: 'Restore from a backup',
            icon: Icons.settings_backup_restore,
            filled: false,
            onPressed: _busy ? null : _restoreBackup,
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            const SizedBox(height: 8),
            const Text(
              // PBKDF2 at 210,000 iterations takes a visible moment on a phone.
              // Saying why avoids it reading as a hang.
              'Deriving the encryption key — this takes a few seconds by design.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          if (_status != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (_statusIsError ? AppColors.danger : AppColors.success)
                      .withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _statusIsError ? Icons.error_outline : Icons.check_circle_outline,
                    color: _statusIsError ? AppColors.danger : AppColors.success,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _status!,
                      style: const TextStyle(fontSize: 13, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createBackup() async {
    final passphrase = await _askPassphrase(
      title: 'Choose a passphrase',
      body: 'This passphrase is the only way to open the backup. Nobody — not '
          'ScamShield, not anyone else — can recover it for you if you forget '
          'it. Write it down somewhere safe.',
      confirm: true,
    );
    if (passphrase == null || !mounted) return;

    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      final contents = await BackupService.create(passphrase);
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final file = File('${dir.path}/ScamShield_Backup_$stamp.scamshield');
      await file.writeAsString(contents);
      await OpenFilex.open(file.path);
      _report('Backup saved to ${file.path}. Copy it somewhere safe — a '
          'backup that only exists on this phone does not survive losing it.');
    } on BackupException catch (e) {
      _report(e.message, isError: true);
    } catch (e) {
      _report('Could not write the backup file.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final picked = await FilePicker.platform.pickFiles(withData: false);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    String contents;
    try {
      contents = await File(path).readAsString();
    } catch (e) {
      _report('Could not read that file.', isError: true);
      return;
    }

    // Read the header before asking for anything: no reason to make someone
    // type a passphrase for a file that was never a backup.
    final createdAt = BackupService.peekCreatedAt(contents);
    if (createdAt == null) {
      _report('That file is not a ScamShield backup.', isError: true);
      return;
    }
    if (!mounted) return;

    final passphrase = await _askPassphrase(
      title: 'Enter the passphrase',
      body: 'This backup was made on '
          '${createdAt.day}/${createdAt.month}/${createdAt.year}. Scans already '
          'on this phone are kept — restoring adds to them rather than '
          'replacing them.',
      confirm: false,
    );
    if (passphrase == null || !mounted) return;

    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      final result = await BackupService.restore(contents, passphrase);
      // Other screens are kept alive in an IndexedStack and need telling.
      DataChangeNotifier.notifyChanged();
      _report('Restored ${result.scansRestored} scan(s).'
          '${result.scansSkipped > 0 ? ' ${result.scansSkipped} were already here and were skipped.' : ''}');
    } on BackupException catch (e) {
      _report(e.message, isError: true);
    } catch (e) {
      _report('Restore failed.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _report(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusIsError = isError;
    });
  }

  /// Asks for a passphrase, optionally twice. Confirming on creation matters
  /// more here than in most places: a typo produces a file that looks fine and
  /// is permanently unopenable, and nothing later would reveal the mistake.
  Future<String?> _askPassphrase({
    required String title,
    required String body,
    required bool confirm,
  }) async {
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  body,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12.5, height: 1.45),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: first,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Passphrase',
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (confirm) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: second,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Type it again',
                      labelStyle: const TextStyle(color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                final value = first.text;
                if (value.length < BackupService.minPassphraseLength) {
                  setDialogState(() => error =
                      'Use at least ${BackupService.minPassphraseLength} characters.');
                  return;
                }
                if (confirm && value != second.text) {
                  setDialogState(() => error = 'The two passphrases do not match.');
                  return;
                }
                Navigator.pop(ctx, value);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Continue',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    first.dispose();
    second.dispose();
    return result;
  }

  Widget _card({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _button({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback? onPressed,
  }) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: filled ? Colors.black : AppColors.primary),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: filled ? Colors.black : AppColors.primary,
          ),
        ),
      ],
    );

    return SizedBox(
      height: 52,
      child: filled
          ? ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary, width: 1.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: child,
            ),
    );
  }
}
