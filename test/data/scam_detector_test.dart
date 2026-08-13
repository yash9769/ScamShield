// test/data/scam_detector_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/services/scam_detector.dart';

void main() {
  group('ScamDetector — Scam messages', () {
    test('detects OTP phishing', () {
      final result = ScamDetector.analyze(
        'Your SBI OTP is 482913. Verify at bit.ly/sbi-kyc. Do not share this OTP.',
      );
      // Combination of OTP + shortened URL + financial = suspicious or scam
      expect(result.classification, isNot(ScamClassification.safe));
      expect(result.riskScore, greaterThan(29));
    });

    test('detects lottery scam', () {
      final result = ScamDetector.analyze(
        'Congratulations! You have won the KBC Lucky Draw prize of Rs 25 Lakh. '
        'Call 9876543210 to claim your reward. Winner selected today!',
      );
      expect(result.classification, isNot(ScamClassification.safe));
      expect(result.riskScore, greaterThan(29));
    });

    test('detects shortened URL', () {
      final result = ScamDetector.analyze(
        'URGENT: Your account is suspended. Verify now at https://bit.ly/verify-acc',
      );
      // Should detect at minimum as suspicious due to urgency + shortened URL
      expect(result.classification, isNot(ScamClassification.safe));
      expect(result.riskScore, greaterThan(20));
    });

    test('detects urgency keywords', () {
      final result = ScamDetector.analyze(
        'Act now! Your account will be terminated within 24 hours. Confirm immediately!',
      );
      final hasUrgency = result.reasons.any(
        (r) => r.iconCategory == IconCategory.urgency,
      );
      expect(hasUrgency, isTrue);
    });

    test('detects financial keywords', () {
      final result = ScamDetector.analyze(
        'Share your OTP, UPI pin, and Aadhaar number to complete KYC verification.',
      );
      final hasFinancial = result.reasons.any(
        (r) => r.iconCategory == IconCategory.financial,
      );
      expect(hasFinancial, isTrue);
    });

    test('detects investment scam', () {
      final result = ScamDetector.analyze(
        'Guaranteed 25% monthly returns on crypto investment. Limited time. Risk free!',
      );
      expect(result.riskScore, greaterThan(20));
    });
  });

  group('ScamDetector — Safe messages', () {
    test('does not flag normal personal message', () {
      final result = ScamDetector.analyze(
        'Hey, are you coming for dinner tonight? Let me know by 6 PM.',
      );
      expect(result.classification, ScamClassification.safe);
    });

    test('does not flag bank debit notification', () {
      final result = ScamDetector.analyze(
        'HDFC Bank: Debit of Rs 1,250 from account XXXXXX8934 on 25-Jul-26 at BigBazaar.',
      );
      // Even if some score, should not cross scam threshold
      expect(result.riskScore, lessThan(65));
    });

    test('returns empty message as safe', () {
      final result = ScamDetector.analyze('');
      expect(result.classification, ScamClassification.safe);
      expect(result.riskScore, equals(0));
    });

    test('returns whitespace-only as safe', () {
      final result = ScamDetector.analyze('   ');
      expect(result.classification, ScamClassification.safe);
    });

    test('does not flag happy birthday message', () {
      final result = ScamDetector.analyze(
        'Happy Birthday! Wishing you a wonderful day filled with joy and happiness.',
      );
      expect(result.classification, ScamClassification.safe);
    });
  });

  group('ScamDetector — Result structure', () {
    test('analysis result has valid score range', () {
      final result = ScamDetector.analyze('Test message with bank OTP and urgent action required!');
      expect(result.riskScore, greaterThanOrEqualTo(0));
      expect(result.riskScore, lessThanOrEqualTo(100));
    });

    test('analysis result has non-empty summary', () {
      final result = ScamDetector.analyze('Click here to verify your account at bit.ly/verify');
      expect(result.summary, isNotEmpty);
    });

    test('analysis result has at least one reason', () {
      final result = ScamDetector.analyze('Click here to verify your account at bit.ly/verify');
      expect(result.reasons, isNotEmpty);
    });
  });
}
