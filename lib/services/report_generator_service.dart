import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'apk_analyzer_service.dart';
import 'osint_service.dart';
import 'scam_detector.dart';

class ReportGeneratorService {
  static Future<File> generateApkReport({
    required ApkAnalysisResult apk,
    required List<OsintResult> osintResults,
    required AnalysisResult analysis,
    required String fileName,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _buildHeader(fileName),
            pw.SizedBox(height: 20),
            _buildSummaryBox(analysis),
            pw.SizedBox(height: 20),
            _buildHashes(apk),
            pw.SizedBox(height: 20),
            _buildMetadata(apk),
            pw.SizedBox(height: 20),
            _buildSecrets(apk.secrets),
            pw.SizedBox(height: 20),
            _buildPermissions(apk.permissions),
            pw.SizedBox(height: 20),
            _buildOsintResults(osintResults),
            pw.SizedBox(height: 20),
            _buildReasons(analysis.reasons),
          ];
        },
      ),
    );

    final outputDir = await getApplicationDocumentsDirectory();
    final file = File('${outputDir.path}/ScamShield_Report_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static Future<File> generateServerApkReport({
    required Map<String, dynamic> report,
    required String fileName,
  }) async {
    final pdf = pw.Document();

    final risk = report['risk'] ?? {};
    final level = risk['level'] ?? 'UNKNOWN';
    final score = risk['score'] ?? 0;
    
    PdfColor color = PdfColors.green;
    PdfColor lightColor = PdfColor.fromHex('#e8f5e9');
    PdfColor darkColor = PdfColor.fromHex('#1b5e20');

    if (level == 'HIGH' || level == 'CRITICAL') {
      color = PdfColors.red;
      lightColor = PdfColor.fromHex('#ffebee');
      darkColor = PdfColor.fromHex('#b71c1c');
    } else if (level == 'MEDIUM') {
      color = PdfColors.orange;
      lightColor = PdfColor.fromHex('#fff3e0');
      darkColor = PdfColor.fromHex('#e65100');
    }

    final aiExplanation = report['ai_explanation'] ?? 'No AI explanation available.';
    final riskDetails = (risk['details'] as List<dynamic>?) ?? [];
    
    final fileInfo = report['file_info'] ?? {};
    final androguardMap = report['androguard'] ?? {};
    final permissions = (androguardMap['permissions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final dexFingerprint = androguardMap['dex_structural_fingerprint'] as String?;
    final yaraMatches = (report['yara']?['matches'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final secretsMap = report['secrets']?['findings'] as Map<String, dynamic>? ?? {};
    final secrets = secretsMap.entries.map((e) => '${e.key}: ${e.value}').toList();
    final urls = (report['secrets']?['urls'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final certificates = (androguardMap['certificates'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

    final malicious = report['osint']?['virustotal']?['malicious'] ?? 0;
    final suspicious = report['osint']?['virustotal']?['suspicious'] ?? 0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _buildHeader(fileName),
            pw.SizedBox(height: 20),
            
            // Summary Box
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: lightColor,
                border: pw.Border.all(color: color, width: 2),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Risk Level: $level', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: darkColor)),
                  pw.Text('Risk Score: $score/100', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: darkColor)),
                  pw.SizedBox(height: 8),
                  pw.Text('AI Explanation:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(aiExplanation, style: pw.TextStyle(fontSize: 14)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            
            pw.Text('File Information', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            _buildRow('MD5', fileInfo['md5']?.toString() ?? 'N/A'),
            _buildRow('SHA-1', fileInfo['sha1']?.toString() ?? 'N/A'),
            _buildRow('SHA-256', fileInfo['sha256']?.toString() ?? 'N/A'),
            if (dexFingerprint != null && dexFingerprint.isNotEmpty)
              _buildRow('DEX Fingerprint', dexFingerprint),
            _buildRow('File Size', '${((fileInfo['size'] ?? 0) / 1024 / 1024).toStringAsFixed(2)} MB'),
            pw.SizedBox(height: 20),

            if (certificates.isNotEmpty) ...[
              pw.Text('Signer Certificates', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              ...certificates.map((c) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text('- $c', style: const pw.TextStyle(fontSize: 10)),
              )),
              pw.SizedBox(height: 20),
            ],

            // Risk Factors
            if (riskDetails.isNotEmpty) ...[
              pw.Text('Risk Factors', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              ...riskDetails.map((r) => pw.Text('- $r', style: const pw.TextStyle(fontSize: 12))),
              pw.SizedBox(height: 20),
            ],

            // OSINT
            pw.Text('OSINT Threat Intelligence', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text('VirusTotal Malicious Flags: $malicious', style: pw.TextStyle(color: malicious > 0 ? PdfColors.red : PdfColors.green)),
            pw.Text('VirusTotal Suspicious Flags: $suspicious', style: pw.TextStyle(color: suspicious > 0 ? PdfColors.orange : PdfColors.green)),
            pw.SizedBox(height: 20),

            if (yaraMatches.isNotEmpty) ...[
              pw.Text('YARA Rule Matches (${yaraMatches.length})', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
              pw.SizedBox(height: 8),
              ...yaraMatches.map((y) => pw.Text('- $y', style: const pw.TextStyle(fontSize: 12))),
              pw.SizedBox(height: 20),
            ],

            _buildSecrets(secrets),
            pw.SizedBox(height: 20),

            if (urls.isNotEmpty) ...[
              pw.Text('Extracted URLs & Trackers (${urls.length})', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              ...urls.map((u) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text(u, style: const pw.TextStyle(fontSize: 10, color: PdfColors.blue800)),
              )),
              pw.SizedBox(height: 20),
            ],

            // Static Analysis Permissions
            pw.Text('Requested Permissions (${permissions.length})', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            ...permissions.map((p) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text('- $p', style: const pw.TextStyle(fontSize: 10)),
            )),
          ];
        },
      ),
    );

    final outputDir = await getTemporaryDirectory();
    final file = File('${outputDir.path}/ScamShield_ServerReport_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _buildHeader(String fileName) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('ScamShield Analysis Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
        pw.SizedBox(height: 8),
        pw.Text('Target: $fileName', style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
        pw.Text('Generated: ${DateTime.now().toIso8601String()}', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
        pw.Divider(),
      ],
    );
  }

  static pw.Widget _buildSummaryBox(AnalysisResult analysis) {
    PdfColor color;
    PdfColor lightColor;
    PdfColor darkColor;

    if (analysis.classification == ScamClassification.scam) {
      color = PdfColors.red;
      lightColor = PdfColor.fromHex('#ffebee');
      darkColor = PdfColor.fromHex('#b71c1c');
    } else if (analysis.classification == ScamClassification.suspicious) {
      color = PdfColors.orange;
      lightColor = PdfColor.fromHex('#fff3e0');
      darkColor = PdfColor.fromHex('#e65100');
    } else {
      color = PdfColors.green;
      lightColor = PdfColor.fromHex('#e8f5e9');
      darkColor = PdfColor.fromHex('#1b5e20');
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: lightColor,
        border: pw.Border.all(color: color, width: 2),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#fff3e0'),
              border: pw.Border.all(color: PdfColors.orange800, width: 1.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Text(
              'LIMITED MODE: Local static analysis only — VirusTotal / full server pipeline not available',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.orange900,
              ),
            ),
          ),
          pw.Text('Risk Score: ${analysis.riskScore}/100', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: darkColor)),
          pw.SizedBox(height: 8),
          pw.Text(analysis.summary, style: pw.TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  static pw.Widget _buildHashes(ApkAnalysisResult apk) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('File Hashes', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        _buildRow('MD5', apk.md5),
        _buildRow('SHA-1', apk.sha1),
        _buildRow('SHA-256', apk.sha256),
        // Exact DEX structural fingerprint (SHA-256 over dex names + bodies) —
        // useful for matching repackaged variants with identical code.
        _buildRow('DEX Fingerprint', apk.dexStructuralFingerprint),
      ],
    );
  }

  static pw.Widget _buildMetadata(ApkAnalysisResult apk) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Package Metadata', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        if (apk.metadata.isNotEmpty)
          ...apk.metadata.entries.map((e) => _buildRow(e.key, e.value))
        else
          pw.Text('No package metadata extracted (AXML parsing disabled/failed)', style: const pw.TextStyle(color: PdfColors.grey)),
        pw.SizedBox(height: 12),
        pw.Text('Certificates', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        if (apk.certificates.isNotEmpty)
          ...apk.certificates.take(5).map((c) => pw.Text(c, style: const pw.TextStyle(fontSize: 10)))
        else
          pw.Text('No certificates found', style: const pw.TextStyle(color: PdfColors.grey)),
        pw.SizedBox(height: 12),
        pw.Text('Native Libraries', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text(apk.nativeLibraries.isEmpty ? 'None' : apk.nativeLibraries.join(', '), style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }

  static pw.Widget _buildPermissions(List<String> permissions) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Requested Permissions (${permissions.length})', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Wrap(
          spacing: 4,
          runSpacing: 4,
          children: permissions.map((p) => pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(p, style: const pw.TextStyle(fontSize: 10)),
          )).toList(),
        ),
      ],
    );
  }

  static pw.Widget _buildOsintResults(List<OsintResult> osint) {
    if (osint.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('OSINT Threat Intelligence', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        ...osint.map((o) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('[${o.provider}] ', style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                // An unreachable provider must not be rendered green: "we could
                // not check" is not the same as "verified clean".
                color: o.isMalicious
                    ? PdfColors.red
                    : (o.available ? PdfColors.green : PdfColors.grey600),
              )),
              pw.Expanded(child: pw.Text(o.details)),
            ],
          ),
        )),
      ],
    );
  }

  static pw.Widget _buildReasons(List<DetectionReason> reasons) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Detection Breakdown', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        ...reasons.map((r) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border(left: pw.BorderSide(color: PdfColors.blueGrey, width: 3)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('${r.label} (+${r.scoreContribution} risk)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(r.description, style: const pw.TextStyle(fontSize: 12)),
            ],
          ),
        )),
      ],
    );
  }

  static pw.Widget _buildSecrets(List<String> secrets) {
    if (secrets.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Exposed Secrets (${secrets.length})', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
        pw.SizedBox(height: 8),
        ...secrets.map((s) => pw.Text('- $s', style: const pw.TextStyle(fontSize: 12))),
      ],
    );
  }

  static pw.Widget _buildRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 100, child: pw.Text('$label:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  static Future<String> generatePdf(
      Map<String, dynamic> report, {
      String fileName = 'scan.apk',
    }) async {
    final pdf = pw.Document();
    final fileInfo = report['file_info'] as Map<String, dynamic>? ?? {};
    final risk = report['risk'] as Map<String, dynamic>? ?? {};
    final aiExplanation = report['ai_explanation'] as String? ?? 'Analysis complete.';

    final level = risk['level'] as String? ?? 'UNKNOWN';
    final score = risk['score'] as int? ?? 0;
    final riskDetails = (risk['details'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final riskBreakdown = (risk['breakdown'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    final androguard = report['androguard'] as Map<String, dynamic>? ?? {};
    final permissions = (androguard['permissions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final dangerousPerms = (androguard['dangerous_permissions'] as List<dynamic>?)?.map((e) => e.toString()).toSet() ?? {};
    final packageName = androguard['package_name'] as String? ?? 'Unknown';
    final androguardStatus = androguard['status'] as String? ?? 'unavailable';
    final dexFingerprint = androguard['dex_structural_fingerprint'] as String?;
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
    final scanDate = DateTime.now();

    PdfColor verdictColor = PdfColors.green800;
    PdfColor verdictBg = PdfColor.fromHex('#e8f5e9');
    if (level == 'HIGH' || level == 'CRITICAL') {
      verdictColor = PdfColors.red800;
      verdictBg = PdfColor.fromHex('#ffebee');
    } else if (level == 'MEDIUM') {
      verdictColor = PdfColors.orange800;
      verdictBg = PdfColor.fromHex('#fff3e0');
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('ScamShield APK Security Audit — Confidential',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
        build: (pw.Context context) {
          return [
            // ── HEADER ──────────────────────────────────────────────────────
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.blueGrey900,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('SCAMSHIELD',
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.cyan200,
                          letterSpacing: 3)),
                  pw.SizedBox(height: 4),
                  pw.Text('APK Security Audit Report',
                      style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white)),
                  pw.SizedBox(height: 8),
                  pw.Text('File: $fileName',
                      style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey300)),
                  pw.Text('Scan Date: ${scanDate.toIso8601String().substring(0, 19).replaceAll('T', ' ')} UTC',
                      style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey300)),
                  pw.Text('Engine: ${scanMode == 'server' ? 'Full Server Analysis (Androguard + YARA + OSINT)' : 'Local Static Analysis Only (Offline Fallback)'}',
                      style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey300)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // ── 1. EXECUTIVE VERDICT ────────────────────────────────────────
            _pdfSectionTitle('1. Executive Verdict'),
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: verdictBg,
                border: pw.Border.all(color: verdictColor, width: 2),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (scanMode != 'server') ...[
                    pw.Container(
                      width: double.infinity,
                      margin: const pw.EdgeInsets.only(bottom: 10),
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#fff3e0'),
                        border: pw.Border.all(color: PdfColors.orange800, width: 1.5),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.Text(
                        'LIMITED MODE: Local static analysis only — VirusTotal / full server pipeline not available',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.orange900,
                        ),
                      ),
                    ),
                  ],
                  pw.Text('RISK LEVEL: $level',
                      style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: verdictColor)),
                  pw.Text('Risk Score: $score / 100',
                      style: pw.TextStyle(fontSize: 14, color: verdictColor)),
                  pw.SizedBox(height: 8),
                  pw.Text(aiExplanation, style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // ── 2. FILE INFORMATION ─────────────────────────────────────────
            _pdfSectionTitle('2. File Information'),
            _pdfRow('Filename', fileName),
            _pdfRow('Package', packageName),
            _pdfRow('Size',
                '${((fileInfo['size'] as num? ?? 0) / 1024 / 1024).toStringAsFixed(2)} MB'),
            _pdfRow('MD5', fileInfo['md5']?.toString() ?? 'N/A'),
            _pdfRow('SHA-1', fileInfo['sha1']?.toString() ?? 'N/A'),
            _pdfRow('SHA-256', fileInfo['sha256']?.toString() ?? 'N/A'),
            if (dexFingerprint != null && dexFingerprint.isNotEmpty)
              _pdfRow('DEX Fingerprint', dexFingerprint),
            pw.SizedBox(height: 20),

            // ── 3. SECURITY FINDINGS ────────────────────────────────────────
            _pdfSectionTitle('3. Security Findings'),
            if (riskDetails.isEmpty)
              pw.Text('No threat patterns found.',
                  style: const pw.TextStyle(color: PdfColors.green800))
            else
              ...riskDetails.map((d) => pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 6),
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                          left: pw.BorderSide(color: verdictColor, width: 3)),
                    ),
                    child: pw.Text('• $d',
                        style: const pw.TextStyle(fontSize: 11)),
                  )),
            pw.SizedBox(height: 20),

            // ── 4. ANDROID ANALYSIS ─────────────────────────────────────────
            _pdfSectionTitle('4. Android Analysis'),
            _pdfRow('Androguard Status', androguardStatus),
            _pdfRow('Package Name', packageName),
            _pdfRow('Total Permissions', '${permissions.length}'),
            _pdfRow('Dangerous Permissions', dangerousPerms.isNotEmpty ? dangerousPerms.join(', ') : 'None'),
            if (certificates.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text('Certificates:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.SizedBox(height: 4),
              ...certificates.take(3).map((c) => pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 6),
                    padding: const pw.EdgeInsets.all(6),
                    decoration: const pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius:
                            pw.BorderRadius.all(pw.Radius.circular(4))),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (c['subject'] != null)
                          pw.Text('Subject: ${c['subject']}',
                              style: const pw.TextStyle(fontSize: 9)),
                        if (c['issuer'] != null)
                          pw.Text('Issuer: ${c['issuer']}',
                              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        if (c['sha256'] != null)
                          pw.Text('SHA-256: ${c['sha256']}',
                              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                      ],
                    ),
                  )),
            ],
            if (permissions.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text('All Permissions:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.SizedBox(height: 4),
              pw.Wrap(
                spacing: 4,
                runSpacing: 4,
                children: permissions.take(40).map((p) {
                  final shortP = p
                      .replaceAll('android.permission.', '')
                      .replaceAll('android.', '');
                  final isDangerous =
                      dangerousPerms.any((d) => p.toUpperCase().contains(d));
                  return pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: pw.BoxDecoration(
                      color: isDangerous ? PdfColors.red100 : PdfColors.grey200,
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Text(shortP,
                        style: pw.TextStyle(
                            fontSize: 8,
                            color: isDangerous ? PdfColors.red900 : PdfColors.grey800,
                            fontWeight: isDangerous ? pw.FontWeight.bold : pw.FontWeight.normal)),
                  );
                }).toList(),
              ),
            ],
            pw.SizedBox(height: 20),

            // ── 5. YARA ANALYSIS ────────────────────────────────────────────
            _pdfSectionTitle('5. YARA Analysis'),
            if (yaraMatches.isEmpty)
              pw.Text('No configured YARA signatures matched.',
                  style: const pw.TextStyle(color: PdfColors.green800, fontSize: 11))
            else ...[
              pw.Text('${yaraMatches.length} rule(s) matched — HIGH RISK',
                  style: pw.TextStyle(
                      color: PdfColors.red800,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 12)),
              pw.SizedBox(height: 4),
              ...yaraMatches.map((m) => pw.Text('• $m',
                  style: pw.TextStyle(
                      color: PdfColors.red800, fontSize: 11))),
            ],
            pw.SizedBox(height: 20),

            // ── 6. VIRUSTOTAL ───────────────────────────────────────────────
            _pdfSectionTitle('6. VirusTotal'),
            if (!vtChecked)
              pw.Text(vtNote,
                  style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 11))
            else ...[
              _pdfRow('Malicious', '$vtMalicious engine(s)'),
              _pdfRow('Suspicious', '$vtSuspicious engine(s)'),
              _pdfRow('Status', vtNote),
            ],
            pw.SizedBox(height: 20),

            // ── 7. GOOGLE SAFE BROWSING ─────────────────────────────────────
            _pdfSectionTitle('7. Google Safe Browsing'),
            if (!sbChecked)
              pw.Text('Not configured — no URLs were checked.',
                  style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 11))
            else if (sbResults.isEmpty)
              pw.Text('No URLs found in APK to check.',
                  style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 11))
            else ...[
              pw.Text(
                  sbFlagged.isNotEmpty
                      ? '${sbFlagged.length} URL(s) flagged as dangerous'
                      : 'All ${sbResults.length} URL(s) checked — clean',
                  style: pw.TextStyle(
                      color: sbFlagged.isNotEmpty
                          ? PdfColors.red800
                          : PdfColors.green800,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 11)),
              if (sbFlagged.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                ...sbFlagged.take(5).map((r) => pw.Text(
                      '• ${r['url']}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.red700),
                    )),
              ],
            ],
            pw.SizedBox(height: 20),

            // ── 8. SECRETS & SUSPICIOUS STRINGS ────────────────────────────
            if (secretsFindings.isNotEmpty || suspiciousUrls.isNotEmpty) ...[
              _pdfSectionTitle('8. Secrets & Suspicious Strings'),
              if (secretsFindings.isNotEmpty) ...[
                pw.Text('Hardcoded Secrets Found:',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                        color: PdfColors.red800)),
                pw.SizedBox(height: 4),
                ...secretsFindings.entries.map((e) =>
                    _pdfRow(e.key, '${e.value} occurrence(s)')),
              ],
              if (suspiciousUrls.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text('Suspicious URLs:',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                        color: PdfColors.orange800)),
                pw.SizedBox(height: 4),
                ...suspiciousUrls.take(10).map((u) => pw.Text('• $u',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.orange800))),
              ],
              pw.SizedBox(height: 20),
            ],

            // ── 9. RISK SCORE BREAKDOWN ─────────────────────────────────────
            if (riskBreakdown.isNotEmpty) ...[
              _pdfSectionTitle('9. Risk Score Breakdown'),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Factor',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Points',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      ),
                    ],
                  ),
                  ...riskBreakdown.map((item) => pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(item['factor']?.toString() ?? '',
                                style: const pw.TextStyle(fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text('+${item['points']}',
                                style: pw.TextStyle(
                                    fontSize: 10,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.red800)),
                          ),
                        ],
                      )),
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('TOTAL',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('$score / 100',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 11,
                                color: verdictColor)),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
            ],

            // ── 10. RECOMMENDATION ──────────────────────────────────────────
            _pdfSectionTitle('10. Recommendation'),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: verdictBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                level == 'CRITICAL' || level == 'HIGH'
                    ? 'DO NOT install this APK. Multiple high-severity threat indicators were detected. Delete the file immediately.'
                    : level == 'MEDIUM'
                        ? 'Exercise caution. Install only if you trust the source. Review the flagged permissions before proceeding.'
                        : 'Low risk detected based on available analysis. Ensure the APK is from an official, trusted source before installing.',
                style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: verdictColor),
              ),
            ),
            pw.SizedBox(height: 20),

            // ── FOOTER NOTE ─────────────────────────────────────────────────
            pw.Divider(),
            pw.Text(
              'Generated by ScamShield on ${scanDate.toIso8601String().substring(0, 10)}. '
              'This report reflects analysis at the time of scan. '
              'VirusTotal and Safe Browsing results depend on configured API keys and current threat-intelligence databases.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ];
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/ScamShield_AuditReport_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  static pw.Widget _pdfSectionTitle(String title) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blueGrey900,
          ),
        ),
        pw.Divider(color: PdfColors.blueGrey200, height: 8),
        pw.SizedBox(height: 6),
      ],
    );
  }

  static pw.Widget _pdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            ),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }
}

