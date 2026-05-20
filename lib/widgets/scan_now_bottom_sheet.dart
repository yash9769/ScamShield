// lib/widgets/scan_now_bottom_sheet.dart
// Real bottom sheet for SCAN NOW: file pick, image pick, clipboard scan.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/file_scanner_service.dart';
import '../services/scam_detector.dart';
import '../data/repositories/scan_repository.dart';
import '../data/models/scan_record.dart';

class ScanNowBottomSheet extends StatefulWidget {
  const ScanNowBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ScanNowBottomSheet(),
    );
  }

  @override
  State<ScanNowBottomSheet> createState() => _ScanNowBottomSheetState();
}

class _ScanNowBottomSheetState extends State<ScanNowBottomSheet> {
  bool _isScanning = false;
  String _scanStatus = '';
  FileScanResult? _result;
  final ScanRepository _repo = ScanRepository();

  Future<void> _runScan(Future<FileScanResult?> Function() scanner, String label) async {
    setState(() {
      _isScanning = true;
      _scanStatus = 'Scanning $label...';
      _result = null;
    });

    try {
      final result = await scanner();
      if (result == null) {
        setState(() {
          _isScanning = false;
          _scanStatus = '';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(label == 'Clipboard'
                  ? 'Clipboard is empty.'
                  : 'No file selected or permission denied.'),
              backgroundColor: AppColors.surface,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        return;
      }

      // Save to SQLite history
      final record = ScanRecord.fromAnalysisResult(
        inputText: result.rawContent,
        result: result.analysis,
        source: result.source == ScanSource.file
            ? 'File: ${result.fileName}'
            : result.source == ScanSource.image
                ? 'Image: ${result.fileName}'
                : 'Clipboard',
      );
      await _repo.saveScan(record);

      setState(() {
        _isScanning = false;
        _result = result;
        _scanStatus = '';
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
        _scanStatus = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Scan Content',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose what to scan for scam indicators',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 24),

              if (_isScanning) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: 16),
                Text(_scanStatus, style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
              ] else if (_result != null) ...[
                _buildResult(_result!),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => setState(() => _result = null),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Scan Another'),
                ),
              ] else ...[
                _buildOption(
                  icon: Icons.folder_open_rounded,
                  color: AppColors.primary,
                  title: 'Scan File',
                  subtitle: 'Pick a .txt, .pdf, .doc, .csv, or other file from your device',
                  onTap: () => _runScan(FileScannerService.pickAndScanFile, 'File'),
                ),
                const SizedBox(height: 12),
                _buildOption(
                  icon: Icons.image_outlined,
                  color: AppColors.accent,
                  title: 'Scan Image',
                  subtitle: 'Pick a screenshot or photo from your gallery',
                  onTap: () => _runScan(FileScannerService.pickAndScanImage, 'Image'),
                ),
                const SizedBox(height: 12),
                _buildOption(
                  icon: Icons.content_paste_rounded,
                  color: AppColors.success,
                  title: 'Scan Clipboard',
                  subtitle: 'Instantly scan whatever text is copied on your clipboard',
                  onTap: () => _runScan(FileScannerService.scanClipboard, 'Clipboard'),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(FileScanResult result) {
    final analysis = result.analysis;
    final Color color;
    final IconData icon;
    final String label;

    switch (analysis.classification) {
      case ScamClassification.scam:
        color = AppColors.danger;
        icon = Icons.warning_rounded;
        label = 'SCAM DETECTED';
      case ScamClassification.suspicious:
        color = AppColors.warning;
        icon = Icons.help_outline_rounded;
        label = 'SUSPICIOUS';
      case ScamClassification.safe:
        color = AppColors.success;
        icon = Icons.check_circle_rounded;
        label = 'LOOKS SAFE';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(result.fileName,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${analysis.riskScore}',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(analysis.summary,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }
}
