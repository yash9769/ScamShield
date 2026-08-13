import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'apk_analyzer_service.dart';
import 'backend_config.dart';
import 'device_identity.dart';

class ScannerService {
  final String baseUrl;

  ScannerService({String? baseUrl})
      : baseUrl = baseUrl ?? BackendConfig.baseUrl;

  Future<Map<String, dynamic>> scanApk(PlatformFile apkFile) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/scan'));
      request.headers.addAll(await DeviceIdentity.authHeaders());

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

    // Build human-readable risk factors from the richer on-device signals.
    final riskFactors = <String>[];

    if (result.permissionRiskScore >= 35) {
      riskFactors.add(
          'High-risk permission vector (score: ${result.permissionRiskScore}/100). '
          'Dangerous permissions: ${result.permissions.where((p) => _isDangerousPerm(p)).take(4).join(", ")}.');
    } else if (result.permissionRiskScore > 0) {
      riskFactors.add(
          'Moderate permission risk (score: ${result.permissionRiskScore}/100).');
    }

    if (result.dangerousApis.isNotEmpty) {
      riskFactors.add(
          'Dangerous API patterns detected in Dex bytecode: '
          '${result.dangerousApis.join(", ")}.');
    }

    if (result.certificateRiskScore > 0) {
      riskFactors.add('Certificate concern: ${result.certificateReputation}');
    }

    if (result.secrets.isNotEmpty) {
      riskFactors.add(
          'Contains ${result.secrets.length} hardcoded secret(s) '
          '(API keys / tokens) inside dex/so binaries.');
    }

    if (result.urls.isNotEmpty) {
      riskFactors.add(
          'Extracted ${result.urls.length} remote network endpoint(s). '
          'Review the Domains section for suspicious hosts.');
    }

    final riskScore = result.onDeviceRiskScore;
    final level = result.onDeviceRiskLevel;

    final secretsMap = <String, String>{};
    for (int i = 0; i < result.secrets.length; i++) {
      secretsMap['secret_$i'] = result.secrets[i];
    }

    return {
      'scan_mode': 'local',
      'risk': {
        'level': level,
        'score': riskScore,
        'details': riskFactors.isEmpty
            ? ['No major threat patterns found in static code structure.']
            : riskFactors,
      },
      'ai_explanation': 'On-Device Static Analysis: Analyzed '
          '${result.permissions.length} permissions, '
          '${result.dangerousApis.length} dangerous API pattern(s), '
          'certificate reputation, and Dex bytecode. '
          '${riskFactors.isNotEmpty ? "Flagged ${riskFactors.length} security concern(s)." : "Package appears clean."}',
      'file_info': {
        'md5': result.md5,
        'sha1': result.sha1,
        'sha256': result.sha256,
        'dex_fingerprint': result.dexStructuralFingerprint,
        'dex_minhash': result.dexMinHash,
        'size': File(apkFile.path!).lengthSync(),
      },
      'androguard': {
        'permissions': result.permissions,
        'package_name': result.metadata['Package'] ?? apkFile.name,
        'certificates': result.certificates,
        'certificate_reputation': result.certificateReputation,
        'dangerous_apis': result.dangerousApis,
        'native_libraries': result.nativeLibraries,
      },
      'secrets': {
        'findings': secretsMap,
        'urls': result.urls,
      },
      'yara': {
        'matches':
            result.secrets.isNotEmpty ? ['Hardcoded_Secrets_Rule'] : [],
      },
      'osint': {
        // On-device fallback: cloud threat-intel providers are not run because
        // the backend was unreachable. Report status honestly.
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
              ? 'No URLs were extracted from this APK.'
              : '${result.urls.length} URL(s) extracted. Reconnect to the '
                  'ScamShield backend to screen them live.',
        },
      },
    };
  }

  static bool _isDangerousPerm(String perm) {
    const dangerous = {
      'INSTALL_PACKAGES', 'REQUEST_INSTALL_PACKAGES',
      'BIND_ACCESSIBILITY_SERVICE', 'SYSTEM_ALERT_WINDOW',
      'READ_SMS', 'RECEIVE_SMS', 'SEND_SMS',
      'READ_CALL_LOG', 'WRITE_CALL_LOG', 'RECORD_AUDIO',
      'ACCESS_FINE_LOCATION', 'ACCESS_BACKGROUND_LOCATION',
    };
    return dangerous.contains(perm);
  }
}


