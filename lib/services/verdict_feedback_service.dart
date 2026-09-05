// lib/services/verdict_feedback_service.dart
//
// "Was this right?" — the feedback loop a detection pipeline otherwise never
// gets.
//
// ScamShield's verdicts come from a heuristic engine plus an LLM, and neither
// can tell when it is wrong. A false positive on a legitimate bank SMS is
// completely invisible to us unless the person who received it says so, and
// that person is the only one who actually knows. This sends that one bit
// back.
//
// ── What is and isn't sent ─────────────────────────────────────────────────
// Never the message. What goes to the server is a SHA-256 of the analysed
// text, the verdict, the score, and which of three answers the user picked.
// The hash exists for exactly one purpose — collapsing repeat votes on the
// same message into one — and cannot be turned back into the message. The
// endpoint rejects anything that isn't a hex digest, so it can't quietly drift
// into a place raw SMS bodies get posted.
//
// No account is required. Feedback on a scam text is worth having from someone
// who never signs in, and requiring an identity to give it would cost more
// than it is worth.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'consent_service.dart';

/// The three things a user can say about a verdict.
enum VerdictAgreement {
  /// The call was right.
  correct,

  /// Flagged as a scam, but the user knows this one is legitimate.
  falsePositive,

  /// Called safe (or scored too low), but the user knows it was a scam.
  missed,
}

extension VerdictAgreementWire on VerdictAgreement {
  String get wireValue => switch (this) {
        VerdictAgreement.correct => 'correct',
        VerdictAgreement.falsePositive => 'false_positive',
        VerdictAgreement.missed => 'missed',
      };
}

class VerdictAccuracy {
  final int total;
  final int correct;
  final int falsePositives;
  final int missed;
  final double accuracyPercent;

  const VerdictAccuracy({
    required this.total,
    required this.correct,
    required this.falsePositives,
    required this.missed,
    required this.accuracyPercent,
  });

  factory VerdictAccuracy.fromJson(Map<String, dynamic> j) => VerdictAccuracy(
        total: j['total'] ?? 0,
        correct: j['correct'] ?? 0,
        falsePositives: j['false_positives'] ?? 0,
        missed: j['missed'] ?? 0,
        accuracyPercent: (j['accuracy_percent'] as num?)?.toDouble() ?? 0.0,
      );
}

class VerdictFeedbackService {
  VerdictFeedbackService._();

  static final ConsentService _consent = ConsentService();

  static String get _baseUrl {
    const customUrl = String.fromEnvironment('SCAMSHIELD_BACKEND_URL');
    if (customUrl.isNotEmpty) return customUrl;
    return Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
  }

  static const Duration _timeout = Duration(seconds: 8);

  /// The digest sent in place of the message. Same input always produces the
  /// same hash, which is what makes repeat votes collapse server-side.
  static String contentHash(String text) =>
      sha256.convert(utf8.encode(text.trim())).toString();

  /// Submits one vote. Returns false on any failure so the caller can say
  /// "couldn't send" rather than show a thank-you for something that never
  /// left the device.
  static Future<bool> submit({
    required String text,
    required String classification,
    required int riskScore,
    required VerdictAgreement agreement,
    String? note,
  }) async {
    // Feedback leaves the device, so it is covered by the same consent gate as
    // every other outbound call. Someone who declined analytics/AI processing
    // has not agreed to send this either.
    if (!await _consent.hasGivenCurrentConsent()) return false;

    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/feedback/verdict'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'content_hash': contentHash(text),
              'classification': classification.toLowerCase(),
              'risk_score': riskScore,
              'agreement': agreement.wireValue,
              if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
            }),
          )
          .timeout(_timeout);
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('VerdictFeedbackService.submit failed: $e');
      return false;
    }
  }

  /// How often the pipeline has been agreeing with reality lately. Returns
  /// null when unavailable — a figure the app can't actually stand behind is
  /// worse than showing nothing.
  static Future<VerdictAccuracy?> fetchAccuracy({int days = 30}) async {
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/feedback/accuracy?days=$days'))
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      return VerdictAccuracy.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('VerdictFeedbackService.fetchAccuracy failed: $e');
      return null;
    }
  }
}
