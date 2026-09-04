import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Result of an OSINT threat-intelligence lookup (VirusTotal, Google Safe
/// Browsing, AbuseIPDB, Domain Intelligence, ...).
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
  static String get _backendBaseUrl {
    const customUrl = String.fromEnvironment('SCAMSHIELD_BACKEND_URL');
    if (customUrl.isNotEmpty) return customUrl;
    return Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
  }

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
        if (data['checked'] == false) {
          return _unavailable('VirusTotal');
        }
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
  /// do NOT simply report every URL as "unavailable" — instead each URL's
  /// domain is screened via [checkDomainIntel] (Certificate Transparency +
  /// RDAP registration age), which is free/keyless and always available.
  /// That way a missing Safe Browsing key degrades to a real secondary
  /// verdict rather than an empty "no URLs checked" result.
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
        // provider key is not configured server-side, so fall back to
        // domain-intelligence below.
        final allUnchecked = results.isNotEmpty &&
            results.every((r) => r['checked'] == false);
        if (!allUnchecked && results.isNotEmpty) {
          return results.map((r) {
            final isMalicious = r['malicious'] == true;
            final checked = r['checked'] == true;
            return OsintResult(
              provider: 'Google Safe Browsing',
              isMalicious: isMalicious,
              available: checked,
              details: isMalicious
                  ? 'Flagged as dangerous by Google Safe Browsing.'
                  : (r['note'] as String? ?? 'No threats found.'),
            );
          }).toList();
        }
      }
    } catch (_) {
      // Fall through to the keyless domain-intelligence fallback below.
    }
    return Future.wait(urls.map(checkDomainIntel));
  }

  /// Check an IP address against AbuseIPDB via the backend.
  static Future<OsintResult> checkIpAbuseIPDB(String ip) async {
    try {
      final url = Uri.parse('$_backendBaseUrl/osint/ip/$ip');
      final response = await http.get(url).timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['checked'] == false) {
          return _unavailable('AbuseIPDB');
        }
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

  /// Domain-trust check via the backend's /osint/domain endpoint
  /// (Certificate Transparency logs + RDAP registration age — both free,
  /// no API key, always available). [urlOrHost] may be a full URL or a bare
  /// hostname.
  ///
  /// This replaces a previous direct-from-client call to
  /// `urlhaus-api.abuse.ch`. That endpoint has since been put behind
  /// abuse.ch's bot-verification gate (confirmed by a live request that
  /// returned a "verify-ua" redirect instead of API JSON) and no longer
  /// works for a plain server-to-server call; abuse.ch's *replacement* API
  /// also now requires a registered Auth-Key. Rather than ship a call that
  /// silently fails, or attempt to bypass the bot-detection (which we won't
  /// do), this uses two sources that are genuinely keyless today.
  static Future<OsintResult> checkDomainIntel(String urlOrHost) async {
    final host = _extractHost(urlOrHost);
    if (host == null) return _unavailable('Domain Intelligence');
    try {
      final endpoint = Uri.parse('$_backendBaseUrl/osint/domain/$host');
      final response = await http.get(endpoint).timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isNew = data['newly_registered_or_unproven'] == true;
        final certNote = data['certificate_transparency']?['note'] as String? ?? '';
        final rdapNote = data['rdap']?['note'] as String? ?? '';
        return OsintResult(
          provider: 'Domain Intelligence',
          isMalicious: isNew,
          details: isNew
              ? 'Newly-registered or certificate-history-free domain: $certNote $rdapNote'.trim()
              : 'Established domain: $certNote $rdapNote'.trim(),
        );
      }
    } catch (_) {
      // Fall through
    }
    return _unavailable('Domain Intelligence');
  }

  static String? _extractHost(String urlOrHost) {
    try {
      final withScheme = urlOrHost.contains('://') ? urlOrHost : 'http://$urlOrHost';
      final host = Uri.parse(withScheme).host;
      return host.isEmpty ? null : host;
    } catch (_) {
      return null;
    }
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
