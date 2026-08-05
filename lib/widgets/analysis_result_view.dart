// lib/widgets/analysis_result_view.dart
// Reusable rendering of an [AnalysisResult]: verdict card, detection
// breakdown and OSINT intelligence — shared by the image, voice and batch
// scan screens so every AI result looks and behaves identically.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/scam_detector.dart';

class AnalysisResultView extends StatelessWidget {
  final AnalysisResult result;
  final bool showHeader;

  const AnalysisResultView({
    super.key,
    required this.result,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          const SizedBox(height: 8),
          _buildHeader(),
        ],
        _buildResultCard(),
        if (result.reasons.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildReasonsSection(),
        ],
        if (result.osint != null && result.osint!.hasData) ...[
          const SizedBox(height: 20),
          OsintIntelligenceCard(osint: result.osint!),
        ],
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Analysis Result',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          result.aiPowered
              ? 'Powered by AI + heuristic engine'
              : 'Based on local pattern analysis',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildResultCard() {
    final (Color primaryColor, Color bgColor, IconData statusIcon,
        String statusLabel, String statusSubtitle) = switch (result.classification) {
      ScamClassification.scam => (
          AppColors.danger,
          AppColors.danger.withValues(alpha: 0.08),
          Icons.warning_rounded,
          'SCAM DETECTED',
          'High confidence threat identified'),
      ScamClassification.suspicious => (
          AppColors.warning,
          AppColors.warning.withValues(alpha: 0.08),
          Icons.help_outline_rounded,
          'SUSPICIOUS',
          'Multiple warning signals found'),
      ScamClassification.safe => (
          AppColors.success,
          AppColors.success.withValues(alpha: 0.08),
          Icons.check_circle_outline_rounded,
          'LOOKS SAFE',
          'No critical threats detected'),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(statusIcon, color: primaryColor, size: 18),
              const SizedBox(width: 6),
              Text(
                statusLabel,
                style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              if (result.confidence > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${result.confidence}% confidence',
                    style: TextStyle(color: primaryColor, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 110,
                height: 110,
                child: CircularProgressIndicator(
                  value: result.riskScore / 100,
                  strokeWidth: 9,
                  backgroundColor: primaryColor.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                children: [
                  Text(
                    '${result.riskScore}',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  const Text(
                    'RISK SCORE',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            statusSubtitle,
            style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            result.summary,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Detection Breakdown',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Why we flagged this content',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        ...result.reasons.map((r) => _buildReasonCard(r)),
      ],
    );
  }

  Widget _buildReasonCard(DetectionReason reason) {
    final (Color color, IconData icon) = _iconForCategory(reason.iconCategory);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  reason.label,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              if (reason.scoreContribution > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '+${reason.scoreContribution} pts',
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            reason.description,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  (Color, IconData) _iconForCategory(IconCategory category) {
    return switch (category) {
      IconCategory.financial => (AppColors.danger, Icons.account_balance_rounded),
      IconCategory.link => (AppColors.warning, Icons.link_rounded),
      IconCategory.urgency => (AppColors.warning, Icons.timer_rounded),
      IconCategory.suspicious => (AppColors.warning, Icons.search_rounded),
      IconCategory.manipulation => (AppColors.danger, Icons.psychology_rounded),
      IconCategory.safe => (AppColors.success, Icons.check_circle_rounded),
    };
  }
}

/// Displays OSINT enrichment (VirusTotal / Safe Browsing / WHOIS / score).
class OsintIntelligenceCard extends StatelessWidget {
  final OsintDetail osint;

  const OsintIntelligenceCard({super.key, required this.osint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.travel_explore, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Threat Intelligence (OSINT)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (osint.osintScore > 0) ...[
            Row(
              children: [
                const Text('OSINT Score', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: osint.osintScore / 100,
                      minHeight: 6,
                      backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        osint.osintScore >= 50 ? AppColors.danger : AppColors.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${osint.osintScore}/100',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (osint.virustotalChecked)
            _buildRow(
              icon: Icons.shield_outlined,
              label: 'VirusTotal',
              value: osint.maliciousUrls.isNotEmpty
                  ? '⚠ ${osint.maliciousUrls.length} malicious URL(s) found'
                  : 'No malicious detections',
              danger: osint.maliciousUrls.isNotEmpty,
            ),
          if (osint.maliciousUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...osint.maliciousUrls.map(
              (u) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $u',
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            ),
          ],
          if (osint.whoisDomainAgeDays != null)
            _buildRow(
              icon: Icons.calendar_today_outlined,
              label: 'Domain Age',
              value: osint.whoisDomainAgeDays! < 30
                  ? 'Only ${osint.whoisDomainAgeDays} days old (suspicious)'
                  : '${osint.whoisDomainAgeDays} days',
              danger: osint.whoisDomainAgeDays! < 30,
            ),
          if (osint.whoisRegistrar != null && osint.whoisRegistrar!.isNotEmpty)
            _buildRow(
              icon: Icons.business_outlined,
              label: 'Registrar',
              value: osint.whoisRegistrar!,
            ),
          if (osint.urlsFound.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('URLs found', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            ...osint.urlsFound.map(
              (u) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $u',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String label,
    required String value,
    bool danger = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: danger ? AppColors.danger : AppColors.textSecondary),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: danger ? AppColors.danger : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
