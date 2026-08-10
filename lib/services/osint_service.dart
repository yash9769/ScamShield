import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Result of an OSINT threat-intelligence lookup (VirusTotal, Google Safe
/// Browsing, AbuseIPDB, URLhaus, ...).
///
/// [isMalicious] should only ever be `true` when a real provider positively
/// flagged the indicator. When a lookup could not be completed (no network,
/// provider down, check not available on this build), [available] is
/// `false` and [isMalicious] is always `false` — callers must check
/// [available] before treating a "not malicious" result as a clean bill of
/// health, otherwise an unreachable provider would silently look identical
/// to "verified safe".
class OsintResult {
  final String provider;
  final bool isMalicious;
  final bool available;
  final String details;

  OsintResult({
    required this.provider,
    required this.isMalicious,
    required this.details,
    this.available = true,
  });
}

/// Threat-intelligence lookups (VirusTotal / Google Safe Browsing / AbuseIPDB).
///
/// IMPORTANT — these are third-party checks that require secret API keys.
/// Those keys must never be embedded in the mobile app: anyone can decompile
/// an APK and extract hardcoded strings (this app's own APK scanner does
/// exactly that to other apps). A previous version of this file shipped
/// live-looking VirusTotal / Google Safe Browsing / AbuseIPDB keys directly
/// in this source file, which is a real secret-exposure vulnerability —
/// those keys have been removed.
///
/// The correct architecture is to proxy these lookups through the backend
/// (see backend/app/services/osint.py / osint_service.py), where keys live
/// only in server-side environment variables. The server's POST /scan
/// endpoint already returns a VirusTotal verdict for APK hashes. Standalone
/// URL/IP checks from the client are routed through [_backendBaseUrl] below;
/// if the backend is unreachable or has no key configured for a given
/// provider, the lookup is honestly reported as unavailable instead of
/// fabricating a "safe" or "malicious" result.
class OsintService {
  static String get _backendBaseUrl =>
      Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://localhost:8000';

  static const Duration _timeout = Duration(seconds: 6);

  /// Check a file hash (SHA-256, SHA-1, or MD5) against VirusTotal via the
  /// backend. For APK scans, prefer the hash verdict already included in the
  /// POST /scan response instead of calling this separately.
  static Future<OsintResult> checkHashVirusTotal(String hash) async {
    try {
      final url = Uri.parse('$_backendBaseUrl/osint/hash/$hash');
      final response = await http.get(url).timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final malicious = (data['malicious'] ?? 0) as int;
        return OsintResult(
          provider: 'VirusTotal',
          isMalicious: malicious > 0,
          details: (data['note'] as String?) ??
              '$malicious security vendor(s) flagged this file as malicious.',
        );
      }
    } catch (_) {
      // Backend unreachable — fall through to the honest "unavailable" result below.
    }
    return _unavailable('VirusTotal');
  }

  /// Check multiple URLs against Google Safe Browsing via the backend.
  ///
  /// If the backend is unreachable or has no Safe Browsing key configured, we
  /// do NOT simply report every URL as "unavailable" — instead each URL is
  /// screened against URLhaus, a keyless malware-URL database that is safe to
  /// query directly from the client. That way a missing Safe Browsing key
  /// degrades to a real secondary verdict rather than an empty "no URLs
  /// checked" result.
  static Future<List<OsintResult>> checkUrlsGoogleSafeBrowsing(List<String> urls) async {
    if (urls.isEmpty) return [];
    try {
      final endpoint = Uri.parse('$_backendBaseUrl/osint/urls');
      final response = await http
          .post(endpoint,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'urls': urls}))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List<dynamic>? ?? [];
        // The backend echoes a `checked` flag per URL. When it is false the
        // provider key is not configured server-side, so fall back to URLhaus.
        final allUnchecked = results.isNotEmpty &&
            results.every((r) => r['checked'] == false);
        if (!allUnchecked && results.isNotEmpty) {
          return results.map((r) {
            final isMalicious = r['malicious'] == true;
            return OsintResult(
              provider: 'Google Safe Browsing',
              isMalicious: isMalicious,
              details: isMalicious
                  ? 'Flagged as dangerous by Google Safe Browsing.'
                  : (r['note'] as String? ?? 'No threats found.'),
            );
          }).toList();
        }
      }
    } catch (_) {
      // Fall through to the keyless URLhaus fallback below.
    }
    return _urlhausFallback(urls);
  }

  /// Screen each URL against the keyless URLhaus database as a fallback when
  /// Google Safe Browsing could not be reached or is not configured.
  static Future<List<OsintResult>> _urlhausFallback(List<String> urls) async {
    return Future.wait(urls.map((u) async {
      final r = await checkUrlhaus(u);
      if (!r.available) return r;
      return OsintResult(
        provider: 'URLhaus (fallback)',
        isMalicious: r.isMalicious,
        details: r.isMalicious
            ? 'Listed in the URLhaus malware-URL database.'
            : 'Not listed in URLhaus. Google Safe Browsing was unavailable, so '
                'this is a secondary check, not a full clean bill of health.',
      );
    }));
  }

  /// Check an IP address against AbuseIPDB via the backend.
  static Future<OsintResult> checkIpAbuseIPDB(String ip) async {
    try {
      final url = Uri.parse('$_backendBaseUrl/osint/ip/$ip');
      final response = await http.get(url).timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final score = data['abuseConfidenceScore'] as int? ?? 0;
        final isMalicious = score > 50;
        return OsintResult(
          provider: 'AbuseIPDB',
          isMalicious: isMalicious,
          details: isMalicious
              ? 'Abuse confidence score: $score%'
              : (data['note'] as String? ?? 'No significant abuse reports.'),
        );
      }
    } catch (_) {
      // Fall through
    }
    return _unavailable('AbuseIPDB');
  }

  /// Check URL against URLhaus. No API key required, so this is safe to call
  /// directly from the client.
  static Future<OsintResult> checkUrlhaus(String urlToCheck) async {
    try {
      final endpoint = Uri.parse('https://urlhaus-api.abuse.ch/v1/url/');
      final response =
          await http.post(endpoint, body: {'url': urlToCheck}).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final status = data['query_status'];
        if (status == 'ok') {
          return OsintResult(
            provider: 'URLhaus',
            isMalicious: true,
            details: 'URL is listed in the URLhaus malware database.',
          );
        } else if (status == 'no_results') {
          return OsintResult(
            provider: 'URLhaus',
            isMalicious: false,
            details: 'No results found.',
          );
        }
      }
    } catch (_) {
      // Fall through
    }
    return _unavailable('URLhaus');
  }

  static OsintResult _unavailable(String provider) {
    return OsintResult(
      provider: provider,
      isMalicious: false,
      available: false,
      details: 'Could not reach $provider (backend offline or not configured). '
          'This result is unverified — it is NOT a confirmation of safety.',
    );
  }
}
