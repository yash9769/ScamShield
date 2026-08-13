// lib/widgets/scan_now_bottom_sheet.dart
// Real bottom sheet for SCAN NOW: file pick, image pick, clipboard scan.

import 'package:flutter/material.dart';
import '../theme.dart';
import 'motion.dart';
import '../services/file_scanner_service.dart';
import '../services/scam_detector.dart';
import '../data/repositories/scan_repository.dart';
import '../data/models/scan_record.dart';
import '../services/report_generator_service.dart';
import '../services/app_capabilities_service.dart';
import '../screens/apk_scan_screen.dart';

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

      // A failed read must not be written to history or shown as a verdict.
      if (result.hasError && result.rawContent.isEmpty) {
        setState(() {
          _isScanning = false;
          _scanStatus = '';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not scan: ${result.error}'),
              backgroundColor: AppColors.danger,
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

  /// Opens the full APK scanner. This is the deep static-analysis pipeline
  /// (Androguard + YARA + OSINT + PDF export) that used to live in its own
  /// bottom-nav tab. We dismiss the sheet first, then push the dedicated
  /// screen so the user gets the complete multi-section report UI.
  void _openApkScanner() {
    Navigator.of(context).pop(); // close the bottom sheet
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ApkScanScreen()),
    );
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
                Reveal(
                  delay: Reveal.step(0),
                  offsetY: 16,
                  child: _buildOption(
                    icon: Icons.folder_open_rounded,
                    color: AppColors.primary,
                    title: 'Scan File',
                    subtitle: 'Pick a .txt, .pdf, .doc, .csv, or other file from your device',
                    onTap: () => _runScan(FileScannerService.pickAndScanFile, 'File'),
                  ),
                ),
                const SizedBox(height: 12),
                Reveal(
                  delay: Reveal.step(1),
                  offsetY: 16,
                  child: _buildOption(
                    icon: Icons.image_outlined,
                    color: AppColors.accent,
                    title: 'Scan Image',
                    subtitle: 'Pick a screenshot or photo from your gallery',
                    onTap: () => _runScan(FileScannerService.pickAndScanImage, 'Image'),
                  ),
                ),
                const SizedBox(height: 12),
                Reveal(
                  delay: Reveal.step(2),
                  offsetY: 16,
                  child: _buildOption(
                    icon: Icons.content_paste_rounded,
                    color: AppColors.success,
                    title: 'Scan Clipboard',
                    subtitle: 'Instantly scan whatever text is copied on your clipboard',
                    onTap: () => _runScan(FileScannerService.scanClipboard, 'Clipboard'),
                  ),
                ),
                const SizedBox(height: 12),
                Reveal(
                  delay: Reveal.step(3),
                  offsetY: 16,
                  child: _buildOption(
                    icon: Icons.android_rounded,
                    color: AppColors.warning,
                    title: 'Scan APK / App',
                    subtitle: 'Deep static analysis of an Android .apk — permissions, secrets, YARA & OSINT',
                    onTap: _openApkScanner,
                  ),
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
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
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

    if (!analysis.isAnalyzed) {
      // "Could not analyse" is never rendered as a green safe verdict.
      color = AppColors.textSecondary;
      icon = Icons.help_outline_rounded;
      label = 'NOT ANALYZED';
    } else {
      final caps = AppCapabilitiesService.capabilities.value;
      final isFullAi = analysis.aiPowered && caps.hasFullAi;
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
          color = isFullAi ? AppColors.success : AppColors.warning;
          icon = isFullAi ? Icons.check_circle_rounded : Icons.shield_outlined;
          label = isFullAi ? 'LOOKS SAFE' : 'NO THREATS FOUND (HEURISTIC ONLY)';
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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
                  color: color.withValues(alpha: 0.15),
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
          if (result.source == ScanSource.image || result.error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.warning, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.error ?? 'OCR unavailable — Filename and metadata analysis only.',
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          if (result.apkAnalysis != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Static Analysis Complete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.verified_user, color: AppColors.primary, size: 16),
                const SizedBox(width: 6),
                Text('${result.apkAnalysis!.permissions.length} Permissions | ${result.apkAnalysis!.urls.length} Endpoints', 
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('Export Full PDF Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                try {
                  final file = await ReportGeneratorService.generateApkReport(
                    apk: result.apkAnalysis!,
                    osintResults: result.osintResults ?? [],
                    analysis: result.analysis,
                    fileName: result.fileName,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Report saved to: ${file.path}')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to generate PDF: $e')),
                    );
                  }
                }
              },
            ),
          ]
        ],
      ),
    );
  }
}
