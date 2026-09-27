import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

import 'apk_analyzer_service.dart';
import 'osint_service.dart';
import 'scam_detector.dart';

/// Brand colors mirrored from lib/theme.dart's AppColors, so an exported PDF
/// looks like it came from the same product instead of a generic library
/// default. Kept as plain PdfColor (not Flutter's Color) since these render
/// server/client-side into a document, not a widget tree.
class _RC {
  _RC._();

  static const ink = PdfColor.fromInt(0xFF0F172A);
  static const cyan = PdfColor.fromInt(0xFF06B6D4);
  static const danger = PdfColor.fromInt(0xFFEF4444);
  static const dangerDark = PdfColor.fromInt(0xFF991B1B);
  static const dangerBg = PdfColor.fromInt(0xFFFEF2F2);
  static const success = PdfColor.fromInt(0xFF10B981);
  static const successDark = PdfColor.fromInt(0xFF065F46);
  static const successBg = PdfColor.fromInt(0xFFECFDF5);
  static const warning = PdfColor.fromInt(0xFFF59E0B);
  static const warningDark = PdfColor.fromInt(0xFF92400E);
  static const warningBg = PdfColor.fromInt(0xFFFFFBEB);
  static const textMuted = PdfColor.fromInt(0xFF64748B);
  static const textFaint = PdfColor.fromInt(0xFF94A3B8);
  static const border = PdfColor.fromInt(0xFFE2E8F0);
  static const chipBg = PdfColor.fromInt(0xFFF1F5F9);
  static const rowAlt = PdfColor.fromInt(0xFFF8FAFC);

  static bool _isHigh(String label) {
    final u = label.toUpperCase();
    return u == 'SCAM' || u == 'HIGH' || u == 'CRITICAL';
  }

  static bool _isMedium(String label) {
    final u = label.toUpperCase();
    return u == 'SUSPICIOUS' || u == 'MEDIUM';
  }

  /// The verdict color family is driven by the same label string the rest of
  /// the app already computed (classification name / risk level) — never
  /// re-derived from the numeric score here, so a report can't disagree with
  /// the verdict shown on-screen.
  static PdfColor forLabel(String label) =>
      _isHigh(label) ? danger : (_isMedium(label) ? warning : success);

  static PdfColor darkForLabel(String label) =>
      _isHigh(label) ? dangerDark : (_isMedium(label) ? warningDark : successDark);

  static PdfColor bgForLabel(String label) =>
      _isHigh(label) ? dangerBg : (_isMedium(label) ? warningBg : successBg);
}

/// A small label/value pair rendered as a table-like row.
class _KV {
  final String label;
  final String value;
  const _KV(this.label, this.value);
}

/// Fonts + logo loaded once per report generation call. Bundled as local
/// assets (assets/fonts/*.ttf, assets/icon.png) rather than fetched via
/// PdfGoogleFonts at runtime, so generating a report never depends on the
/// device having a network connection — this app is used precisely in
/// moments (a suspicious APK, no signal) where that can't be assumed.
class _ReportAssets {
  final pw.ThemeData theme;
  final pw.Font medium;
  final pw.Font semiBold;
  final pw.MemoryImage logo;

  _ReportAssets({
    required this.theme,
    required this.medium,
    required this.semiBold,
    required this.logo,
  });

  static Future<_ReportAssets> load() async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf'));
    final medium = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Medium.ttf'));
    final semiBold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));
    final logoBytes = await rootBundle.load('assets/icon.png');
    return _ReportAssets(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      medium: medium,
      semiBold: semiBold,
      logo: pw.MemoryImage(logoBytes.buffer.asUint8List()),
    );
  }
}

class ReportGeneratorService {
  /// Local Tier-1 APK scan report (on-device static engine only) — used by
  /// the Scan Now bottom sheet's "Export Full PDF Report" action.
  static Future<File> generateApkReport({
    required ApkAnalysisResult apk,
    required List<OsintResult> osintResults,
    required AnalysisResult analysis,
    required String fileName,
  }) async {
    final assets = await _ReportAssets.load();
    final label = analysis.classification.name.toUpperCase();
    final pdf = pw.Document(theme: assets.theme, title: 'ScamShield Report — $fileName');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 32),
        footer: (context) => _footer(context),
        build: (context) => [
          _brandHeader(
            assets: assets,
            title: 'APK Scan Report',
            target: fileName,
            engineLabel: 'On-Device Static Engine',
          ),
          pw.SizedBox(height: 22),
          _sectionLabel('EXECUTIVE VERDICT', assets),
          _verdictHero(label: label, score: analysis.riskScore, summary: analysis.summary),
          pw.SizedBox(height: 22),
          _sectionLabel('FILE HASHES', assets),
          _kvCard([
            _KV('MD5', apk.md5),
            _KV('SHA-1', apk.sha1),
            _KV('SHA-256', apk.sha256),
          ]),
          pw.SizedBox(height: 22),
          _sectionLabel('PACKAGE METADATA', assets),
          apk.metadata.isNotEmpty
              ? _kvCard(apk.metadata.entries.map((e) => _KV(e.key, e.value)).toList())
              : _emptyNote('No package metadata extracted (AXML parsing disabled or failed).'),
          if (apk.certificates.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _subLabel('Signer Certificates', assets),
            pw.SizedBox(height: 6),
            ...apk.certificates.take(5).map(_monoLine),
          ],
          if (apk.nativeLibraries.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _subLabel('Native Libraries', assets),
            pw.SizedBox(height: 6),
            pw.Text(apk.nativeLibraries.join(', '), style: const pw.TextStyle(fontSize: 9, color: _RC.textMuted)),
          ],
          pw.SizedBox(height: 22),
          _sectionLabel('REQUESTED PERMISSIONS (${apk.permissions.length})', assets),
          apk.permissions.isEmpty ? _emptyNote('No permissions declared.') : _chipWrap(apk.permissions),
          if (apk.secrets.isNotEmpty) ...[
            pw.SizedBox(height: 22),
            _sectionLabel('EXPOSED SECRETS (${apk.secrets.length})', assets, accent: _RC.danger),
            ...apk.secrets.map((s) => _findingCard(s, _RC.danger)),
          ],
          if (osintResults.isNotEmpty) ...[
            pw.SizedBox(height: 22),
            _sectionLabel('OSINT THREAT INTELLIGENCE', assets),
            ...osintResults.map(_osintRow),
          ],
          if (analysis.reasons.isNotEmpty) ...[
            pw.SizedBox(height: 22),
            _sectionLabel('DETECTION BREAKDOWN', assets),
            ...analysis.reasons.map(_reasonCard),
          ],
        ],
      ),
    );

    final outputDir = await getApplicationDocumentsDirectory();
    final file = File('${outputDir.path}/ScamShield_Report_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Full deep-scan APK security audit (Androguard + YARA + Secrets + OSINT),
  /// used by the dedicated APK Scan screen's "Export Security Audit PDF".
  static Future<String> generatePdf(
    Map<String, dynamic> report, {
    String fileName = 'scan.apk',
  }) async {
    final assets = await _ReportAssets.load();

    final fileInfo = report['file_info'] as Map<String, dynamic>? ?? {};
    final risk = report['risk'] as Map<String, dynamic>? ?? {};
    final aiExplanation = report['ai_explanation'] as String? ?? 'Analysis complete.';

    final level = (risk['level'] as String? ?? 'UNKNOWN').toUpperCase();
    final score = risk['score'] as int? ?? 0;
    final riskDetails = (risk['details'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final riskBreakdown = (risk['breakdown'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    final androguard = report['androguard'] as Map<String, dynamic>? ?? {};
    final permissions = (androguard['permissions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final dangerousPerms =
        (androguard['dangerous_permissions'] as List<dynamic>?)?.map((e) => e.toString().toUpperCase()).toSet() ?? {};
    final packageName = androguard['package_name'] as String? ?? 'Unknown';
    final androguardStatus = androguard['status'] as String? ?? 'unavailable';
    final certificates = (androguard['certificates'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    final secrets = report['secrets'] as Map<String, dynamic>? ?? {};
    final secretsFindings = secrets['findings'] as Map<String, dynamic>? ?? {};
    final suspiciousUrls = (secrets['suspicious_urls'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

    final yara = report['yara'] as Map<String, dynamic>? ?? {};
    final yaraMatches = (yara['matches'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

    final osint = report['osint'] as Map<String, dynamic>? ?? {};
    final vt = osint['virustotal'] as Map<String, dynamic>? ?? {};
    final vtChecked = vt['checked'] as bool? ?? false;
    final vtMalicious = vt['malicious'] as int? ?? 0;
    final vtSuspicious = vt['suspicious'] as int? ?? 0;
    final vtNote = vt['note'] as String? ?? 'Not available.';

    final sb = osint['safe_browsing'] as Map<String, dynamic>? ?? {};
    final sbChecked = sb['checked'] as bool? ?? false;
    final sbResults = (sb['results'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final sbFlagged = sbResults.where((r) => r['malicious'] == true).toList();

    final scanMode = report['scan_mode'] as String? ?? 'local';

    final pdf = pw.Document(theme: assets.theme, title: 'ScamShield Security Audit — $fileName');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 32),
        footer: (context) => _footer(context),
        build: (context) => [
          _brandHeader(
            assets: assets,
            title: 'APK Security Audit Report',
            target: fileName,
            engineLabel: scanMode == 'server'
                ? 'Full Server Analysis (Androguard + YARA + OSINT)'
                : 'On-Device Static Engine',
          ),
          pw.SizedBox(height: 22),

          _sectionLabel('1. EXECUTIVE VERDICT', assets),
          _verdictHero(label: level, score: score, summary: aiExplanation),
          pw.SizedBox(height: 22),

          _sectionLabel('2. FILE INFORMATION', assets),
          _kvCard([
            _KV('Filename', fileName),
            _KV('Package', packageName),
            _KV('Size', '${((fileInfo['size'] as num? ?? 0) / 1024 / 1024).toStringAsFixed(2)} MB'),
            _KV('MD5', fileInfo['md5']?.toString() ?? 'N/A'),
            _KV('SHA-1', fileInfo['sha1']?.toString() ?? 'N/A'),
            _KV('SHA-256', fileInfo['sha256']?.toString() ?? 'N/A'),
          ]),
          pw.SizedBox(height: 22),

          _sectionLabel('3. SECURITY FINDINGS', assets),
          riskDetails.isEmpty
              ? _emptyNote('No threat patterns found.', color: _RC.success)
              : pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: riskDetails.map((d) => _findingCard(d, _RC.forLabel(level))).toList(),
                ),
          pw.SizedBox(height: 22),

          _sectionLabel('4. ANDROID ANALYSIS', assets),
          _kvCard([
            _KV('Androguard Status', androguardStatus),
            _KV('Package Name', packageName),
            _KV('Total Permissions', '${permissions.length}'),
            _KV('Dangerous Permissions', dangerousPerms.isNotEmpty ? dangerousPerms.join(', ') : 'None'),
          ]),
          if (certificates.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _subLabel('Certificates', assets),
            pw.SizedBox(height: 6),
            ...certificates.take(3).map(_certCard),
          ],
          if (permissions.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _subLabel('All Permissions', assets),
            pw.SizedBox(height: 6),
            _chipWrap(permissions.take(60).toList(), highlight: dangerousPerms),
          ],
          pw.SizedBox(height: 22),

          _sectionLabel('5. YARA ANALYSIS', assets),
          yaraMatches.isEmpty
              ? _emptyNote('No configured YARA signatures matched.', color: _RC.success)
              : pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 6),
                      child: pw.Text('${yaraMatches.length} rule(s) matched — HIGH RISK',
                          style: pw.TextStyle(color: _RC.dangerDark, fontWeight: pw.FontWeight.bold, fontSize: 10.5)),
                    ),
                    ...yaraMatches.map((m) => _findingCard(m, _RC.danger)),
                  ],
                ),
          pw.SizedBox(height: 22),

          _sectionLabel('6. VIRUSTOTAL', assets),
          !vtChecked
              ? _emptyNote(vtNote)
              : _kvCard([
                  _KV('Malicious', '$vtMalicious engine(s)'),
                  _KV('Suspicious', '$vtSuspicious engine(s)'),
                  _KV('Status', vtNote),
                ]),
          pw.SizedBox(height: 22),

          _sectionLabel('7. GOOGLE SAFE BROWSING', assets),
          !sbChecked
              ? _emptyNote('Not configured — no URLs were checked.')
              : sbResults.isEmpty
                  ? _emptyNote('No URLs found in APK to check.')
                  : pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          sbFlagged.isNotEmpty
                              ? '${sbFlagged.length} URL(s) flagged as dangerous'
                              : 'All ${sbResults.length} URL(s) checked — clean',
                          style: pw.TextStyle(
                            color: sbFlagged.isNotEmpty ? _RC.dangerDark : _RC.successDark,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10.5,
                          ),
                        ),
                        if (sbFlagged.isNotEmpty) ...[
                          pw.SizedBox(height: 6),
                          ...sbFlagged.take(5).map((r) => _monoLine(r['url']?.toString() ?? '', color: _RC.dangerDark)),
                        ],
                      ],
                    ),
          pw.SizedBox(height: 22),

          if (secretsFindings.isNotEmpty || suspiciousUrls.isNotEmpty) ...[
            _sectionLabel('8. SECRETS & SUSPICIOUS STRINGS', assets, accent: _RC.danger),
            if (secretsFindings.isNotEmpty) ...[
              _subLabel('Hardcoded Secrets Found', assets),
              pw.SizedBox(height: 6),
              _kvCard(secretsFindings.entries.map((e) => _KV(e.key, '${e.value} occurrence(s)')).toList()),
            ],
            if (suspiciousUrls.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              _subLabel('Suspicious URLs', assets),
              pw.SizedBox(height: 6),
              ...suspiciousUrls.take(10).map((u) => _monoLine(u, color: _RC.warningDark)),
            ],
            pw.SizedBox(height: 22),
          ],

          if (riskBreakdown.isNotEmpty) ...[
            _sectionLabel('9. RISK SCORE BREAKDOWN', assets),
            _breakdownTable(riskBreakdown, score, level, assets),
            pw.SizedBox(height: 22),
          ],

          _sectionLabel('10. RECOMMENDATION', assets),
          _recommendationBox(
            level,
            level == 'CRITICAL' || level == 'HIGH'
                ? 'DO NOT install this APK. Multiple high-severity threat indicators were detected. Delete the file immediately.'
                : level == 'MEDIUM'
                    ? 'Exercise caution. Install only if you trust the source. Review the flagged permissions before proceeding.'
                    : 'Low risk detected based on available analysis. Ensure the APK is from an official, trusted source before installing.',
          ),
          pw.SizedBox(height: 18),

          pw.Divider(color: _RC.border),
          pw.Text(
            'This report reflects analysis at the time of scan. VirusTotal and Safe Browsing results depend on '
            'configured API keys and current threat-intelligence databases.',
            style: const pw.TextStyle(fontSize: 8, color: _RC.textFaint),
          ),
        ],
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/ScamShield_AuditReport_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  // ── Shared building blocks ────────────────────────────────────────────────

  static pw.Widget _brandHeader({
    required _ReportAssets assets,
    required String title,
    required String target,
    required String engineLabel,
  }) {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: _RC.ink,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.ClipRRect(
                horizontalRadius: 8,
                verticalRadius: 8,
                child: pw.Image(assets.logo, width: 34, height: 34),
              ),
              pw.SizedBox(width: 12),
              pw.Text(
                'SCAMSHIELD',
                style: pw.TextStyle(font: assets.semiBold, fontSize: 10, color: _RC.cyan, letterSpacing: 3),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20, color: PdfColors.white)),
          pw.SizedBox(height: 8),
          pw.Text('Target: $target', style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey300)),
          pw.Text('Generated: $dateStr', style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey300)),
          pw.Text('Engine: $engineLabel', style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey300)),
        ],
      ),
    );
  }

  static pw.Widget _sectionLabel(String title, _ReportAssets assets, {PdfColor accent = _RC.cyan}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Row(
        children: [
          pw.Container(width: 4, height: 13, color: accent),
          pw.SizedBox(width: 8),
          pw.Text(
            title,
            style: pw.TextStyle(font: assets.semiBold, fontSize: 11, color: _RC.ink, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  static pw.Widget _subLabel(String title, _ReportAssets assets) {
    return pw.Text(title, style: pw.TextStyle(font: assets.semiBold, fontSize: 10, color: _RC.ink));
  }

  static pw.Widget _emptyNote(String text, {PdfColor color = _RC.textMuted}) {
    return pw.Text(text, style: pw.TextStyle(fontSize: 9.5, color: color, fontStyle: pw.FontStyle.italic));
  }

  static pw.Widget _monoLine(String text, {PdfColor color = _RC.textMuted}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 8.5, color: color)),
    );
  }

  /// A rounded, bordered card of label/value rows with alternating tints.
  static pw.Widget _kvCard(List<_KV> data) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _RC.border, width: 0.75),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.ClipRRect(
        horizontalRadius: 6,
        verticalRadius: 6,
        child: pw.Column(
          // Rows must stretch full width, otherwise each alternating-tint
          // background shrink-wraps to its own text (Column's default
          // cross-axis alignment is center), producing ragged-width stripes
          // instead of a clean table.
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < data.length; i++)
              pw.Container(
                color: i.isEven ? PdfColors.white : _RC.rowAlt,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: 130,
                      child: pw.Text(data[i].label, style: const pw.TextStyle(fontSize: 9, color: _RC.textMuted)),
                    ),
                    pw.Expanded(
                      child: pw.Text(data[i].value, style: const pw.TextStyle(fontSize: 9.5, color: _RC.ink)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _chipWrap(List<String> items, {Set<String> highlight = const {}}) {
    return pw.Wrap(
      spacing: 5,
      runSpacing: 5,
      children: items.map((p) {
        final isDangerous = highlight.any((d) => p.toUpperCase().contains(d));
        final shortP = p.replaceAll('android.permission.', '').replaceAll('android.', '');
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: pw.BoxDecoration(
            color: isDangerous ? _RC.dangerBg : _RC.chipBg,
            border: pw.Border.all(color: isDangerous ? _RC.danger : _RC.border, width: 0.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
          ),
          child: pw.Text(
            shortP,
            style: pw.TextStyle(
              fontSize: 7.5,
              color: isDangerous ? _RC.dangerDark : _RC.textMuted,
              fontWeight: isDangerous ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );
      }).toList(),
    );
  }

  /// A left-accent-bar card for a single finding/risk-factor line.
  static pw.Widget _findingCard(String text, PdfColor color) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _RC.rowAlt,
        border: pw.Border(left: pw.BorderSide(color: color, width: 2.5)),
        borderRadius: const pw.BorderRadius.only(
          topRight: pw.Radius.circular(4),
          bottomRight: pw.Radius.circular(4),
        ),
      ),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 9.5, color: _RC.ink)),
    );
  }

  static pw.Widget _reasonCard(DetectionReason r) {
    final color = r.scoreContribution >= 20 ? _RC.danger : _RC.warning;
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 7),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _RC.rowAlt,
        border: pw.Border(left: pw.BorderSide(color: color, width: 2.5)),
        borderRadius: const pw.BorderRadius.only(
          topRight: pw.Radius.circular(4),
          bottomRight: pw.Radius.circular(4),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(r.label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: _RC.ink)),
              pw.Text('+${r.scoreContribution}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: color)),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Text(r.description, style: const pw.TextStyle(fontSize: 9, color: _RC.textMuted)),
        ],
      ),
    );
  }

  static pw.Widget _osintRow(OsintResult o) {
    // An unreachable provider must not be rendered green: "we could not
    // check" is not the same as "verified clean".
    final color = o.isMalicious ? _RC.danger : (o.available ? _RC.success : _RC.textFaint);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 3, right: 7),
            width: 6,
            height: 6,
            decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
          ),
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(children: [
                pw.TextSpan(
                  text: '${o.provider}: ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: _RC.ink),
                ),
                pw.TextSpan(text: o.details, style: const pw.TextStyle(fontSize: 9.5, color: _RC.textMuted)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _certCard(Map<String, dynamic> c) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(color: _RC.chipBg, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5))),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (c['subject'] != null)
            pw.Text('Subject: ${c['subject']}', style: const pw.TextStyle(fontSize: 8.5, color: _RC.ink)),
          if (c['issuer'] != null)
            pw.Text('Issuer: ${c['issuer']}', style: const pw.TextStyle(fontSize: 8.5, color: _RC.textMuted)),
          if (c['sha256'] != null)
            pw.Text('SHA-256: ${c['sha256']}', style: const pw.TextStyle(fontSize: 7.5, color: _RC.textFaint)),
        ],
      ),
    );
  }

  /// The headline verdict card: a colored badge, a numeric score, a
  /// proportional risk meter, and the summary/AI-explanation text.
  static pw.Widget _verdictHero({
    required String label,
    required int score,
    required String summary,
  }) {
    final color = _RC.forLabel(label);
    final dark = _RC.darkForLabel(label);
    final bg = _RC.bgForLabel(label);
    // Expanded's flex is int and must be > 0 on both sides, so a 0 or 100
    // score still renders a (near-empty/near-full) two-segment bar instead
    // of a type error (num.clamp returns num) or an assertion failure.
    final int filled = score < 1 ? 1 : (score > 99 ? 99 : score);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: bg,
        border: pw.Border.all(color: color, width: 1.2),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 22, color: dark)),
              pw.Text('$score/100', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15, color: dark)),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.ClipRRect(
            horizontalRadius: 5,
            verticalRadius: 5,
            child: pw.Row(
              children: [
                pw.Expanded(flex: filled, child: pw.Container(height: 9, color: color)),
                pw.Expanded(flex: 100 - filled, child: pw.Container(height: 9, color: PdfColors.white)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(summary, style: pw.TextStyle(fontSize: 10, color: _RC.ink, lineSpacing: 3)),
        ],
      ),
    );
  }

  static pw.Widget _recommendationBox(String label, String text) {
    final color = _RC.forLabel(label);
    final dark = _RC.darkForLabel(label);
    final bg = _RC.bgForLabel(label);
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: bg,
        border: pw.Border.all(color: color, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Text(text, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: dark)),
    );
  }

  static pw.Widget _breakdownTable(
    List<Map<String, dynamic>> items,
    int score,
    String level,
    _ReportAssets assets,
  ) {
    return pw.ClipRRect(
      horizontalRadius: 6,
      verticalRadius: 6,
      child: pw.Table(
        border: pw.TableBorder.symmetric(inside: const pw.BorderSide(color: _RC.border, width: 0.5)),
        columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1)},
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _RC.ink),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: pw.Text('Factor',
                    style: pw.TextStyle(font: assets.semiBold, fontSize: 9.5, color: PdfColors.white)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: pw.Text('Points',
                    style: pw.TextStyle(font: assets.semiBold, fontSize: 9.5, color: PdfColors.white)),
              ),
            ],
          ),
          for (var i = 0; i < items.length; i++)
            pw.TableRow(
              decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _RC.rowAlt),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: pw.Text(items[i]['factor']?.toString() ?? '',
                      style: const pw.TextStyle(fontSize: 9.5, color: _RC.ink)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: pw.Text('+${items[i]['points']}',
                      style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _RC.dangerDark)),
                ),
              ],
            ),
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _RC.chipBg),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: pw.Text('TOTAL', style: pw.TextStyle(font: assets.semiBold, fontSize: 10, color: _RC.ink)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: pw.Text('$score / 100',
                    style: pw.TextStyle(font: assets.semiBold, fontSize: 10, color: _RC.forLabel(level))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context) {
    return pw.Column(
      children: [
        pw.Divider(color: _RC.border, height: 1),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('ScamShield — Confidential Security Report',
                style: const pw.TextStyle(fontSize: 7.5, color: _RC.textFaint)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 7.5, color: _RC.textFaint)),
          ],
        ),
      ],
    );
  }
}
