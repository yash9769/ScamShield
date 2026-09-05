// lib/services/community_report_service.dart
//
// Crowdsourced scam reporting: lets a user flag a phone number/URL/domain as
// a scam, and lets any screen check whether an indicator has already been
// reported before the user engages with it (answers a call, opens a link,
// pays a UPI handle from a QR code).
//
// Talks to POST /report and GET /reputation/{type}/{value} on the backend
// (server/main.py). Deliberately a thin, honest client: a failed lookup is
// reported as "unknown", never silently treated as "not a scam" — the same
// fail-closed convention used by OsintService.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum IndicatorType { phone, url, domain, upi }

extension on IndicatorType {
  String get value => switch (this) {
        IndicatorType.phone => 'phone',
        IndicatorType.url => 'url',
        IndicatorType.domain => 'domain',
        IndicatorType.upi => 'upi',
      };
}

class ReputationResult {
  final bool checked;
  final bool reported;
  final int reportCount;
  final String? category;

  const ReputationResult({
    required this.checked,
    required this.reported,
    required this.reportCount,
    this.category,
  });

  const ReputationResult.unavailable()
      : checked = false,
        reported = false,
        reportCount = 0,
        category = null;
}

class CommunityReportService {
  static String get _baseUrl {
    const customUrl = String.fromEnvironment('SCAMSHIELD_BACKEND_URL');
    if (customUrl.isNotEmpty) return customUrl;
    return Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
  }

  static const Duration _timeout = Duration(seconds: 6);

  /// Submits a scam report. Returns true only if the backend confirmed it
  /// was recorded — callers should show an error rather than a false
  /// "reported!" confirmation when this returns false.
  static Future<bool> reportIndicator({
    required IndicatorType type,
    required String value,
    String? category,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/report'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'indicator_type': type.value,
              'indicator_value': value,
              if (category != null) 'category': category,
            }),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('CommunityReportService.reportIndicator failed: $e');
      return false;
    }
  }

  /// Checks whether an indicator has been community-reported as a scam.
  static Future<ReputationResult> checkReputation({
    required IndicatorType type,
    required String value,
  }) async {
    try {
      final encoded = Uri.encodeComponent(value);
      final response = await http
          .get(Uri.parse('$_baseUrl/reputation/${type.value}/$encoded'))
          .timeout(_timeout);
      if (response.statusCode != 200) return const ReputationResult.unavailable();

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ReputationResult(
        checked: true,
        reported: data['reported'] == true,
        reportCount: (data['report_count'] ?? 0) as int,
        category: data['category'] as String?,
      );
    } catch (e) {
      debugPrint('CommunityReportService.checkReputation failed: $e');
      return const ReputationResult.unavailable();
    }
  }
}
