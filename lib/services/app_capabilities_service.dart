// lib/services/app_capabilities_service.dart

import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'backend_config.dart';
import 'device_identity.dart';

class AppCapabilities {
  final bool isBackendReachable;
  final bool hasFullAi;
  final bool hasOsint;
  final bool hasFullApkPipeline;
  final bool isOfflineMode;
  final String modeLabel;

  const AppCapabilities({
    required this.isBackendReachable,
    required this.hasFullAi,
    required this.hasOsint,
    required this.hasFullApkPipeline,
    required this.isOfflineMode,
    required this.modeLabel,
  });

  static const offline = AppCapabilities(
    isBackendReachable: false,
    hasFullAi: false,
    hasOsint: false,
    hasFullApkPipeline: false,
    isOfflineMode: true,
    modeLabel: 'Limited Mode — On-Device Heuristics & Local Storage Only',
  );
}

class AppCapabilitiesService {
  static String get _baseUrl => BackendConfig.baseUrl;

  static final ValueNotifier<AppCapabilities> capabilities =
      ValueNotifier<AppCapabilities>(AppCapabilities.offline);

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Listen to network changes
    Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (offline) {
        capabilities.value = AppCapabilities.offline;
      } else {
        refreshCapabilities();
      }
    });

    await refreshCapabilities();
  }

  static Future<AppCapabilities> refreshCapabilities() async {
    try {
      final headers = await DeviceIdentity.authHeaders();
      final response = await http
          .get(Uri.parse('$_baseUrl/health'), headers: headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final apiStatus = data['api_status'] as Map<String, dynamic>? ?? {};

        final geminiOk = apiStatus['gemini']?['available'] == true;
        final groqOk = apiStatus['groq']?['available'] == true;
        final llmOk = apiStatus['llm']?['available'] == true || geminiOk || groqOk;

        final vtOk = apiStatus['virustotal']?['available'] == true;
        final sbOk = apiStatus['safe_browsing']?['available'] == true;
        final ipOk = apiStatus['abuseipdb']?['available'] == true;
        final osintOk = vtOk || sbOk || ipOk;

        // New field (apk_tools.full_pipeline) with backward-compatible fallback.
        final apkTools = apiStatus['apk_tools'] as Map<String, dynamic>? ?? {};
        final fullApkOk = apkTools['full_pipeline'] == true ||
            apiStatus['full_apk_pipeline'] == true;

        String label;
        if (llmOk && osintOk) {
          label = 'Full Mode — Gemini AI & Live OSINT Active';
        } else if (llmOk) {
          label = 'AI Mode — Gemini AI Active (OSINT Limited)';
        } else if (osintOk) {
          label = 'OSINT Mode — Live Threat Intel Active (Heuristic Analysis)';
        } else {
          label = 'Limited Mode — Server Heuristics & Local Rules Only';
        }

        final caps = AppCapabilities(
          isBackendReachable: true,
          hasFullAi: llmOk,
          hasOsint: osintOk,
          hasFullApkPipeline: fullApkOk,
          isOfflineMode: false,
          modeLabel: label,
        );

        capabilities.value = caps;
        return caps;
      }
    } catch (e) {
      debugPrint('AppCapabilitiesService probe failed: $e');
    }

    capabilities.value = AppCapabilities.offline;
    return AppCapabilities.offline;
  }
}
