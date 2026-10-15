// lib/screens/my_data_screen.dart
//
// DPDP "right to access": lets the user see a summary of what ScamShield
// holds about them on this device, and export it as a JSON file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

import '../theme.dart';
import '../services/data_privacy_service.dart';

class MyDataScreen extends StatefulWidget {
  const MyDataScreen({super.key});

  @override
  State<MyDataScreen> createState() => _MyDataScreenState();
}

class _MyDataScreenState extends State<MyDataScreen> {
  final _service = DataPrivacyService();
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _exporting = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _service.exportUserData();
    if (mounted) {
      setState(() {
        _data = data;
        _loading = false;
      });
    }
  }

  Future<void> _export() async {
    if (_data == null || _exporting) return;
    setState(() {
      _exporting = true;
      _statusMessage = null;
    });
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/ScamShield_MyData_${DateTime.now().millisecondsSinceEpoch}.json');
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(_data));
      await OpenFilex.open(file.path);
      if (mounted) setState(() => _statusMessage = 'Exported and opened.');
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'Export failed: could not write file.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scans = (_data?['scanHistory'] as List?)?.length ?? 0;
    final vaultItems =
        (_data?['safeVaultItems (titles/categories only — see note)'] as List?)?.length ?? 0;
    final email = _data?['account']?['email'] as String?;
    final cloudSection = _data?['cloudSyncAccount'] as Map<String, dynamic>?;
    final cloudSignedIn = cloudSection?['signedIn'] == true;
    final cloudScans = ((cloudSection?['data'] as Map?)?['syncedScans'] as List?)?.length;
    final points = (_data?['learningProgress'] as Map?)?['totalPoints'];

    return Scaffold(
      appBar: AppBar(title: const Text('My Data', style: TextStyle(fontWeight: FontWeight.bold))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Summary of what ScamShield stores about you on this device.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  _row('Account email', email ?? '(no local account)'),
                  _row('Profile name', _data?['profile']?['name'] ?? '—'),
                  _row('Scan history records', '$scans'),
                  _row('Safe Vault items', '$vaultItems (titles only shown here)'),
                  _row(
                    'AI-assisted analysis',
                    (_data?['consent']?['aiProcessingConsent'] == true) ? 'Enabled' : 'Disabled',
                  ),
                  _row(
                    'Privacy Policy agreed',
                    _data?['consent']?['privacyPolicyVersionAgreed'] ?? 'Not recorded',
                  ),
                  _row('Learning points', '${points ?? 0}'),
                  const SizedBox(height: 8),
                  _row(
                    'Cloud sync account',
                    cloudSignedIn
                        ? 'Signed in${cloudScans != null ? ' · $cloudScans scan(s) held on the server' : ''}'
                        : 'Not signed in — nothing held on the server',
                  ),
                  if (cloudSignedIn && cloudSection?['data'] == null) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Could not reach the server just now to fetch what it holds for this '
                      'section — try exporting again while online for the full picture.',
                      style: TextStyle(color: AppColors.warning, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: AppColors.textSecondary, size: 18),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Safe Vault secret contents are not included in this export — only '
                            'titles and categories — so exporting never writes your stored '
                            'passwords/PINs to an unencrypted file.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _exporting ? null : _export,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: _exporting
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.download_outlined, color: Colors.black),
                      label: const Text('Export My Data (JSON)',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(_statusMessage!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
