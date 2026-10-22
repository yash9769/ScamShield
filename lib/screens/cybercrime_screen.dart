// lib/screens/cybercrime_screen.dart
//
// "Report a cybercrime": the one place that answers "I've been scammed, what do
// I do now?". The complaint-evidence PDF generator already existed, but it was
// only reachable by opening Scan History, tapping a record and scrolling a
// bottom sheet, which meant nobody found it. This puts the whole path on one
// screen: call the helpline, open the portal, what to do in the first hour for
// money lost, and a one-tap evidence PDF built from any saved scan.
//
// ScamShield cannot file for the user (India's NCRP has no public filing API),
// so it is honest about that: it prepares the evidence and opens the right
// places.

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models/scan_record.dart';
import '../data/repositories/scan_repository.dart';
import '../services/report_generator_service.dart';
import '../theme.dart';

class CybercrimeScreen extends StatefulWidget {
  /// When opened from a specific result, that scan is offered first.
  final ScanRecord? record;

  const CybercrimeScreen({super.key, this.record});

  @override
  State<CybercrimeScreen> createState() => _CybercrimeScreenState();
}

class _CybercrimeScreenState extends State<CybercrimeScreen> {
  final ScanRepository _repo = ScanRepository();
  List<ScanRecord> _recent = const [];
  int? _exporting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await _repo.loadHistory(limit: 30);
      // Flagged first: those are the ones worth a complaint.
      final flagged = all
          .where((r) => r.classification.toLowerCase() != 'safe')
          .toList();
      if (mounted) setState(() => _recent = flagged.take(6).toList());
    } catch (_) {}
  }

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open ${uri.scheme == 'tel' ? 'the dialer' : uri.host}.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _export(ScanRecord record, int index) async {
    setState(() => _exporting = index);
    try {
      final file = await ReportGeneratorService.generateComplaintReport(
        record: record,
      );
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not create the complaint PDF: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = <ScanRecord>[
      if (widget.record != null) widget.record!,
      ..._recent.where(
        (r) =>
            widget.record == null ||
            r.inputText != widget.record!.inputText ||
            r.timestamp != widget.record!.timestamp,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Report a cybercrime')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          const Text(
            'If money was taken, the first hour matters most. Banks can often '
            'freeze a transfer that is reported quickly.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          _ActionCard(
            icon: Icons.call,
            color: AppColors.danger,
            title: 'Call 1930',
            subtitle:
                'National cyber-crime helpline for financial fraud. Free, 24 hours.',
            onTap: () => _open(Uri(scheme: 'tel', path: '1930')),
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.public,
            color: AppColors.primary,
            title: 'Open cybercrime.gov.in',
            subtitle:
                'File the complaint online on the National Cyber Crime Reporting Portal.',
            onTap: () => _open(Uri.parse('https://cybercrime.gov.in')),
          ),
          const SizedBox(height: 24),
          const Text(
            'WHAT TO DO, IN ORDER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          const _Step(
            1,
            'Call 1930 right away if you sent money. Give the transaction ID, amount and the account or UPI ID it went to.',
          ),
          const _Step(
            2,
            'Call your bank or UPI app support and ask them to block or hold the transaction. Block the card or UPI ID if you shared details.',
          ),
          const _Step(
            3,
            'Do not delete the message, call log or screenshots. Do not reply to the scammer again.',
          ),
          const _Step(
            4,
            'Change the passwords and PINs of anything you shared or reused, starting with banking and email.',
          ),
          const _Step(
            5,
            'File the complaint at cybercrime.gov.in and attach the evidence PDF below.',
          ),
          const SizedBox(height: 24),
          const Text(
            'EVIDENCE PDF FROM A SCAN',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'The message word for word, when it arrived, the links, phone '
            'numbers and UPI IDs in it, and a filing checklist, ready to attach '
            'to your complaint.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No flagged scans yet. Scan the message first, then come back '
                'here to turn it into evidence.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else
            for (var i = 0; i < records.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            records[i].inputText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, height: 1.35),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${records[i].classification.toUpperCase()} · ${records[i].timestamp.day}/${records[i].timestamp.month}/${records[i].timestamp.year}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _exporting == i
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton.icon(
                            onPressed: _exporting != null
                                ? null
                                : () => _export(records[i], i),
                            icon: const Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 18,
                            ),
                            label: const Text('PDF'),
                          ),
                  ],
                ),
              ),
          const SizedBox(height: 16),
          const Text(
            'ScamShield cannot file the complaint for you. The portal has no '
            'public filing service, so this prepares the evidence and opens the '
            'right places.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String text;

  const _Step(this.number, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: AppColors.surfaceLight,
            child: Text(
              '$number',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
