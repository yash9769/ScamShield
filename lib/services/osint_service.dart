import 'dart:convert';
import 'package:http/http.dart' as http;

class OsintResult {
  final String provider;
  final bool isMalicious;
  final String details;

  OsintResult({
    required this.provider,
    required this.isMalicious,
    required this.details,
  });
}

class OsintService {
  static const String _vtApiKey = String.fromEnvironment('VIRUSTOTAL_API_KEY', defaultValue: '');
  static const String _gsbApiKey = String.fromEnvironment('GOOGLE_SAFE_BROWSING_KEY', defaultValue: '');
  static const String _abuseIpdbApiKey = String.fromEnvironment('ABUSEIPDB_API_KEY', defaultValue: '');

  /// Check a file hash (SHA-256, SHA-1, or MD5) against VirusTotal.
  static Future<OsintResult> checkHashVirusTotal(String hash) async {
    if (_vtApiKey.isEmpty) {
      return _mockCheckHash(hash, 'VirusTotal');
    }

    try {
      final url = Uri.parse('https://www.virustotal.com/api/v3/files/$hash');
      final response = await http.get(url, headers: {'x-apikey': _vtApiKey});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final stats = data['data']?['attributes']?['last_analysis_stats'];
        if (stats != null) {
          final malicious = (stats['malicious'] ?? 0) as int;
          return OsintResult(
            provider: 'VirusTotal',
            isMalicious: malicious > 0,
            details: '$malicious security vendors flagged this file as malicious.',
          );
        }
      } else if (response.statusCode == 404) {
        return OsintResult(
          provider: 'VirusTotal',
          isMalicious: false,
          details: 'File hash not found in VirusTotal database.',
        );
      }
    } catch (e) {
      // Fallback on error
    }
    return _mockCheckHash(hash, 'VirusTotal (Fallback)');
  }

  /// Check multiple URLs against Google Safe Browsing.
  static Future<List<OsintResult>> checkUrlsGoogleSafeBrowsing(List<String> urls) async {
    if (_gsbApiKey.isEmpty || urls.isEmpty) {
      return urls.map((url) => _mockCheckUrl(url, 'Google Safe Browsing')).toList();
    }

    try {
      final endpoint = Uri.parse('https://safebrowsing.googleapis.com/v4/threatMatches:find?key=$_gsbApiKey');
      final body = {
        "client": {
          "clientId": "scamshield",
          "clientVersion": "1.0.0"
        },
        "threatInfo": {
          "threatTypes": ["MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE", "POTENTIALLY_HARMFUL_APPLICATION"],
          "platformTypes": ["ANY_PLATFORM"],
          "threatEntryTypes": ["URL"],
          "threatEntries": urls.map((u) => {"url": u}).toList()
        }
      };

      final response = await http.post(
        endpoint,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final matches = data['matches'] as List<dynamic>?;
        
        final maliciousUrls = <String>{};
        if (matches != null) {
          for (final match in matches) {
            final url = match['threat']['url'] as String?;
            if (url != null) maliciousUrls.add(url);
          }
        }

        return urls.map((url) {
          final isMalicious = maliciousUrls.contains(url);
          return OsintResult(
            provider: 'Google Safe Browsing',
            isMalicious: isMalicious,
            details: isMalicious ? 'Flagged as dangerous by Google Safe Browsing.' : 'Safe',
          );
        }).toList();
      }
    } catch (e) {
      // Fallback
    }

    return urls.map((url) => _mockCheckUrl(url, 'Google Safe Browsing (Fallback)')).toList();
  }

  /// Check an IP address against AbuseIPDB.
  static Future<OsintResult> checkIpAbuseIPDB(String ip) async {
    if (_abuseIpdbApiKey.isEmpty) {
      return _mockCheckIp(ip, 'AbuseIPDB');
    }

    try {
      final url = Uri.parse('https://api.abuseipdb.com/api/v2/check?ipAddress=$ip&maxAgeInDays=90');
      final response = await http.get(url, headers: {
        'Accept': 'application/json',
        'Key': _abuseIpdbApiKey,
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final score = data['data']?['abuseConfidenceScore'] as int? ?? 0;
        final isMalicious = score > 50; // threshold
        return OsintResult(
          provider: 'AbuseIPDB',
          isMalicious: isMalicious,
          details: isMalicious ? 'Abuse confidence score: $score%' : 'No significant abuse reports.',
        );
      }
    } catch (e) {
      // Fallback
    }
    return _mockCheckIp(ip, 'AbuseIPDB (Fallback)');
  }

  /// Check URL against URLhaus (No API key needed).
  static Future<OsintResult> checkUrlhaus(String urlToCheck) async {
    try {
      final endpoint = Uri.parse('https://urlhaus-api.abuse.ch/v1/url/');
      final response = await http.post(
        endpoint,
        body: {'url': urlToCheck},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final status = data['query_status'];
        if (status == 'ok') {
          return OsintResult(
            provider: 'URLhaus',
            isMalicious: true,
            details: 'URL is listed in URLhaus malware database.',
          );
        } else if (status == 'no_results') {
          return OsintResult(
            provider: 'URLhaus',
            isMalicious: false,
            details: 'No results found.',
          );
        }
      }
    } catch (e) {
      // Fallback
    }
    return _mockCheckUrl(urlToCheck, 'URLhaus (Fallback)');
  }

  // --- MOCK PROVIDERS ---

  static OsintResult _mockCheckHash(String hash, String provider) {
    final isMalicious = hash.startsWith('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'); // empty SHA256 just for testing
    return OsintResult(
      provider: provider,
      isMalicious: isMalicious,
      details: isMalicious ? 'Mock: Flagged as malicious malware signature.' : 'Mock: Hash appears safe.',
    );
  }

  static OsintResult _mockCheckUrl(String url, String provider) {
    final lower = url.toLowerCase();
    final isMalicious = lower.contains('free-money') || lower.contains('bit.ly/scam');
    return OsintResult(
      provider: provider,
      isMalicious: isMalicious,
      details: isMalicious ? 'Mock: Known malicious domain.' : 'Mock: URL appears safe.',
    );
  }

  static OsintResult _mockCheckIp(String ip, String provider) {
    final isMalicious = ip == '192.168.1.99'; // random trigger
    return OsintResult(
      provider: provider,
      isMalicious: isMalicious,
      details: isMalicious ? 'Mock: High abuse confidence.' : 'Mock: Clean IP.',
    );
  }
}
