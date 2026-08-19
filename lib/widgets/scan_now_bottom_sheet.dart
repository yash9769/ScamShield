// lib/widgets/scan_now_bottom_sheet.dart
// Complete scan launcher bottom sheet — all scan types active and functional.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import 'motion.dart';
import '../screens/apk_scan_screen.dart';
import '../screens/scan_screen.dart';

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
  void _openScanMessage() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ScanScreen(initialTab: 0),
      ),
    );
  }

  void _openScanUrl() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ScanScreen(initialTab: 1),
      ),
    );
  }

  void _openScanFile() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ScanScreen(initialTab: 4, autoPick: true),
      ),
    );
  }

  void _openScanImage() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ScanScreen(initialTab: 3, autoPick: true),
      ),
    );
  }

  Future<void> _openScanClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    Navigator.of(context).pop();
    if (text.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScanScreen(initialText: text),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Clipboard is empty. Copy a message or link first.',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ScanScreen(initialTab: 0),
        ),
      );
    }
  }

  void _openApkScanner() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ApkScanScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
              Text(
                'What would you like to scan?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'All scans use Gemini AI + OSINT for full analysis',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),

              // Row 1: Message + URL
              Row(
                children: [
                  Expanded(
                    child: Reveal(
                      delay: Reveal.step(0),
                      offsetY: 16,
                      child: _buildCompactOption(
                        icon: Icons.mark_chat_unread_rounded,
                        color: AppColors.cobalt,
                        title: 'Message',
                        subtitle: 'SMS / Text',
                        onTap: _openScanMessage,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Reveal(
                      delay: Reveal.step(1),
                      offsetY: 16,
                      child: _buildCompactOption(
                        icon: Icons.link_rounded,
                        color: AppColors.electricBlue,
                        title: 'URL / Link',
                        subtitle: 'Web Check',
                        onTap: _openScanUrl,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Row 2: Screenshot + File
              Row(
                children: [
                  Expanded(
                    child: Reveal(
                      delay: Reveal.step(2),
                      offsetY: 16,
                      child: _buildCompactOption(
                        icon: Icons.image_rounded,
                        color: AppColors.accent,
                        title: 'Screenshot',
                        subtitle: 'OCR Scan',
                        onTap: _openScanImage,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Reveal(
                      delay: Reveal.step(3),
                      offsetY: 16,
                      child: _buildCompactOption(
                        icon: Icons.description_rounded,
                        color: AppColors.primary,
                        title: 'Document',
                        subtitle: 'File Scan',
                        onTap: _openScanFile,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Row 3: Clipboard + APK
              Row(
                children: [
                  Expanded(
                    child: Reveal(
                      delay: Reveal.step(4),
                      offsetY: 16,
                      child: _buildCompactOption(
                        icon: Icons.content_paste_rounded,
                        color: AppColors.success,
                        title: 'Clipboard',
                        subtitle: 'Quick Scan',
                        onTap: _openScanClipboard,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Reveal(
                      delay: Reveal.step(5),
                      offsetY: 16,
                      child: _buildCompactOption(
                        icon: Icons.android_rounded,
                        color: AppColors.warning,
                        title: 'APK / App',
                        subtitle: 'Deep Scan',
                        onTap: _openApkScanner,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactOption({
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
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
