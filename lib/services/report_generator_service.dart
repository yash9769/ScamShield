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
    final permissions = (report['androguard']?['permissions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final yaraMatches = (report['yara']?['matches'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final secretsMap = report['secrets']?['findings'] as Map<String, dynamic>? ?? {};
    final secrets = secretsMap.entries.map((e) => '${e.key}: ${e.value}').toList();
    final urls = (report['secrets']?['urls'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final certificates = (report['androguard']?['certificates'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

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
              pw.Text('[${o.provider}] ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: o.isMalicious ? PdfColors.red : PdfColors.green)),
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
}
