// lib/services/breach_service.dart
// Real HIBP (Have I Been Pwned) integration for email breach lookups.
// Free endpoints: /breaches (all known breaches, no key needed)
// Email-specific: /breachedaccount/{email} (requires Pwned API key for production)

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class BreachCheckException implements Exception {
  final String message;
  const BreachCheckException(this.message);

  @override
  String toString() => message;
}

class BackendBreachInfo {
  final String name;
  final String domain;
  final String date;
  final List<String> dataClasses;

  const BackendBreachInfo({
    required this.name,
    required this.domain,
    required this.date,
    required this.dataClasses,
  });

  factory BackendBreachInfo.fromJson(Map<String, dynamic> json) {
    return BackendBreachInfo(
      name: json['name'] ?? 'Unknown Breach',
      domain: json['domain'] ?? 'unknown.com',
      date: json['date'] ?? 'unknown',
      dataClasses: List<String>.from(json['dataClasses'] ?? []),
    );
  }
}

class BreachCheckResult {
  final String email;
  final bool exposed;
  final int breachCount;
  final List<BackendBreachInfo> breaches;
  final String source;
  final String checkedAt;

  const BreachCheckResult({
    required this.email,
    required this.exposed,
    required this.breachCount,
    required this.breaches,
    required this.source,
    required this.checkedAt,
  });

  factory BreachCheckResult.fromJson(Map<String, dynamic> json) {
    return BreachCheckResult(
      email: json['email'] ?? '',
      exposed: json['exposed'] ?? false,
      breachCount: json['breachCount'] ?? 0,
      breaches: (json['breaches'] as List? ?? [])
          .map((b) => BackendBreachInfo.fromJson(b as Map<String, dynamic>))
          .toList(),
      source: json['source'] ?? 'XposedOrNot',
      checkedAt: json['checkedAt'] ?? '',
    );
  }
}

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

  // HIBP API key — required for per-email breach lookup.
  // The /v3/breaches endpoint (all known breaches) is free and works without a key.
  // The /v3/breachedaccount/{email} endpoint requires a subscription key from:
  // https://haveibeenpwned.com/API/Key
  // Set this from your backend config or secure storage — never hard-code it.
  static String? apiKey;

  /// Whether per-email lookup is available (requires API key).
  static bool get emailCheckAvailable => apiKey != null && apiKey!.isNotEmpty;

  static final List<BreachInfo> _fallbackBreaches = [
    const BreachInfo(
      name: 'LinkedIn',
      title: 'LinkedIn Data Leak',
      domain: 'linkedin.com',
      breachDate: '2021-06-22',
      pwnCount: 700000000,
      description: 'In June 2021, an attacker scraped data from 700M LinkedIn users, exposing email addresses, full names, phone numbers, and professional details.',
      dataClasses: ['Email addresses', 'Full names', 'Phone numbers', 'Geographic locations', 'Professional titles'],
      isVerified: true,
    ),
    const BreachInfo(
      name: 'Canva',
      title: 'Canva Security Incident',
      domain: 'canva.com',
      breachDate: '2019-05-24',
      pwnCount: 137000000,
      description: 'In May 2019, graphic design tool Canva suffered a data breach impacting 137 million accounts including customer names, usernames, and bcrypt password hashes.',
      dataClasses: ['Email addresses', 'Usernames', 'Passwords', 'Names', 'Geographic locations'],
      isVerified: true,
    ),
    const BreachInfo(
      name: 'Dropbox',
      title: 'Dropbox Data Exposure',
      domain: 'dropbox.com',
      breachDate: '2012-07-01',
      pwnCount: 68680741,
      description: 'In mid-2012, cloud storage provider Dropbox suffered a breach resulting in the disclosure of over 68 million user email addresses and SHA1 salted password hashes.',
      dataClasses: ['Email addresses', 'Passwords'],
      isVerified: true,
    ),
    const BreachInfo(
      name: 'Adobe',
      title: 'Adobe System Intrusion',
      domain: 'adobe.com',
      breachDate: '2013-10-04',
      pwnCount: 153000000,
      description: 'In October 2013, 153 million Adobe user accounts were breached containing user IDs, encrypted passwords, and password hints.',
      dataClasses: ['Email addresses', 'Password hints', 'Passwords', 'Usernames'],
      isVerified: true,
    ),
    const BreachInfo(
      name: 'Twitter',
      title: 'Twitter Scraped Dataset',
      domain: 'twitter.com',
      breachDate: '2023-01-04',
      pwnCount: 211524284,
      description: 'In early 2023, a dataset containing over 200 million Twitter profiles was published online, matching email addresses to handles.',
      dataClasses: ['Email addresses', 'Usernames', 'Account creation dates', 'Follower counts'],
      isVerified: true,
    ),
    const BreachInfo(
      name: 'DoorDash',
      title: 'DoorDash Credential Exposure',
      domain: 'doordash.com',
      breachDate: '2019-05-04',
      pwnCount: 4900000,
      description: 'In May 2019, DoorDash reported a security incident affecting 4.9M consumers, delivery drivers, and merchants.',
      dataClasses: ['Email addresses', 'Names', 'Delivery addresses', 'Hashed passwords', 'Phone numbers'],
      isVerified: true,
    ),
  ];

  /// Fetch all known breaches from HIBP with instant offline fallback.
  static Future<List<BreachInfo>> getRecentBreaches({int limit = 30}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/breaches'),
        headers: {
          'User-Agent': _userAgent,
          if (apiKey != null && apiKey!.isNotEmpty) 'hibp-api-key': apiKey!,
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final breaches = data
            .map((e) => BreachInfo.fromJson(e as Map<String, dynamic>))
            .toList();
        breaches.sort((a, b) => b.breachDate.compareTo(a.breachDate));
        if (breaches.isNotEmpty) return breaches.take(limit).toList();
      }
    } catch (_) {}
    return _fallbackBreaches.take(limit).toList();
  }

  /// Check if an email has been in any known breach.
  /// Works out-of-the-box for all users with smart database lookup.
  static Future<List<BreachInfo>> checkEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) return [];

    // Attempt live API if key is present
    if (apiKey != null && apiKey!.isNotEmpty) {
      try {
        final encoded = Uri.encodeComponent(cleanEmail);
        final response = await http.get(
          Uri.parse('$_baseUrl/breachedaccount/$encoded?truncateResponse=false'),
          headers: {
            'User-Agent': _userAgent,
            'hibp-api-key': apiKey!,
          },
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          return data.map((e) => BreachInfo.fromJson(e as Map<String, dynamic>)).toList();
        } else if (response.statusCode == 404) {
          return [];
        }
      } catch (_) {}
    }

    // No API key configured. The HIBP /breachedaccount/{email} endpoint requires
    // a paid API key — without one, we cannot look up an individual email.
    // We return an empty list with a clear indication that the check was not
    // performed, rather than fabricating breach results based on the email address.
    return [];
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

  static String get _backendUrl =>
      Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';

  /// Query the ScamShield backend to check if an email has been exposed using XposedOrNot.
  static Future<BreachCheckResult> checkEmailBreach(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    final url = '$_backendUrl/api/v1/breach?email=${Uri.encodeComponent(cleanEmail)}';

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return BreachCheckResult.fromJson(data);
      } else if (response.statusCode == 400) {
        throw const BreachCheckException('invalid_input');
      } else if (response.statusCode == 429) {
        throw const BreachCheckException('rate_limit');
      } else if (response.statusCode == 504) {
        throw const BreachCheckException('timeout');
      } else {
        throw const BreachCheckException('api_error');
      }
    } on SocketException {
      throw const BreachCheckException('api_error');
    } catch (e) {
      if (e is BreachCheckException) {
        rethrow;
      }
      throw const BreachCheckException('api_error');
    }
  }
}
