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

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'consent_service.dart';
import 'backend_config.dart';

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

/// What happened to a vote.
enum FeedbackOutcome {
  /// The server has it.
  sent,

  /// The server could not be reached, so the vote is saved on this device and
  /// goes out the next time the server answers. The user's answer is not lost,
  /// and the button must not look like it did nothing.
  savedOnDevice,

  /// Nothing was recorded (no consent on file).
  notRecorded,
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

  static String get _baseUrl => BackendConfig.baseUrl;

  static const Duration _timeout = Duration(seconds: 8);

  /// The digest sent in place of the message. Same input always produces the
  /// same hash, which is what makes repeat votes collapse server-side.
  static String contentHash(String text) =>
      sha256.convert(utf8.encode(text.trim())).toString();

  static const String _pendingKey = 'scamshield_pending_feedback';

  /// Submits one vote. If the server can't be reached the vote is kept on the
  /// device and retried later, instead of being dropped with an error: the
  /// "It was a scam" button used to do nothing visible whenever the server was
  /// down, which on a phone with no server configured was always.
  static Future<FeedbackOutcome> submit({
    required String text,
    required String classification,
    required int riskScore,
    required VerdictAgreement agreement,
    String? note,
  }) async {
    // Feedback leaves the device, so it is covered by the same consent gate as
    // every other outbound call. Someone who declined analytics/AI processing
    // has not agreed to send this either.
    if (!await _consent.hasGivenCurrentConsent()) {
      return FeedbackOutcome.notRecorded;
    }

    final vote = <String, dynamic>{
      'content_hash': contentHash(text),
      'classification': classification.toLowerCase(),
      'risk_score': riskScore,
      'agreement': agreement.wireValue,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };

    if (await _post(vote)) {
      unawaited(flushPending());
      return FeedbackOutcome.sent;
    }
    await _enqueue(vote);
    return FeedbackOutcome.savedOnDevice;
  }

  static Future<bool> _post(Map<String, dynamic> vote) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/feedback/verdict'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(vote),
          )
          .timeout(BackendConfig.timeout(_timeout));
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('VerdictFeedbackService.submit failed: $e');
      return false;
    }
  }

  static Future<void> _enqueue(Map<String, dynamic> vote) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_pendingKey) ?? <String>[];
      // One vote per message: a newer answer replaces an older one.
      queue.removeWhere((raw) {
        try {
          return (jsonDecode(raw) as Map)['content_hash'] ==
              vote['content_hash'];
        } catch (_) {
          return true;
        }
      });
      queue.add(jsonEncode(vote));
      // Bounded, so a server that is never reachable can't grow this forever.
      final trimmed = queue.length > 50
          ? queue.sublist(queue.length - 50)
          : queue;
      await prefs.setStringList(_pendingKey, trimmed);
    } catch (e) {
      debugPrint('VerdictFeedbackService could not queue a vote: $e');
    }
  }

  /// Sends votes saved while the server was unreachable. Safe to call often.
  static Future<void> flushPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_pendingKey) ?? const <String>[];
      if (queue.isEmpty) return;

      // Send in order; stop at the first failure and keep it and everything
      // after it for next time.
      var firstUnsent = queue.length;
      for (var i = 0; i < queue.length; i++) {
        Map<String, dynamic> vote;
        try {
          vote = Map<String, dynamic>.from(jsonDecode(queue[i]) as Map);
        } catch (_) {
          continue; // unreadable entry: drop it
        }
        if (!await _post(vote)) {
          firstUnsent = i;
          break;
        }
      }
      await prefs.setStringList(_pendingKey, queue.sublist(firstUnsent));
    } catch (e) {
      debugPrint('VerdictFeedbackService.flushPending failed: $e');
    }
  }

  /// How often the pipeline has been agreeing with reality lately. Returns
  /// null when unavailable — a figure the app can't actually stand behind is
  /// worse than showing nothing.
  static Future<VerdictAccuracy?> fetchAccuracy({int days = 30}) async {
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/feedback/accuracy?days=$days'))
          .timeout(BackendConfig.timeout(_timeout));
      if (resp.statusCode != 200) return null;
      return VerdictAccuracy.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('VerdictFeedbackService.fetchAccuracy failed: $e');
      return null;
    }
  }
}
