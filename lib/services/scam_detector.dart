// lib/services/scam_detector.dart
import 'apk_analyzer_service.dart';
import 'osint_service.dart';

/// The result of a scam analysis.
enum ScamClassification { safe, suspicious, scam }

/// A single detected pattern / reason shown to the user.
class DetectionReason {
  final String label;
  final String description;
  final int scoreContribution;
  final IconCategory iconCategory;

  const DetectionReason({
    required this.label,
    required this.description,
    required this.scoreContribution,
    required this.iconCategory,
  });
}

enum IconCategory { financial, link, urgency, suspicious, manipulation, safe }

/// The full analysis result returned by [ScamDetector.analyze].
class AnalysisResult {
  final ScamClassification classification;
  final int riskScore; // 0–100
  final List<DetectionReason> reasons;
  final String summary;
  final bool aiPowered;

  const AnalysisResult({
    required this.classification,
    required this.riskScore,
    required this.reasons,
    required this.summary,
    this.aiPowered = false, // false = local heuristic, true = Gemini AI
  });
}

/// Pure-Dart, offline scam detection engine using keyword + regex patterns.
class ScamDetector {
  // ── Financial keywords ──────────────────────────────────────────────────
  static const _financialKeywords = [
    'bank',
    'account',
    'otp',
    'pin',
    'password',
    'credit card',
    'debit card',
    'transaction',
    'transfer',
    'wire',
    'payment',
    'wallet',
    'kyc',
    'verify your account',
    'aadhaar',
    'pan card',
    'upi',
    'ifsc',
  ];

  // ── Suspicious prize / lottery words ────────────────────────────────────
  static const _prizeKeywords = [
    'win',
    'winner',
    'lottery',
    'prize',
    'reward',
    'congratulations',
    'selected',
    'gift card',
    'voucher',
    'free money',
    'jackpot',
    'lucky draw',
    'you won',
    'kbc',
  ];

  // ── Urgency / pressure words ─────────────────────────────────────────────
  static const _urgencyKeywords = [
    'urgent',
    'immediately',
    'act now',
    'limited time',
    'expires',
    'final notice',
    'last chance',
    'within 24 hours',
    'suspended',
    'blocked',
    'terminated',
    'action required',
    'verify now',
    'confirm now',
    'do not ignore',
  ];

  // ── Psychological manipulation words ─────────────────────────────────────
  static const _manipulationKeywords = [
    'click here',
    'click now',
    'tap here',
    // Not "do not share" / "never share": that is the warning every genuine
    // bank OTP SMS carries, and counting it flagged real OTPs as suspicious.
    'call us immediately',
    'call now',
    'trust us',
    'guaranteed',
    'risk free',
    'no cost',
    'secret',
    'confidential',
  ];

  // ── Suspicious action words ───────────────────────────────────────────────
  static const _suspiciousKeywords = [
    'click',
    'download',
    'install',
    'open attachment',
    'unsubscribe',
    'confirm your details',
    'update your information',
    'verify your identity',
    'via the link',
    'link below',
    'following link',
  ];

  // ── Regex patterns ────────────────────────────────────────────────────────
  /// Detects any http / https URL.
  static final _urlRegex = RegExp(r'https?://[^\s]+', caseSensitive: false);

  /// Detects shortened / obfuscated URLs commonly used in phishing.
  static final _shortUrlRegex = RegExp(
    r'\b(bit\.ly|tinyurl\.com|goo\.gl|t\.co|ow\.ly|buff\.ly|is\.gd|rb\.gy|cutt\.ly|tiny\.cc|adf\.ly)[^\s]*',
    caseSensitive: false,
  );

  /// Detects phone numbers that could be used for vishing.
  static final _phoneRegex = RegExp(r'(\+?\d[\d\s\-().]{7,}\d)');

  /// Detects patterns like "Your OTP is 123456" or "OTP: 654321".
  static final _otpPatternRegex = RegExp(
    r'otp[\s:is]*\d{4,8}',
    caseSensitive: false,
  );

  /// Asking for a code, as opposed to delivering one. "Share OTP 482913 with
  /// our agent" is a request; "Your OTP is 551203. Do not share it" is a bank
  /// delivering a code and warning you, and must not score as a scam.
  static final _otpRequestRegex = RegExp(
    r'\b(share|send|tell|forward|give|provide|read\s+out|reply\s+with)\b[^.]{0,40}\b(otp|code|pin)\b'
    r'|\b(otp|code)\b[^.]{0,30}\b(to|with)\s+(our|the|this)\s+(agent|executive|officer|representative|number)\b',
    caseSensitive: false,
  );
  static final _negationRegex = RegExp(
    r"\b(never|not|don't|dont|do\s+not)\s*$",
    caseSensitive: false,
  );

  /// Threats to cut a service off: the electricity / SIM / gas bill scam.
  static final _disconnectionRegex = RegExp(
    r'\b(electricity|power|light|gas|water|connection|sim|mobile number|number|service)\b[^.]{0,50}'
    r'\b(disconnect\w*|cut\s+off|deactivat\w*|be\s+blocked|suspend\w*)\b'
    r'|\b(disconnect\w*|deactivat\w*)\b[^.]{0,40}\b(tonight|today|within)\b',
    caseSensitive: false,
  );

  /// Money demanded up front to release a prize, loan, parcel or job.
  static final _advanceFeeRegex = RegExp(
    r'\b(processing|registration|clearance|release|delivery|activation|verification|customs)\s+(fee|fees|charge|charges)\b'
    r'|\b(pay|deposit|transfer|send)\b[^.]{0,30}\b(fee|charges?|tax)\b[^.]{0,30}\b(to\s+)?(claim|release|receive|activate|unlock)\b',
    caseSensitive: false,
  );

  /// Whole-word matches only: a substring test let "pin" fire inside
  /// "shipping" and "win" inside "window".
  static List<String> _hits(List<String> keywords, String lower) => keywords
      .where(
        (k) => RegExp(
          '(?<![a-z0-9])${RegExp.escape(k)}(?![a-z0-9])',
        ).hasMatch(lower),
      )
      .toList();

  /// True when [text] asks for a code, ignoring negated forms like "never
  /// share this code" that genuine OTP messages use as a warning.
  static bool asksForOtp(String text) {
    for (final m in _otpRequestRegex.allMatches(text)) {
      final before = text.substring(m.start < 12 ? 0 : m.start - 12, m.start);
      if (!_negationRegex.hasMatch(before)) return true;
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  /// The main entry point. Returns an [AnalysisResult] for [text].
  // ─────────────────────────────────────────────────────────────────────────
  static AnalysisResult analyze(String text) {
    if (text.trim().isEmpty) {
      return const AnalysisResult(
        classification: ScamClassification.safe,
        riskScore: 0,
        reasons: [],
        summary: 'No content provided.',
      );
    }

    final lower = text.toLowerCase();
    final reasons = <DetectionReason>[];
    int score = 0;

    // ── 1. Financial keywords ─────────────────────────────────────────────
    final financialHits = _hits(_financialKeywords, lower);
    if (financialHits.isNotEmpty) {
      final pts = (financialHits.length * 12).clamp(0, 35);
      score += pts;
      reasons.add(
        DetectionReason(
          label: 'Financial Keywords Detected',
          description:
              'Found sensitive financial terms: ${financialHits.take(3).map((k) => '"$k"').join(', ')}${financialHits.length > 3 ? ', and ${financialHits.length - 3} more' : ''}.',
          scoreContribution: pts,
          iconCategory: IconCategory.financial,
        ),
      );
    }

    // ── 2. Prize / lottery keywords ───────────────────────────────────────
    final prizeHits = _hits(_prizeKeywords, lower);
    if (prizeHits.isNotEmpty) {
      final pts = (prizeHits.length * 14).clamp(0, 30);
      score += pts;
      reasons.add(
        DetectionReason(
          label: 'Prize / Lottery Language',
          description:
              'Detected classic lottery-scam language: ${prizeHits.take(3).map((k) => '"$k"').join(', ')}. Legitimate organisations never announce prizes via SMS.',
          scoreContribution: pts,
          iconCategory: IconCategory.suspicious,
        ),
      );
    }

    // ── 3. Urgency keywords ───────────────────────────────────────────────
    final urgencyHits = _hits(_urgencyKeywords, lower);
    if (urgencyHits.isNotEmpty) {
      final pts = (urgencyHits.length * 10).clamp(0, 25);
      score += pts;
      reasons.add(
        DetectionReason(
          label: 'Urgency & Pressure Tactics',
          description:
              'Detected ${urgencyHits.length} urgency trigger(s): ${urgencyHits.take(3).map((k) => '"$k"').join(', ')}. Creating pressure is a core scam technique.',
          scoreContribution: pts,
          iconCategory: IconCategory.urgency,
        ),
      );
    }

    // ── 4. URL detection ─────────────────────────────────────────────────
    // Shortened links are checked on their own, not only inside http(s)://
    // matches: SMS phishing usually writes "bit.ly/xyz" with no scheme.
    final urlMatches = _urlRegex.allMatches(text);
    final shortMatches = _shortUrlRegex.allMatches(text);
    final hasLink = urlMatches.isNotEmpty || shortMatches.isNotEmpty;
    if (shortMatches.isNotEmpty) {
      const urlPts = 25;
      score += urlPts;
      reasons.add(
        DetectionReason(
          label: 'Shortened / Obfuscated URL',
          description:
              'Found ${shortMatches.length} shortened URL(s). Scammers use services like bit.ly to hide the real destination of malicious links.',
          scoreContribution: urlPts,
          iconCategory: IconCategory.link,
        ),
      );
    } else if (urlMatches.isNotEmpty) {
      const urlPts = 10;
      score += urlPts;
      reasons.add(
        DetectionReason(
          label: 'URL / Link Detected',
          description:
              'Found ${urlMatches.length} link(s) in the message. Verify any link before clicking, especially if you were not expecting it.',
          scoreContribution: urlPts,
          iconCategory: IconCategory.link,
        ),
      );
    }

    // ── 5. OTP request pattern ───────────────────────────────────────────
    if (asksForOtp(text)) {
      const pts = 30;
      score += pts;
      reasons.add(
        DetectionReason(
          label: 'OTP / Code Sharing Request',
          description:
              'The message asks you to share an OTP or code. No legitimate service will ever ask you to share your OTP.',
          scoreContribution: pts,
          iconCategory: IconCategory.financial,
        ),
      );
    } else if (_otpPatternRegex.hasMatch(lower) && hasLink) {
      // A code delivered alongside a link. A code delivered on its own, with
      // no request, is the normal shape of a genuine OTP: no points.
      const pts = 15;
      score += pts;
      reasons.add(
        DetectionReason(
          label: 'OTP Alongside a Link',
          description:
              'An OTP arrives together with a link. Never enter a code on a page reached from a message.',
          scoreContribution: pts,
          iconCategory: IconCategory.financial,
        ),
      );
    }

    // ── 5b. Service disconnection threat ─────────────────────────────────
    if (_disconnectionRegex.hasMatch(text)) {
      const pts = 30;
      score += pts;
      reasons.add(
        DetectionReason(
          label: 'Service Disconnection Threat',
          description:
              "Threatens to cut off your electricity, SIM or another service unless you act now. Utilities don't disconnect over SMS; check with the provider's official number.",
          scoreContribution: pts,
          iconCategory: IconCategory.urgency,
        ),
      );
    }

    // ── 5c. Upfront fee demand ───────────────────────────────────────────
    if (_advanceFeeRegex.hasMatch(text)) {
      const pts = 30;
      score += pts;
      reasons.add(
        DetectionReason(
          label: 'Upfront Fee Demand',
          description:
              'Asks for a fee before you can receive a prize, loan, parcel or job. Real prizes and refunds never require paying first.',
          scoreContribution: pts,
          iconCategory: IconCategory.financial,
        ),
      );
    }

    // ── 6. Manipulation keywords ─────────────────────────────────────────
    final manipHits = _hits(_manipulationKeywords, lower);
    if (manipHits.isNotEmpty) {
      final pts = (manipHits.length * 8).clamp(0, 20);
      score += pts;
      reasons.add(
        DetectionReason(
          label: 'Psychological Manipulation',
          description:
              'Detected manipulative language: ${manipHits.take(3).map((k) => '"$k"').join(', ')}. Scammers use these phrases to bypass critical thinking.',
          scoreContribution: pts,
          iconCategory: IconCategory.manipulation,
        ),
      );
    }

    // ── 7. Generic suspicious action words ───────────────────────────────
    final suspHits = _hits(_suspiciousKeywords, lower);
    if (suspHits.isNotEmpty) {
      final pts = (suspHits.length * 5).clamp(0, 15);
      score += pts;
      reasons.add(
        DetectionReason(
          label: 'Suspicious Action Words',
          description:
              'Found action-driving language: ${suspHits.take(3).map((k) => '"$k"').join(', ')}. Be cautious of messages asking you to click, download, or install anything.',
          scoreContribution: pts,
          iconCategory: IconCategory.suspicious,
        ),
      );
    }

    // ── 8. Phone number in message ───────────────────────────────────────
    final phoneMatches = _phoneRegex.allMatches(text);
    if (phoneMatches.isNotEmpty && reasons.isNotEmpty) {
      // Only flag phones as suspicious when combined with other signals
      const pts = 5;
      score += pts;
      reasons.add(
        DetectionReason(
          label: 'Embedded Phone Number',
          description:
              'Found ${phoneMatches.length} phone number(s). Scammers often embed call-back numbers to establish direct voice contact with victims.',
          scoreContribution: pts,
          iconCategory: IconCategory.suspicious,
        ),
      );
    }

    // ── Clamp score ────────────────────────────────────────────────────────
    score = score.clamp(0, 100);

    // ── Classify ──────────────────────────────────────────────────────────
    final ScamClassification classification;
    final String summary;

    if (score == 0) {
      classification = ScamClassification.safe;
      summary =
          'No suspicious patterns were detected. This message appears safe.';
    } else if (score < 30) {
      classification = ScamClassification.safe;
      summary =
          'A few low-risk signals were found. Exercise normal caution but no immediate threat detected.';
    } else if (score < 65) {
      classification = ScamClassification.suspicious;
      summary =
          'Multiple warning signals detected. Do NOT share personal or financial information. Verify the sender independently.';
    } else {
      classification = ScamClassification.scam;
      summary =
          'High-confidence scam detected! This message uses classic social engineering tactics. Do not click any links, call any numbers, or share any data.';
    }

    // ── If no reasons but score > 0, add safe indicator ──────────────────
    if (reasons.isEmpty) {
      reasons.add(
        const DetectionReason(
          label: 'No Threats Detected',
          description: 'This message does not contain known scam patterns.',
          scoreContribution: 0,
          iconCategory: IconCategory.safe,
        ),
      );
    }

    return AnalysisResult(
      classification: classification,
      riskScore: score,
      reasons: reasons,
      summary: summary,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  /// Analyzes an APK based on its static extraction and OSINT results.
  // ─────────────────────────────────────────────────────────────────────────
  static AnalysisResult analyzeApk(
    ApkAnalysisResult apk,
    List<OsintResult> osintResults,
  ) {
    int score = 0;
    final reasons = <DetectionReason>[];

    // 1. Dangerous Permissions Analysis
    final dangerousPermissions = <String, int>{
      'READ_SMS': 25,
      'RECEIVE_SMS': 25,
      'SYSTEM_ALERT_WINDOW': 30, // Overlay attacks
      'BIND_ACCESSIBILITY_SERVICE': 35, // Accessibility attacks
      'READ_CONTACTS': 10,
      'SEND_SMS': 20,
      'CALL_PHONE': 15,
      'REQUEST_INSTALL_PACKAGES': 20,
    };

    int permissionScore = 0;
    final foundDangerous = <String>[];
    for (final perm in apk.permissions) {
      if (dangerousPermissions.containsKey(perm)) {
        permissionScore += dangerousPermissions[perm]!;
        foundDangerous.add(perm);
      }
    }

    if (foundDangerous.isNotEmpty) {
      score += permissionScore;
      reasons.add(
        DetectionReason(
          label: 'Dangerous Permissions',
          description:
              'App requests: ${foundDangerous.join(', ')}. This combination is highly sensitive and often abused by malware.',
          scoreContribution: permissionScore,
          iconCategory: IconCategory.suspicious,
        ),
      );
    }

    // 2. OSINT Analysis
    int osintScore = 0;
    final maliciousOsint = osintResults.where((r) => r.isMalicious).toList();
    if (maliciousOsint.isNotEmpty) {
      for (final result in maliciousOsint) {
        osintScore += 40; // Heavy penalty for flagged OSINT
        reasons.add(
          DetectionReason(
            label: 'OSINT Blacklist (${result.provider})',
            description: result.details,
            scoreContribution: 40,
            iconCategory: IconCategory
                .suspicious, // mapped to manipulation/suspicious later
          ),
        );
      }
      score += osintScore;
    }

    // 3. Secrets / URLs
    // Basic heuristic: check if urls contains suspicious keywords
    int urlScore = 0;
    final suspiciousUrlKeywords = [
      'free',
      'money',
      'bit.ly',
      'ngrok',
      'tinyurl',
    ];
    for (final url in apk.urls) {
      final lower = url.toLowerCase();
      if (suspiciousUrlKeywords.any((k) => lower.contains(k))) {
        urlScore += 5;
      }
    }
    if (urlScore > 0) {
      urlScore = urlScore.clamp(0, 20);
      score += urlScore;
      reasons.add(
        DetectionReason(
          label: 'Suspicious Domains/Endpoints',
          description:
              'Extracted network endpoints match suspicious patterns or link shorteners.',
          scoreContribution: urlScore,
          iconCategory: IconCategory.link,
        ),
      );
    }

    // 3.5 Secrets Detection
    if (apk.secrets.isNotEmpty) {
      score += 25; // High penalty for hardcoded secrets
      reasons.add(
        DetectionReason(
          label: 'Exposed Secrets',
          description:
              'Found hardcoded sensitive keys/tokens: ${apk.secrets.take(3).join(', ')}...',
          scoreContribution: 25,
          iconCategory: IconCategory.manipulation,
        ),
      );
    }

    // 4. Certificates
    if (apk.certificates.isEmpty) {
      // Unsigned or v2/v3 signed
      reasons.add(
        const DetectionReason(
          label: 'No V1 Certificate Found',
          description:
              'No META-INF certificates found. App is either unsigned or uses v2/v3 signatures exclusively.',
          scoreContribution: 0,
          iconCategory: IconCategory.safe,
        ),
      );
    } else if (apk.certificates.any(
      (c) => c.contains('testkey') || c.contains('debug'),
    )) {
      score += 15;
      reasons.add(
        const DetectionReason(
          label: 'Debug/Test Certificate',
          description:
              'App is signed with a debug or test key. Legitimate production apps use proper release keys.',
          scoreContribution: 15,
          iconCategory: IconCategory.suspicious,
        ),
      );
    }

    score = score.clamp(0, 100);

    final ScamClassification classification;
    final String summary;

    if (score < 20) {
      classification = ScamClassification.safe;
      summary =
          'APK appears safe based on static analysis. No significant red flags detected.';
    } else if (score < 60) {
      classification = ScamClassification.suspicious;
      summary =
          'APK exhibits some suspicious behavior or requests sensitive permissions. Proceed with caution.';
    } else {
      classification = ScamClassification.scam;
      summary =
          'High risk! APK contains multiple indicators of compromise, dangerous permissions, or is flagged by threat intel.';
    }

    if (reasons.isEmpty) {
      reasons.add(
        const DetectionReason(
          label: 'No Threats Detected',
          description: 'Static analysis found no known malicious patterns.',
          scoreContribution: 0,
          iconCategory: IconCategory.safe,
        ),
      );
    }

    return AnalysisResult(
      classification: classification,
      riskScore: score,
      reasons: reasons,
      summary: summary,
      aiPowered: true,
    );
  }
}
