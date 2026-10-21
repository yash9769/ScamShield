import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../services/scanner_service.dart';
import '../services/report_generator_service.dart';
import '../data/repositories/scan_repository.dart';
import '../data/models/scan_record.dart';
import '../theme.dart';
import '../widgets/animated_radar.dart';

class ApkScanScreen extends StatefulWidget {
  const ApkScanScreen({super.key});

  @override
  State<ApkScanScreen> createState() => _ApkScanScreenState();
}

class _ApkScanScreenState extends State<ApkScanScreen> {
  final ScannerService _scannerService = ScannerService();
  bool _isScanning = false;
  String? _fileName;
  Map<String, dynamic>? _report;
  String? _error;
  int _scanId = 0; // stale-result guard

  static const List<String> _scanStages = [
    'Uploading & validating APK binary',
    'Running static analysis (Androguard + YARA)',
    'Synthesizing threat intelligence report',
  ];
  int _currentStageIndex = 0;

  Future<void> _pickAndScanApk() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        // Capture this scan's ID before going async — prevents stale overwrites
        final thisScanId = ++_scanId;

        setState(() {
          _fileName = result.files.single.name;
          _isScanning = true;
          _error = null;
          _report = null;
          _currentStageIndex = 0;
        });

        setState(() => _currentStageIndex = 1);
        final report = await _scannerService.scanApk(result.files.single);

        // Discard result if a newer scan was started while this one was in flight
        if (thisScanId != _scanId) return;

        // Save scan result to SQLite database to increment user stats
        try {
          final risk = report['risk'] ?? {};
          final riskScore = (risk['score'] as int?) ?? 0;
          // Derive classification from the same 'level' the report displays,
          // so the saved history record can never disagree with the on-screen verdict.
          final level = (risk['level'] as String?) ?? 'LOW';
          final classification = (level == 'CRITICAL' || level == 'HIGH')
              ? 'scam'
              : level == 'MEDIUM'
              ? 'suspicious'
              : 'safe';
          final summary =
              report['ai_explanation'] ?? 'APK static analysis completed.';

          await ScanRepository().saveScan(
            ScanRecord(
              inputText: 'APK: ${_fileName ?? "application.apk"}',
              classification: classification,
              riskScore: riskScore,
              summary: summary,
              timestamp: DateTime.now(),
              source: 'APK Scan',
            ),
          );
        } catch (_) {}

        if (mounted && thisScanId == _scanId) {
          setState(() {
            _currentStageIndex = 2;
            _report = report;
            _isScanning = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Scan failed: $e';
          _isScanning = false;
        });
      }
    }
  }

  // ── Immersive APK Scanning Experience ──────────────────────────────────────
  Widget _buildImmersiveApkScanningScreen() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Large animated radar as the focal point for APK scanning
          const Center(child: AnimatedRadar(size: 320, isScanning: true)),
          const SizedBox(height: AppSpacing.xxxl),
          // Scan status text
          Text(
            'APK Security Analysis',
            style: AppText.heading.copyWith(color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          // Current scanning stage
          Text(
            _scanStages[_currentStageIndex],
            style: AppText.body.copyWith(color: AppColors.primary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          // Progress indicator with all stages
          Container(
            width: 280,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1),
            ),
            child: Column(
              children: List.generate(_scanStages.length, (index) {
                final isCompleted = index < _currentStageIndex;
                final isCurrent = index == _currentStageIndex;

                Color iconColor = AppColors.textSecondary.withValues(alpha: 0.5);
                IconData icon = Icons.radio_button_unchecked;

                if (isCompleted) {
                  iconColor = AppColors.success;
                  icon = Icons.check_circle;
                } else if (isCurrent) {
                  iconColor = AppColors.primary;
                  icon = Icons.sync;
                }

                return Padding(
                  padding: EdgeInsets.only(bottom: index == _scanStages.length - 1 ? 0 : AppSpacing.md),
                  child: Row(
                    children: [
                      Icon(icon, color: iconColor, size: 18),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _scanStages[index],
                          style: TextStyle(
                            color: isCompleted
                                ? Colors.white
                                : (isCurrent ? AppColors.primary : AppColors.textSecondary),
                            fontWeight: isCurrent || isCompleted ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          // Progress bar showing overall completion
          SizedBox(
            width: 250,
            child: Column(
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: (_currentStageIndex + 1) / _scanStages.length,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.protectionGradient,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${((_currentStageIndex + 1) / _scanStages.length * 100).round()}% complete',
                  style: AppText.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          // Cancel button
          TextButton.icon(
            onPressed: () {
              setState(() {
                _isScanning = false;
                _error = 'Scan cancelled by user';
              });
            },
            icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 18),
            label: Text(
              'Cancel scan',
              style: AppText.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.android,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'APK Security Scanner',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
      ),
      body: Padding(padding: const EdgeInsets.all(16.0), child: _buildBody()),
    );
  }

  /// Premium APK scan results screen with clear risk assessment
  Widget _buildPremiumApkResults() {
    final risk = _report!['risk'] ?? {};
    final riskScore = (risk['score'] as int?) ?? 0;
    final level = (risk['level'] as String?) ?? 'LOW';
    final isSafe = level == 'LOW';
    final isWarning = level == 'MEDIUM';
    final isDangerous = level == 'HIGH' || level == 'CRITICAL';

    // Calculate status colors
    final statusColor = isSafe ? AppColors.accent : (isWarning ? AppColors.warning : AppColors.danger);
    final statusGradient = isSafe ? AppColors.protectionGradient : LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isWarning 
          ? [AppColors.warning, AppColors.warning.withValues(alpha: 0.7)]
          : (isDangerous ? [AppColors.danger, AppColors.danger.withValues(alpha: 0.7)] : [AppColors.danger, AppColors.danger.withValues(alpha: 0.7)]),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Scanned file header
          _buildScannedFileHeader(),
          const SizedBox(height: AppSpacing.xl),
          // Premium risk assessment hero section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              children: [
                // Risk score circle
                Center(
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: statusGradient,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.4),
                          blurRadius: 25,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$riskScore',
                            style: const TextStyle(
                              fontSize: 52,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Text(
                            '/ 100',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                // Risk level verdict
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      level == 'LOW' ? 'Safe' : level == 'MEDIUM' ? 'Suspicious' : 'Dangerous',
                      style: AppText.heading.copyWith(color: statusColor),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // Main recommendation
                Text(
                  isSafe 
                      ? 'This APK appears to be safe for installation.'
                      : isWarning 
                          ? 'This APK has some suspicious characteristics - review carefully.'
                          : 'This APK contains dangerous malware - do not install it.',
                  style: AppText.body.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          // Detailed report
          _buildReportView(_report!),
        ],
      ),
    );
  }

  /// Chooses the layout based on state.
  Widget _buildBody() {
    if (_report != null && !_isScanning) {
      return _buildPremiumApkResults();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPickerCard(),
        const SizedBox(height: 20),
        if (_isScanning) Expanded(child: _buildImmersiveApkScanningScreen()),
        if (_error != null && !_isScanning)
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.danger),
                ),
                child: Text(
                  'Error: $_error',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Large upload card shown before/while scanning.
  Widget _buildPickerCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.surfaceLight.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_upload_outlined,
            color: AppColors.primary,
            size: 44,
          ),
          const SizedBox(height: 12),
          const Text(
            'Select Android APK Binary',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Extract permissions, secrets, YARA signatures & OSINT metrics',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isScanning ? null : _pickAndScanApk,
            icon: const Icon(Icons.file_open_outlined, color: Colors.black),
            label: Text(
              _fileName != null ? 'Select different APK' : 'Choose APK file',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact header shown above the report once a scan completes. Replaces the
  /// large upload card and keeps a "scan another" affordance without occupying
  /// the whole viewport.
  Widget _buildScannedFileHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.surfaceLight.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.insert_drive_file_outlined,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SCANNED FILE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fileName ?? 'application.apk',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _isScanning ? null : _pickAndScanApk,
            icon: const Icon(Icons.refresh, size: 16, color: AppColors.primary),
            label: const Text(
              'New scan',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REPORT VIEW — renders all 9 sections from the actual backend response
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildReportView(Map<String, dynamic> report) {
    final risk = report['risk'] as Map<String, dynamic>? ?? {};
    final level = risk['level'] as String? ?? 'UNKNOWN';
    final score = risk['score'] as int? ?? 0;
    final riskDetails =
        (risk['details'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final riskBreakdown =
        (risk['breakdown'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
        [];

    final androguard = report['androguard'] as Map<String, dynamic>? ?? {};
    final permissions =
        (androguard['permissions'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final dangerousPermissions =
        (androguard['dangerous_permissions'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toSet() ??
        {};
    final packageName = androguard['package_name'] as String? ?? 'Unknown';
    final androguardStatus = androguard['status'] as String? ?? 'unavailable';
    final certificates = (androguard['certificates'] as List<dynamic>?) ?? [];

    final secrets = report['secrets'] as Map<String, dynamic>? ?? {};
    final secretsFindings = secrets['findings'] as Map<String, dynamic>? ?? {};
    final urls =
        (secrets['urls'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final suspiciousUrls =
        (secrets['suspicious_urls'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final yara = report['yara'] as Map<String, dynamic>? ?? {};
    final yaraMatches =
        (yara['matches'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final osint = report['osint'] as Map<String, dynamic>? ?? {};
    final vt = osint['virustotal'] as Map<String, dynamic>? ?? {};
    final sb = osint['safe_browsing'] as Map<String, dynamic>? ?? {};
    final sbResults =
        (sb['results'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    final fileInfo = report['file_info'] as Map<String, dynamic>? ?? {};
    final scanMode = report['scan_mode'] as String? ?? 'local';

    Color levelColor = AppColors.success;
    if (level == 'HIGH' || level == 'CRITICAL') {
      levelColor = AppColors.danger;
    } else if (level == 'MEDIUM') {
      levelColor = AppColors.warning;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. SECURITY VERDICT ────────────────────────────────────────────
        _buildVerdictCard(level, score, levelColor, riskDetails, scanMode),
        const SizedBox(height: 20),

        // ── 2. SECURITY FINDINGS ──────────────────────────────────────────
        if (riskDetails.isNotEmpty) ...[
          _buildSectionHeader('SECURITY FINDINGS', Icons.security),
          const SizedBox(height: 8),
          ...riskDetails.map(
            (finding) => _buildFindingCard(finding, levelColor),
          ),
          const SizedBox(height: 20),
        ],

        // ── 3. VIRUSTOTAL ─────────────────────────────────────────────────
        _buildSectionHeader('VIRUSTOTAL', Icons.biotech),
        const SizedBox(height: 8),
        _buildVirusTotalCard(vt),
        const SizedBox(height: 20),

        // ── 4. GOOGLE SAFE BROWSING ───────────────────────────────────────
        _buildSectionHeader('GOOGLE SAFE BROWSING', Icons.shield_outlined),
        const SizedBox(height: 8),
        _buildSafeBrowsingCard(sb, sbResults),
        const SizedBox(height: 20),

        // ── 5. Yara signatures ────────────────────────────────────────────
        _buildSectionHeader('Yara signatures', Icons.pest_control),
        const SizedBox(height: 8),
        _buildYaraCard(yaraMatches),
        const SizedBox(height: 20),

        // ── 6. Android analysis ───────────────────────────────────────────
        _buildSectionHeader('Android analysis', Icons.android),
        const SizedBox(height: 8),
        _buildAndroidCard(
          packageName,
          androguardStatus,
          permissions,
          dangerousPermissions,
          certificates,
        ),
        const SizedBox(height: 20),

        // ── 7. Secrets & suspicious strings ──────────────────────────────
        if (secretsFindings.isNotEmpty || suspiciousUrls.isNotEmpty) ...[
          _buildSectionHeader('Secrets & suspicious strings', Icons.vpn_key),
          const SizedBox(height: 8),
          _buildSecretsCard(secretsFindings, suspiciousUrls, urls),
          const SizedBox(height: 20),
        ],

        // ── 8. File hashes & metadata ─────────────────────────────────────
        _buildSectionHeader('File hashes & metadata', Icons.fingerprint),
        const SizedBox(height: 8),
        _buildInfoCard([
          _buildHashRow('MD5', fileInfo['md5']?.toString() ?? 'N/A'),
          _buildHashRow('SHA-1', fileInfo['sha1']?.toString() ?? 'N/A'),
          _buildHashRow('SHA-256', fileInfo['sha256']?.toString() ?? 'N/A'),
          _buildInfoRow(
            'Size',
            '${((fileInfo['size'] as num? ?? 0) / 1024 / 1024).toStringAsFixed(2)} MB',
          ),
        ]),
        const SizedBox(height: 20),

        // ── 9. RISK SCORE BREAKDOWN ───────────────────────────────────────
        if (riskBreakdown.isNotEmpty) ...[
          _buildSectionHeader('RISK SCORE BREAKDOWN', Icons.bar_chart),
          const SizedBox(height: 8),
          _buildBreakdownCard(riskBreakdown, score),
          const SizedBox(height: 20),
        ],

        // ── Export PDF ────────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: () async {
              try {
                final pdfPath = await ReportGeneratorService.generatePdf(
                  report,
                  fileName: _fileName ?? 'scan.apk',
                );
                await OpenFilex.open(pdfPath);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
                }
              }
            },
            icon: const Icon(Icons.picture_as_pdf, color: Colors.black),
            label: const Text(
              'EXPORT SECURITY AUDIT PDF',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Section Builders ───────────────────────────────────────────────────────

  Widget _buildVerdictCard(
    String level,
    int score,
    Color levelColor,
    List<String> riskDetails,
    String scanMode,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: levelColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: levelColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RISK LEVEL: $level',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: levelColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Score: $score / 100',
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Icon(
                level == 'LOW'
                    ? Icons.verified_user
                    : level == 'MEDIUM'
                    ? Icons.warning_amber_rounded
                    : Icons.dangerous_outlined,
                color: levelColor,
                size: 48,
              ),
            ],
          ),
          if (riskDetails.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),
            const Text(
              'Why this score?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            ...riskDetails
                .take(3)
                .map(
                  (d) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '• ',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        Expanded(
                          child: Text(
                            d,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              scanMode == 'server'
                  ? '🛡 Full Server Analysis'
                  : '📱 On-Device Analysis',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFindingCard(String finding, Color levelColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: levelColor, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: levelColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              finding,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVirusTotalCard(Map<String, dynamic> vt) {
    final checked = vt['checked'] as bool? ?? false;
    final malicious = vt['malicious'] as int? ?? 0;
    final suspicious = vt['suspicious'] as int? ?? 0;
    final note = vt['note'] as String? ?? 'No data available.';

    Color statusColor = AppColors.success;
    String statusText = 'No Detections';
    IconData statusIcon = Icons.check_circle_outline;

    if (!checked) {
      statusColor = AppColors.textSecondary;
      statusText = 'Cloud Check Not Run';
      statusIcon = Icons.cloud_off_outlined;
    } else if (malicious > 0) {
      statusColor = AppColors.danger;
      statusText = 'MALICIOUS DETECTED';
      statusIcon = Icons.dangerous_outlined;
    } else if (suspicious > 0) {
      statusColor = AppColors.warning;
      statusText = 'Suspicious';
      statusIcon = Icons.warning_amber_rounded;
    }

    return _buildInfoCard([
      Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: statusColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (checked) ...[
        _buildInfoRow('Malicious', '$malicious engine(s)'),
        _buildInfoRow('Suspicious', '$suspicious engine(s)'),
      ],
      _buildInfoRow('Status', note),
    ]);
  }

  Widget _buildSafeBrowsingCard(
    Map<String, dynamic> sb,
    List<Map<String, dynamic>> results,
  ) {
    final checked = sb['checked'] as bool? ?? false;

    if (!checked) {
      final note = sb['note'] as String?;
      final urlsFound = sb['urls_found'] as int? ?? results.length;
      return _buildInfoCard([
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: AppColors.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                note ??
                    (urlsFound == 0
                        ? 'No URLs were extracted from this APK, so there was nothing to check.'
                        : '$urlsFound URL(s) extracted. Reconnect to the ScamShield backend to screen them live.'),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ]);
    }

    final flagged = results.where((r) => r['malicious'] == true).toList();

    return _buildInfoCard([
      Row(
        children: [
          Icon(
            flagged.isNotEmpty
                ? Icons.dangerous_outlined
                : Icons.check_circle_outline,
            color: flagged.isNotEmpty ? AppColors.danger : AppColors.success,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            flagged.isNotEmpty
                ? '${flagged.length} URL(s) flagged as dangerous'
                : 'All ${results.length} checked URL(s) clean',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: flagged.isNotEmpty ? AppColors.danger : AppColors.success,
              fontSize: 14,
            ),
          ),
        ],
      ),
      if (flagged.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text(
          'Flagged URLs:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: AppColors.danger,
          ),
        ),
        const SizedBox(height: 4),
        ...flagged
            .take(5)
            .map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SelectableText(
                  r['url']?.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.danger,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
      ],
      if (results.isEmpty)
        const Text(
          'No URLs found in APK to check.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
    ]);
  }

  Widget _buildYaraCard(List<String> matches) {
    if (matches.isEmpty) {
      return _buildInfoCard([
        const Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: AppColors.success,
              size: 18,
            ),
            SizedBox(width: 8),
            Text(
              'No configured YARA signatures matched.',
              style: TextStyle(color: AppColors.success, fontSize: 13),
            ),
          ],
        ),
      ]);
    }

    return _buildInfoCard([
      Row(
        children: [
          const Icon(
            Icons.dangerous_outlined,
            color: AppColors.danger,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            '${matches.length} rule(s) matched — HIGH RISK',
            style: const TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ...matches.map(
        (m) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
          ),
          child: Text(
            m,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.danger,
              fontSize: 13,
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildAndroidCard(
    String packageName,
    String status,
    List<String> permissions,
    Set<String> dangerousPerms,
    List<dynamic> certificates,
  ) {
    final isStatusOk = status == 'success';

    return _buildInfoCard([
      _buildInfoRow('Package', packageName),
      _buildInfoRow(
        'Androguard',
        isStatusOk ? '✓ Analysis complete' : '⚠ $status',
      ),
      _buildInfoRow(
        'Permissions',
        '${permissions.length} total, ${dangerousPerms.length} dangerous',
      ),
      if (certificates.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text(
          'Certificate(s):',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        ...(certificates.take(3)).map((cert) {
          final c = cert as Map<String, dynamic>? ?? {};
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c['subject'] != null)
                  Text(
                    'Subject: ${c['subject']}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textPrimary,
                    ),
                  ),
                if (c['issuer'] != null)
                  Text(
                    'Issuer: ${c['issuer']}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (c['sha256'] != null)
                  SelectableText(
                    'SHA-256: ${c['sha256']}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontFamily: 'monospace',
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          );
        }),
      ] else ...[
        const SizedBox(height: 4),
        const Text(
          'No certificate data extracted.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
      if (permissions.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text(
          'Permissions:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: permissions.take(30).map((p) {
            final shortP = p
                .replaceAll('android.permission.', '')
                .replaceAll('android.', '');
            final isDangerous = dangerousPerms.any(
              (d) => p.toUpperCase().contains(d),
            );
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDangerous
                    ? AppColors.danger.withValues(alpha: 0.15)
                    : AppColors.surfaceLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDangerous
                      ? AppColors.danger.withValues(alpha: 0.5)
                      : Colors.transparent,
                ),
              ),
              child: Text(
                shortP,
                style: TextStyle(
                  fontSize: 10,
                  color: isDangerous ? AppColors.danger : AppColors.textPrimary,
                  fontWeight: isDangerous ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          }).toList(),
        ),
        if (permissions.length > 30)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '+${permissions.length - 30} more permissions',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
      ],
    ]);
  }

  Widget _buildSecretsCard(
    Map<String, dynamic> findings,
    List<String> suspiciousUrls,
    List<String> allUrls,
  ) {
    return _buildInfoCard([
      if (findings.isNotEmpty) ...[
        Row(
          children: [
            const Icon(Icons.vpn_key, color: AppColors.danger, size: 18),
            const SizedBox(width: 8),
            Text(
              '${findings.length} secret type(s) found',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.danger,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...findings.entries.map(
          (e) => _buildInfoRow(e.key, '${e.value} occurrence(s)'),
        ),
      ],
      if (suspiciousUrls.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          '${suspiciousUrls.length} suspicious URL(s):',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.warning,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        ...suspiciousUrls
            .take(5)
            .map(
              (u) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SelectableText(
                  u,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.warning,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
      ],
      if (allUrls.isNotEmpty && suspiciousUrls.isEmpty)
        _buildInfoRow(
          'URLs extracted',
          '${allUrls.length} (none flagged suspicious)',
        ),
    ]);
  }

  Widget _buildBreakdownCard(List<Map<String, dynamic>> breakdown, int total) {
    return _buildInfoCard([
      ...breakdown.map((item) {
        final pts = item['points'] as int? ?? 0;
        final factor = item['factor'] as String? ?? '';
        final pct = total > 0 ? pts / total : 0.0;

        Color barColor = AppColors.success;
        final cat = item['category'] as String? ?? '';
        if (cat == 'yara' || cat == 'virustotal' || pts >= 30) {
          barColor = AppColors.danger;
        } else if (pts >= 15) {
          barColor = AppColors.warning;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      factor,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '+$pts pts',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: barColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct.clamp(0.0, 1.0),
                  color: barColor,
                  backgroundColor: barColor.withValues(alpha: 0.15),
                  minHeight: 5,
                ),
              ),
            ],
          ),
        );
      }),
      const Divider(color: Colors.white24),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'TOTAL RISK SCORE',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Text(
            '$total / 100',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    ]);
  }

  // ── Helper Widgets ─────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 8),
        Text(title, style: AppText.label),
      ],
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.surfaceLight.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHashRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: value));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$label copied to clipboard')),
                  );
                }
              },
              child: SelectableText(
                value,
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}