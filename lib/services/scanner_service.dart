import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'apk_analyzer_service.dart';

class ScannerService {
  final String baseUrl;

  ScannerService({String? baseUrl}) 
      : baseUrl = baseUrl ?? _resolveBaseUrl();

  static String _resolveBaseUrl() {
    const customUrl = String.fromEnvironment('SCAMSHIELD_BACKEND_URL');
    if (customUrl.isNotEmpty) return customUrl;
    return Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
  }

  Future<Map<String, dynamic>> scanApk(PlatformFile apkFile) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/scan'));
      
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          apkFile.path!,
          filename: apkFile.name,
        ),
      );

      // Timeout backend connection after 5 seconds
      var streamedResponse = await request.send().timeout(const Duration(seconds: 5));
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        data['scan_mode'] = 'server';
        return data;
      }
    } catch (_) {
      // Backend is offline/unreachable or timed out: fall back to local static engine
    }

    // Fallback to local static APK engine
    return await _performLocalScan(apkFile);
  }

  Future<Map<String, dynamic>> _performLocalScan(PlatformFile apkFile) async {
    final result = await ApkAnalyzerService.analyzeApk(apkFile.path!);

    final riskFactors = <String>[];
    int riskScore = 15; // Base score

    if (result.permissions.any((p) => p.contains('RECEIVE_SMS') || p.contains('READ_SMS') || p.contains('SEND_SMS'))) {
      riskFactors.add('Requests sensitive SMS reading/sending permissions.');
      riskScore += 30;
    }
    if (result.permissions.any((p) => p.contains('SYSTEM_ALERT_WINDOW') || p.contains('BIND_ACCESSIBILITY_SERVICE'))) {
      riskFactors.add('Requests overlay or accessibility service permissions (common in banking Trojans).');
      riskScore += 35;
    }
    if (result.permissions.any((p) => p.contains('INSTALL_PACKAGES') || p.contains('REQUEST_INSTALL_PACKAGES'))) {
      riskFactors.add('Can silently download or install third-party packages.');
      riskScore += 20;
    }
    if (result.secrets.isNotEmpty) {
      riskFactors.add('Contains hardcoded API keys/secrets inside dex/so binaries.');
      riskScore += 25;
    }
    if (result.urls.isNotEmpty) {
      riskFactors.add('Extracted ${result.urls.length} remote network endpoints.');
      riskScore += 10;
    }

    riskScore = riskScore.clamp(0, 100);

    String level = 'LOW';
    if (riskScore >= 75) {
      level = 'CRITICAL';
    } else if (riskScore >= 50) {
      level = 'HIGH';
    } else if (riskScore >= 30) {
      level = 'MEDIUM';
    }

    final secretsMap = <String, String>{};
    for (int i = 0; i < result.secrets.length; i++) {
      secretsMap['secret_$i'] = result.secrets[i];
    }

    return {
      'scan_mode': 'local',
      'risk': {
        'level': level,
        'score': riskScore,
        'details': riskFactors.isEmpty ? ['No major threat patterns found in static code structure.'] : riskFactors,
      },
      'ai_explanation': 'Local Engine Analysis: Analyzed package structure, certificate hashes, Dex bytecode, and AndroidManifest. ${riskFactors.isNotEmpty ? "Flagged ${riskFactors.length} potential security concerns." : "Package appears clean based on local static rules."}',
      'file_info': {
        'md5': result.md5,
        'sha1': result.sha1,
        'sha256': result.sha256,
        'size': File(apkFile.path!).lengthSync(),
      },
      'androguard': {
        'permissions': result.permissions,
        'package_name': result.metadata['Package'] ?? apkFile.name,
        'certificates': result.certificates,
      },
      'secrets': {
        'findings': secretsMap,
        'urls': result.urls,
      },
      'yara': {
        'matches': result.secrets.isNotEmpty ? ['Hardcoded_Secrets_Rule'] : [],
      },
      'osint': {
        // On-device fallback: the cloud threat-intel providers are proxied
        // through the ScamShield backend (which holds the API keys), so they
        // are not "misconfigured" here — they simply were not run because the
        // backend was unreachable for this scan. Report that honestly and with
        // the same shape the server path returns, so the UI can render a clear
        // status instead of a scary "not available / not configured" message.
        'virustotal': {
          'checked': false,
          'malicious': 0,
          'suspicious': 0,
          'note':
              'Cloud reputation not run in on-device mode. Reconnect to the '
              'ScamShield backend (with a VirusTotal key configured) for a live '
              'multi-engine verdict.',
        },
        'safe_browsing': {
          'checked': false,
          'results': const <Map<String, dynamic>>[],
          'urls_found': result.urls.length,
          'note': result.urls.isEmpty
              ? 'No URLs were extracted from this APK, so there was nothing to check.'
              : '${result.urls.length} URL(s) extracted. Reconnect to the ScamShield '
                  'backend (with a Google Safe Browsing key configured) to screen '
                  'them live.',
        },
      }
    };
  }
}

