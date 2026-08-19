import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/scanner_service.dart';
import '../services/report_generator_service.dart';
import '../data/repositories/scan_repository.dart';
import '../data/models/scan_record.dart';
import '../theme.dart';
import '../widgets/scamshield_hero_visual.dart';
import '../widgets/security_score.dart';
import '../widgets/premium_cta.dart';
import '../widgets/motion.dart';

class ApkScanScreen extends StatefulWidget {
  const ApkScanScreen({super.key});

  @override
  State<ApkScanScreen> createState() => _ApkScanScreenState();
}

class _ApkScanScreenState extends State<ApkScanScreen> {
  final ScannerService _scannerService = ScannerService();
  bool _isScanning = false;
  String? _fileName;
  int _fileSizeBytes = 0;
  Map<String, dynamic>? _report;
  String? _error;
  int _scanId = 0; // stale-result guard

  static const List<String> _scanStages = [
    'Validating APK archive structure',
    'Running static security analysis (Bytecode & Manifest)',
    'Synthesizing threat intelligence report',
  ];
  int _currentStageIndex = 0;

  Future<void> _pickAndScanApk() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        final thisScanId = ++_scanId;
        final file = result.files.single;

        setState(() {
          _fileName = file.name;
          _fileSizeBytes = file.size;
          _isScanning = true;
          _error = null;
          _report = null;
          _currentStageIndex = 0;
        });

        setState(() => _currentStageIndex = 1);
        final report = await _scannerService.scanApk(file);

        if (thisScanId != _scanId) return;

        try {
          final risk = report['risk'] ?? {};
          final riskScore = (risk['score'] as int?) ?? 0;
          final classification = riskScore >= 50
              ? 'scam'
              : riskScore >= 25
                  ? 'suspicious'
                  : 'safe';
          final summary =
              report['ai_explanation'] ?? 'APK static analysis completed.';

          await ScanRepository().saveScan(ScanRecord(
            inputText: 'APK: ${_fileName ?? "application.apk"}',
            classification: classification,
            riskScore: riskScore,
            summary: summary,
            timestamp: DateTime.now(),
            source: 'APK Scan',
          ));
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

  // ── Progress Steps Widget ──────────────────────────────────────────────────
  Widget _buildProgressSteps() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cobalt.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.cobalt,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'Static Analysis Pipeline',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.cobalt,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...List.generate(_scanStages.length, (index) {
            final isCompleted = index < _currentStageIndex;
            final isCurrent = index == _currentStageIndex;

            Color iconColor = AppColors.mutedText;
            IconData icon = Icons.radio_button_unchecked_rounded;

            if (isCompleted) {
              iconColor = AppColors.safeEmerald;
              icon = Icons.check_circle_rounded;
            } else if (isCurrent) {
              iconColor = AppColors.cobalt;
              icon = Icons.sync_rounded;
            }

            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isCurrent
                    ? AppColors.cobalt.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isCurrent
                      ? AppColors.cobalt.withValues(alpha: 0.4)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, color: iconColor, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _scanStages[index],
                      style: GoogleFonts.plusJakartaSans(
                        color: isCompleted
                            ? AppColors.textPrimary
                            : (isCurrent
                                ? AppColors.electricBlue
                                : AppColors.mutedText),
                        fontWeight: isCurrent || isCompleted
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_report != null && !_isScanning) {
      final risk = _report!['risk'] as Map<String, dynamic>? ?? {};
      final score = risk['score'] as int? ?? 0;
      final isDangerous = score >= 40;

      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAppBar(),
            const SizedBox(height: 16),
            _buildReportView(_report!, isDangerous, score),
            const SizedBox(height: 90),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAppBar(),
          const SizedBox(height: 20),

          // Editorial Headline
          Reveal(
            delay: Reveal.step(0),
            child: Text(
              "SCAN\nBEFORE\nYOU INSTALL.",
              style: GoogleFonts.plusJakartaSans(
                fontSize: AppFontSizes.heroHeadline,
                fontWeight: FontWeight.w900,
                height: 1.02,
                letterSpacing: -1.0,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Reveal(
            delay: Reveal.step(1),
            child: Text(
              "Deep static analysis for permissions, secrets, YARA signatures & threat metrics.",
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Hero Visual
          Reveal(
            delay: Reveal.step(2),
            child: Center(
              child: ScamShieldHeroVisual(
                size: 220,
                isThreat: false,
                isSafe: true,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Upload / File Selection Card
          Reveal(
            delay: Reveal.step(3),
            child: _buildPickerCard(),
          ),
          const SizedBox(height: 20),

          if (_isScanning)
            Reveal(
              child: _buildProgressSteps(),
            ),

          if (_error != null && !_isScanning)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.danger),
              ),
              child: Text(
                'Error: $_error',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 90),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.cobalt.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.android_rounded, color: AppColors.cobalt, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              'APK Security Scanner',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        if (_report != null)
          GestureDetector(
            onTap: () {
              setState(() {
                _report = null;
                _fileName = null;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                'NEW SCAN',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.cobalt,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPickerCard() {
    final sizeMb = (_fileSizeBytes / 1024 / 1024).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(
            _fileName != null ? Icons.insert_drive_file_rounded : Icons.cloud_upload_rounded,
            color: AppColors.cobalt,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            _fileName ?? 'Select Android APK Binary',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _fileName != null
                ? '$sizeMb MB • READY TO SCAN'
                : 'Extract permissions, YARA signatures & threat metrics',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              color: _fileName != null ? AppColors.safeEmerald : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: _fileName != null ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          PremiumCTA(
            label: _fileName != null ? "START SECURITY SCAN →" : "CHOOSE APK FILE",
            icon: Icons.file_open_rounded,
            onPressed: _isScanning ? null : _pickAndScanApk,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REPORT VIEW — renders all sections with dynamic safe vs dangerous theme
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildReportView(Map<String, dynamic> report, bool isDangerous, int score) {
    final risk = report['risk'] as Map<String, dynamic>? ?? {};
    final level = risk['level'] as String? ?? 'UNKNOWN';
    final riskDetails =
        (risk['details'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final riskBreakdown =
        (risk['breakdown'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    final androguard = report['androguard'] as Map<String, dynamic>? ?? {};
    final permissions = (androguard['permissions'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final dangerousPermissions = (androguard['dangerous_permissions'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toSet() ??
        {};
    final packageName = androguard['package_name'] as String? ?? 'Unknown';
    final androguardStatus = androguard['status'] as String? ?? 'unavailable';
    final certificates = (androguard['certificates'] as List<dynamic>?) ?? [];

    final secrets = report['secrets'] as Map<String, dynamic>? ?? {};
    final secretsFindings = secrets['findings'] as Map<String, dynamic>? ?? {};
    final urls = (secrets['urls'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final suspiciousUrls = (secrets['suspicious_urls'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final yara = report['yara'] as Map<String, dynamic>? ?? {};
    final yaraMatches =
        (yara['matches'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

    final osint = report['osint'] as Map<String, dynamic>? ?? {};
    final vt = osint['virustotal'] as Map<String, dynamic>? ?? {};
    final sb = osint['safe_browsing'] as Map<String, dynamic>? ?? {};
    final sbResults = (sb['results'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    final fileInfo = report['file_info'] as Map<String, dynamic>? ?? {};
    final dexFingerprint = (fileInfo['dex_fingerprint'] as String?) ?? (androguard['dex_structural_fingerprint'] as String?);
    final dexMinHash = fileInfo['dex_minhash'] as String?;
    final certReputation = androguard['certificate_reputation'] as String?;
    final dangerousApis = (androguard['dangerous_apis'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final scanMode = report['scan_mode'] as String? ?? 'local';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: ScamShieldHeroVisual(
            size: 200,
            isThreat: isDangerous,
            isSafe: !isDangerous,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: SecurityScore(
            score: score,
            statusLabel: isDangerous ? "DANGEROUS" : "LOW RISK",
          ),
        ),
        const SizedBox(height: 20),

        Center(
          child: Text(
            isDangerous
                ? "This APK shows signs of malicious behavior."
                : "This APK looks safe.",
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDangerous ? AppColors.danger : AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── 1. SECURITY VERDICT ────────────────────────────────────────────
        _buildVerdictCard(level, score, isDangerous ? AppColors.danger : AppColors.safeEmerald, riskDetails, scanMode),
        const SizedBox(height: 20),

        // ── 2. SECURITY FINDINGS ──────────────────────────────────────────
        if (riskDetails.isNotEmpty) ...[
          _buildSectionHeader('SECURITY FINDINGS', Icons.security),
          const SizedBox(height: 8),
          ...riskDetails.map((finding) => _buildFindingCard(finding, isDangerous ? AppColors.danger : AppColors.safeEmerald)),
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

        // ── 5. YARA SIGNATURES ────────────────────────────────────────────
        _buildSectionHeader('YARA SIGNATURES', Icons.pest_control),
        const SizedBox(height: 8),
        _buildYaraCard(yaraMatches),
        const SizedBox(height: 20),

        // ── 6. ANDROID ANALYSIS ───────────────────────────────────────────
        _buildSectionHeader('ANDROID ANALYSIS', Icons.android),
        const SizedBox(height: 8),
        _buildAndroidCard(
            packageName, androguardStatus, permissions, dangerousPermissions, certificates, certReputation, dangerousApis),
        const SizedBox(height: 20),

        // ── 7. SECRETS & SUSPICIOUS STRINGS ──────────────────────────────
        if (secretsFindings.isNotEmpty || suspiciousUrls.isNotEmpty) ...[
          _buildSectionHeader('SECRETS & SUSPICIOUS STRINGS', Icons.vpn_key),
          const SizedBox(height: 8),
          _buildSecretsCard(secretsFindings, suspiciousUrls, urls),
          const SizedBox(height: 20),
        ],

        // ── 8. FILE HASHES & METADATA ─────────────────────────────────────
        _buildSectionHeader('FILE HASHES & METADATA', Icons.fingerprint),
        const SizedBox(height: 8),
        _buildInfoCard([
          _buildHashRow('MD5', fileInfo['md5']?.toString() ?? 'N/A'),
          _buildHashRow('SHA-1', fileInfo['sha1']?.toString() ?? 'N/A'),
          _buildHashRow('SHA-256', fileInfo['sha256']?.toString() ?? 'N/A'),
          if (dexFingerprint != null && dexFingerprint.isNotEmpty)
            _buildHashRow('DEX Fingerprint', dexFingerprint),
          if (dexMinHash != null && dexMinHash.isNotEmpty)
            _buildHashRow('DEX MinHash', dexMinHash),
          _buildInfoRow('Size',
              '${((fileInfo['size'] as num? ?? 0) / 1024 / 1024).toStringAsFixed(2)} MB'),
        ]),
        const SizedBox(height: 20),

        // ── 9. RISK SCORE BREAKDOWN ───────────────────────────────────────
        if (riskBreakdown.isNotEmpty) ...[
          _buildSectionHeader('RISK SCORE BREAKDOWN', Icons.bar_chart),
          const SizedBox(height: 8),
          _buildBreakdownCard(riskBreakdown, score),
          const SizedBox(height: 20),
        ],

        // Export PDF Action
        PremiumCTA(
          label: "EXPORT SECURITY AUDIT PDF",
          icon: Icons.picture_as_pdf_rounded,
          onPressed: () async {
            try {
              final pdfPath = await ReportGeneratorService.generatePdf(
                  report,
                  fileName: _fileName ?? 'scan.apk');
              await OpenFilex.open(pdfPath);
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Export failed: $e')));
              }
            }
          },
        ),
      ],
    );
  }

  // ── Section Builders ───────────────────────────────────────────────────────

  Widget _buildVerdictCard(String level, int score, Color levelColor,
      List<String> riskDetails, String scanMode) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: levelColor.withValues(alpha: 0.6), width: 1.5),
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
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: levelColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Score: $score / 100',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Icon(
                level == 'LOW'
                    ? Icons.verified_user_rounded
                    : Icons.dangerous_rounded,
                color: levelColor,
                size: 36,
              ),
            ],
          ),
          if (riskDetails.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: AppColors.border),
            const SizedBox(height: 8),
            ...riskDetails.take(3).map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(color: AppColors.mutedText)),
                      Expanded(
                        child: Text(
                          d,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
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
        borderRadius: BorderRadius.circular(16),
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
              style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.4),
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

    Color statusColor = AppColors.safeEmerald;
    String statusText = 'No Detections';
    IconData statusIcon = Icons.check_circle_outline_rounded;

    if (!checked) {
      statusColor = AppColors.mutedText;
      statusText = 'Cloud Check Not Run';
      statusIcon = Icons.cloud_off_rounded;
    } else if (malicious > 0) {
      statusColor = AppColors.danger;
      statusText = 'MALICIOUS DETECTED';
      statusIcon = Icons.dangerous_rounded;
    }

    return _buildInfoCard([
      Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: GoogleFonts.plusJakartaSans(
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
      Map<String, dynamic> sb, List<Map<String, dynamic>> results) {
    final checked = sb['checked'] as bool? ?? false;

    if (!checked) {
      final note = sb['note'] as String?;
      return _buildInfoCard([
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.mutedText, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                note ?? 'No URLs were extracted from this APK to check.',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textSecondary,
                  fontSize: 13,
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
            flagged.isNotEmpty ? Icons.dangerous_rounded : Icons.check_circle_outline_rounded,
            color: flagged.isNotEmpty ? AppColors.danger : AppColors.safeEmerald,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            flagged.isNotEmpty
                ? '${flagged.length} URL(s) flagged as dangerous'
                : 'All checked URLs clean',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.bold,
              color: flagged.isNotEmpty ? AppColors.danger : AppColors.safeEmerald,
              fontSize: 14,
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _buildYaraCard(List<String> matches) {
    if (matches.isEmpty) {
      return _buildInfoCard([
        Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                color: AppColors.safeEmerald, size: 18),
            const SizedBox(width: 8),
            Text(
              'No configured YARA signatures matched.',
              style: GoogleFonts.plusJakartaSans(color: AppColors.safeEmerald, fontSize: 13),
            ),
          ],
        ),
      ]);
    }

    return _buildInfoCard([
      Row(
        children: [
          const Icon(Icons.dangerous_rounded, color: AppColors.danger, size: 18),
          const SizedBox(width: 8),
          Text(
            '${matches.length} rule(s) matched',
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.danger,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ...matches.map((m) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
            ),
            child: Text(
              m,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.bold,
                color: AppColors.danger,
                fontSize: 13,
              ),
            ),
          )),
    ]);
  }

  Widget _buildAndroidCard(
      String packageName,
      String status,
      List<String> permissions,
      Set<String> dangerousPerms,
      List<dynamic> certificates,
      [String? certReputation,
      List<String>? dangerousApis]) {
    final isStatusOk = status == 'success';

    return _buildInfoCard([
      _buildInfoRow('Package', packageName),
      _buildInfoRow('Androguard', isStatusOk ? '✓ Analysis complete' : '⚠ $status'),
      _buildInfoRow(
          'Permissions', '${permissions.length} total, ${dangerousPerms.length} dangerous'),
    ]);
  }

  Widget _buildSecretsCard(Map<String, dynamic> findings,
      List<String> suspiciousUrls, List<String> allUrls) {
    return _buildInfoCard([
      if (findings.isNotEmpty) ...[
        Row(
          children: [
            const Icon(Icons.vpn_key_rounded, color: AppColors.danger, size: 18),
            const SizedBox(width: 8),
            Text(
              '${findings.length} secret type(s) found',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.bold,
                color: AppColors.danger,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ],
    ]);
  }

  Widget _buildBreakdownCard(List<Map<String, dynamic>> breakdown, int total) {
    return _buildInfoCard([
      ...breakdown.map((item) {
        final pts = item['points'] as int? ?? 0;
        final factor = item['factor'] as String? ?? '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  factor,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textPrimary),
                ),
              ),
              Text(
                '+$pts pts',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  color: AppColors.cobalt,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      }),
    ]);
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.cobalt, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.mutedText,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
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
            width: 90,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textPrimary),
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
            width: 70,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
