// lib/services/breach_service.dart
// Real HIBP (Have I Been Pwned) integration for email breach lookups.
// Free endpoints: /breaches (all known breaches, no key needed)
// Email-specific: /breachedaccount/{email} (requires Pwned API key for production)

import 'dart:convert';
import 'package:http/http.dart' as http;

class BreachInfo {
  final String name;
  final String title;
  final String domain;
  final String breachDate;
  final int pwnCount;
  final String description;
  final List<String> dataClasses;
  final bool isVerified;

  const BreachInfo({
    required this.name,
    required this.title,
    required this.domain,
    required this.breachDate,
    required this.pwnCount,
    required this.description,
    required this.dataClasses,
    required this.isVerified,
  });

  factory BreachInfo.fromJson(Map<String, dynamic> json) {
    return BreachInfo(
      name: json['Name'] ?? '',
      title: json['Title'] ?? '',
      domain: json['Domain'] ?? '',
      breachDate: json['BreachDate'] ?? '',
      pwnCount: json['PwnCount'] ?? 0,
      description: _stripHtml(json['Description'] ?? ''),
      dataClasses: List<String>.from(json['DataClasses'] ?? []),
      isVerified: json['IsVerified'] ?? false,
    );
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String get formattedCount {
    if (pwnCount >= 1000000000) return '${(pwnCount / 1000000000).toStringAsFixed(1)}B';
    if (pwnCount >= 1000000) return '${(pwnCount / 1000000).toStringAsFixed(1)}M';
    if (pwnCount >= 1000) return '${(pwnCount / 1000).toStringAsFixed(0)}K';
    return '$pwnCount';
  }
}

class BreachService {
  static const _baseUrl = 'https://haveibeenpwned.com/api/v3';
  static const _userAgent = 'ScamShield-App/1.0';

  // Optional: set this from secure storage / build config for email-specific checks
  static String? apiKey;

  /// Fetch all known breaches from HIBP — no API key required.
  /// Returns the 20 most recent breaches sorted by date descending.
  static Future<List<BreachInfo>> getRecentBreaches({int limit = 30}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/breaches'),
        headers: {
          'User-Agent': _userAgent,
          'hibp-api-key': apiKey ?? '',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final breaches = data
            .map((e) => BreachInfo.fromJson(e as Map<String, dynamic>))
            .toList();
        // Sort by breach date descending (most recent first)
        breaches.sort((a, b) => b.breachDate.compareTo(a.breachDate));
        return breaches.take(limit).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Check if an email has been in any known breach.
  /// Requires a paid HIBP API key (https://haveibeenpwned.com/API/Key).
  /// Returns null if no key is set (graceful degradation).
  static Future<List<BreachInfo>?> checkEmail(String email) async {
    if (apiKey == null || apiKey!.isEmpty) {
      return null; // No key — caller should show "upgrade" message
    }

    try {
      final encoded = Uri.encodeComponent(email.trim().toLowerCase());
      final response = await http.get(
        Uri.parse('$_baseUrl/breachedaccount/$encoded?truncateResponse=false'),
        headers: {
          'User-Agent': _userAgent,
          'hibp-api-key': apiKey!,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data
            .map((e) => BreachInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (response.statusCode == 404) {
        return []; // No breaches found for this email
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Search breaches by name/domain filter (client-side filtering of full list).
  static Future<List<BreachInfo>> searchBreaches(String query) async {
    final all = await getRecentBreaches(limit: 500);
    if (query.trim().isEmpty) return all.take(30).toList();
    final q = query.toLowerCase();
    return all.where((b) =>
      b.title.toLowerCase().contains(q) ||
      b.domain.toLowerCase().contains(q) ||
      b.dataClasses.any((d) => d.toLowerCase().contains(q))
    ).toList();
  }
}
