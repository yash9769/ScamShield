import 'package:crypto/crypto.dart';
import 'dart:convert';

/// On-device clipboard pre-filter.
///
/// This class NEVER sends clipboard contents anywhere. It runs a set of
/// heuristic regexes to decide whether a copied string is worth an explicit
/// backend scan. All network traffic must be triggered by an explicit user
/// action (the "SCAN NOW" button), never by copy events alone.
///
/// Threat hierarchy (highest severity first):
///   ipLiteralHost > otp > upiVpa > shortUrl > nonHttpsUrl > url
enum ClipboardThreat { url, shortUrl, nonHttpsUrl, ipLiteralHost, upiVpa, otp }

class ClipboardAnalysis {
  final String text;
  final Set<ClipboardThreat> threats;
  final List<String> urls;
  final List<String> ipHosts;
  final String? upiVpa;
  final List<String> otpCodes;

  const ClipboardAnalysis({
    required this.text,
    required this.threats,
    required this.urls,
    required this.ipHosts,
    required this.upiVpa,
    required this.otpCodes,
  });

  bool get isThreat => threats.isNotEmpty;

  /// Highest-severity threat, used to pick the snackbar message.
  ClipboardThreat? get topThreat {
    const order = [
      ClipboardThreat.ipLiteralHost,
      ClipboardThreat.otp,
      ClipboardThreat.upiVpa,
      ClipboardThreat.shortUrl,
      ClipboardThreat.nonHttpsUrl,
      ClipboardThreat.url,
    ];
    for (final t in order) {
      if (threats.contains(t)) return t;
    }
    return null;
  }

  String get label {
    switch (topThreat) {
      case ClipboardThreat.ipLiteralHost:
        return 'Link points at a raw IP address';
      case ClipboardThreat.otp:
        return 'One-time password (OTP) detected';
      case ClipboardThreat.upiVpa:
        return 'UPI payment address detected';
      case ClipboardThreat.shortUrl:
        return 'Shortened link detected';
      case ClipboardThreat.nonHttpsUrl:
        return 'Insecure HTTP link detected';
      case ClipboardThreat.url:
        return 'Link detected in clipboard';
      case null:
        return 'No threat indicators';
    }
  }

  String get description {
    switch (topThreat) {
      case ClipboardThreat.ipLiteralHost:
        return 'Scammers host fake payment pages on raw IPs because they are '
            'cheap to rotate and skip domain reputation checks.';
      case ClipboardThreat.otp:
        return 'Never share OTPs or verification codes — no bank or service '
            'asks you to read them back.';
      case ClipboardThreat.upiVpa:
        return 'A UPI payment address is in your clipboard — scammers use '
            'these to collect payments in OTP/refund frauds. '
            'Verify the VPA with your bank before sending any money.';
      case ClipboardThreat.shortUrl:
        return 'Shortened links hide their real destination. Expand it and '
            'verify the host before tapping.';
      case ClipboardThreat.nonHttpsUrl:
        return 'This link uses plain HTTP (not HTTPS). Legitimate financial '
            'and banking sites always use HTTPS. Avoid sharing sensitive '
            'information over an insecure connection.';
      case ClipboardThreat.url:
        return 'Copied links deserve a scan — always verify the real hostname '
            'before opening.';
      case null:
        return '';
    }
  }

  /// Stable dedup key: two analyses of the same normalised text collide.
  String get contentHash => sha256.convert(utf8.encode(_normalise(text))).toString();

  static String _normalise(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');
}

class ClipboardAnalyzer {
  /// Matches any URL (http or https) for general detection.
  static final RegExp _urlPattern =
      RegExp(r'https?://[^\s<>\])]+', caseSensitive: false);

  /// Matches http:// only (non-HTTPS) for the insecure-link threat.
  static final RegExp _httpOnlyPattern =
      RegExp(r'\bhttp://[^\s<>\])]+', caseSensitive: false);
  static final RegExp _shortUrlPattern = RegExp(
    r'https?://'
    r'(?:[a-z0-9-]+\.)*'
    r'(?:bit\.ly|t\.co|goo\.gl|tinyurl\.com|is\.gd|buff\.ly|rb\.gy|'
    r'shorte\.st|cutt\.ly|surl\.li|lnkd\.in|ow\.ly|rebrand\.ly|tiny\.cc|'
    r'qrco\.de|shorturl\.at|1\.tk|smw\.app|v\.gd|tiny\.link|x\.co|2\.ly|'
    r'bud\.ly|s2r\.co|shorte\.st|bcvc\.in|watchshort\.xyz)'
    r'(?:/[^\s<>\])]*)?',
    caseSensitive: false,
  );

  static final RegExp _ipLiteralPattern = RegExp(
    r'https?://\d{1,3}(?:\.\d{1,3}){3}(?::\d{1,5})?(?:/[^\s<>\])]*)?',
    caseSensitive: false,
  );

  static final RegExp _upiVpaPattern = RegExp(
    r'\b[a-zA-Z0-9][a-zA-Z0-9._-]{2,29}@[a-zA-Z0-9]{2,12}\b(?!\.[a-zA-Z]{2,})',
  );

  static final RegExp _otpKeywordPattern = RegExp(
    r'\b(?:otp|one[- ]time password|verification code|secure code|'
    r'authenticator code|do not share this code)\b',
    caseSensitive: false,
  );

  static final RegExp _digitCodePattern = RegExp(r'\b\d{4,6}\b');

  static ClipboardAnalysis analyze(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) {
      return const ClipboardAnalysis(
        text: '',
        threats: {},
        urls: [],
        ipHosts: [],
        upiVpa: null,
        otpCodes: [],
      );
    }

    final threats = <ClipboardThreat>{};
    final urls = <String>[];
    final ipHosts = <String>[];
    String? upiVpa;
    final otpCodes = <String>[];

    // URLs (including short URLs and raw-IP hosts, which are stricter subsets).
    for (final m in _urlPattern.allMatches(text)) {
      final url = m.group(0)!;
      if (!urls.contains(url)) urls.add(url);
    }
    if (urls.isNotEmpty) threats.add(ClipboardThreat.url);

    // Insecure HTTP links (http:// but not https://).
    final httpOnlyMatches = _httpOnlyPattern.allMatches(text).toList();
    if (httpOnlyMatches.isNotEmpty) {
      // Only flag as nonHttpsUrl if the host is not localhost/emulator
      // (dev/debug URLs are not threats).
      final hasNonLocalHttp = httpOnlyMatches.any((m) {
        final url = m.group(0) ?? '';
        return !url.contains('localhost') &&
            !url.contains('127.0.0.1') &&
            !url.contains('10.0.2.2');
      });
      if (hasNonLocalHttp) threats.add(ClipboardThreat.nonHttpsUrl);
    }
    for (final m in _shortUrlPattern.allMatches(text)) {
      if (m.group(0) != null) {
        threats.add(ClipboardThreat.shortUrl);
        break;
      }
    }

    for (final m in _ipLiteralPattern.allMatches(text)) {
      final host = m.group(0)!;
      if (!ipHosts.contains(host)) ipHosts.add(host);
    }
    if (ipHosts.isNotEmpty) threats.add(ClipboardThreat.ipLiteralHost);

    // UPI VPA (a handle@banktag without a dotted email TLD).
    final vpaMatch = _upiVpaPattern.firstMatch(text);
    if (vpaMatch != null) {
      upiVpa = vpaMatch.group(0);
      threats.add(ClipboardThreat.upiVpa);
    }

    // OTP only counts when a verification keyword is actually present, so
    // ordinary 4-6 digit numbers in normal text do not trigger.
    if (_otpKeywordPattern.hasMatch(text)) {
      for (final m in _digitCodePattern.allMatches(text)) {
        otpCodes.add(m.group(0)!);
      }
      threats.add(ClipboardThreat.otp);
    }

    return ClipboardAnalysis(
      text: text,
      threats: threats,
      urls: urls,
      ipHosts: ipHosts,
      upiVpa: upiVpa,
      otpCodes: otpCodes,
    );
  }
}
