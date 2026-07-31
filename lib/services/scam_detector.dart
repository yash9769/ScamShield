// lib/services/scam_detector.dart

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

enum IconCategory {
  financial,
  link,
  urgency,
  suspicious,
  manipulation,
  safe,
}

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
    'do not share',
    'never share',
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
  ];

  // ── Regex patterns ────────────────────────────────────────────────────────
  /// Detects any http / https URL.
  static final _urlRegex = RegExp(
    r'https?://[^\s]+',
    caseSensitive: false,
  );

  /// Detects shortened / obfuscated URLs commonly used in phishing.
  static final _shortUrlRegex = RegExp(
    r'\b(bit\.ly|tinyurl\.com|goo\.gl|t\.co|ow\.ly|buff\.ly|is\.gd|rb\.gy|cutt\.ly|tiny\.cc|adf\.ly)[^\s]*',
    caseSensitive: false,
  );

  /// Detects phone numbers that could be used for vishing.
  static final _phoneRegex = RegExp(
    r'(\+?\d[\d\s\-().]{7,}\d)',
  );

  /// Detects patterns like "Your OTP is 123456" or "OTP: 654321".
  static final _otpPatternRegex = RegExp(
    r'otp[\s:is]*\d{4,8}',
    caseSensitive: false,
  );

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
    final financialHits = _financialKeywords.where((k) => lower.contains(k)).toList();
    if (financialHits.isNotEmpty) {
      final pts = (financialHits.length * 12).clamp(0, 35);
      score += pts;
      reasons.add(DetectionReason(
        label: 'Financial Keywords Detected',
        description:
            'Found sensitive financial terms: ${financialHits.take(3).map((k) => '"$k"').join(', ')}${financialHits.length > 3 ? ', and ${financialHits.length - 3} more' : ''}.',
        scoreContribution: pts,
        iconCategory: IconCategory.financial,
      ));
    }

    // ── 2. Prize / lottery keywords ───────────────────────────────────────
    final prizeHits = _prizeKeywords.where((k) => lower.contains(k)).toList();
    if (prizeHits.isNotEmpty) {
      final pts = (prizeHits.length * 14).clamp(0, 30);
      score += pts;
      reasons.add(DetectionReason(
        label: 'Prize / Lottery Language',
        description:
            'Detected classic lottery-scam language: ${prizeHits.take(3).map((k) => '"$k"').join(', ')}. Legitimate organisations never announce prizes via SMS.',
        scoreContribution: pts,
        iconCategory: IconCategory.suspicious,
      ));
    }

    // ── 3. Urgency keywords ───────────────────────────────────────────────
    final urgencyHits = _urgencyKeywords.where((k) => lower.contains(k)).toList();
    if (urgencyHits.isNotEmpty) {
      final pts = (urgencyHits.length * 10).clamp(0, 25);
      score += pts;
      reasons.add(DetectionReason(
        label: 'Urgency & Pressure Tactics',
        description:
            'Detected ${urgencyHits.length} urgency trigger(s): ${urgencyHits.take(3).map((k) => '"$k"').join(', ')}. Creating pressure is a core scam technique.',
        scoreContribution: pts,
        iconCategory: IconCategory.urgency,
      ));
    }

    // ── 4. URL detection ─────────────────────────────────────────────────
    final urlMatches = _urlRegex.allMatches(text);
    if (urlMatches.isNotEmpty) {
      int urlPts = 10;

      // Check for shortened / phishing URLs — higher penalty
      final shortMatches = _shortUrlRegex.allMatches(text);
      if (shortMatches.isNotEmpty) {
        urlPts = 25;
        reasons.add(DetectionReason(
          label: 'Shortened / Obfuscated URL',
          description:
              'Found ${shortMatches.length} shortened URL(s). Scammers use services like bit.ly to hide the real destination of malicious links.',
          scoreContribution: urlPts,
          iconCategory: IconCategory.link,
        ));
      } else {
        reasons.add(DetectionReason(
          label: 'URL / Link Detected',
          description:
              'Found ${urlMatches.length} link(s) in the message. Verify any link before clicking, especially if you were not expecting it.',
          scoreContribution: urlPts,
          iconCategory: IconCategory.link,
        ));
      }
      score += urlPts;
    }

    // ── 5. OTP request pattern ───────────────────────────────────────────
    if (_otpPatternRegex.hasMatch(lower)) {
      const pts = 20;
      score += pts;
      reasons.add(DetectionReason(
        label: 'OTP / Code Sharing Request',
        description:
            'The message appears to contain or request an OTP. No legitimate service will ever ask you to share your OTP.',
        scoreContribution: pts,
        iconCategory: IconCategory.financial,
      ));
    }

    // ── 6. Manipulation keywords ─────────────────────────────────────────
    final manipHits = _manipulationKeywords.where((k) => lower.contains(k)).toList();
    if (manipHits.isNotEmpty) {
      final pts = (manipHits.length * 8).clamp(0, 20);
      score += pts;
      reasons.add(DetectionReason(
        label: 'Psychological Manipulation',
        description:
            'Detected manipulative language: ${manipHits.take(3).map((k) => '"$k"').join(', ')}. Scammers use these phrases to bypass critical thinking.',
        scoreContribution: pts,
        iconCategory: IconCategory.manipulation,
      ));
    }

    // ── 7. Generic suspicious action words ───────────────────────────────
    final suspHits = _suspiciousKeywords.where((k) => lower.contains(k)).toList();
    if (suspHits.isNotEmpty) {
      final pts = (suspHits.length * 5).clamp(0, 15);
      score += pts;
      reasons.add(DetectionReason(
        label: 'Suspicious Action Words',
        description:
            'Found action-driving language: ${suspHits.take(3).map((k) => '"$k"').join(', ')}. Be cautious of messages asking you to click, download, or install anything.',
        scoreContribution: pts,
        iconCategory: IconCategory.suspicious,
      ));
    }

    // ── 8. Phone number in message ───────────────────────────────────────
    final phoneMatches = _phoneRegex.allMatches(text);
    if (phoneMatches.isNotEmpty && reasons.isNotEmpty) {
      // Only flag phones as suspicious when combined with other signals
      const pts = 5;
      score += pts;
      reasons.add(DetectionReason(
        label: 'Embedded Phone Number',
        description:
            'Found ${phoneMatches.length} phone number(s). Scammers often embed call-back numbers to establish direct voice contact with victims.',
        scoreContribution: pts,
        iconCategory: IconCategory.suspicious,
      ));
    }

    // ── Clamp score ────────────────────────────────────────────────────────
    score = score.clamp(0, 100);

    // ── Classify ──────────────────────────────────────────────────────────
    final ScamClassification classification;
    final String summary;

    if (score == 0) {
      classification = ScamClassification.safe;
      summary = 'No suspicious patterns were detected. This message appears safe.';
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
      reasons.add(const DetectionReason(
        label: 'No Threats Detected',
        description: 'This message does not contain known scam patterns.',
        scoreContribution: 0,
        iconCategory: IconCategory.safe,
      ));
    }

    return AnalysisResult(
      classification: classification,
      riskScore: score,
      reasons: reasons,
      summary: summary,
    );
  }
}
