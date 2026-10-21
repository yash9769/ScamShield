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
      final result = ScamDetector.analyze(
        'Test message with bank OTP and urgent action required!',
      );
      expect(result.riskScore, greaterThanOrEqualTo(0));
      expect(result.riskScore, lessThanOrEqualTo(100));
    });

    test('analysis result has non-empty summary', () {
      final result = ScamDetector.analyze(
        'Click here to verify your account at bit.ly/verify',
      );
      expect(result.summary, isNotEmpty);
    });

    test('analysis result has at least one reason', () {
      final result = ScamDetector.analyze(
        'Click here to verify your account at bit.ly/verify',
      );
      expect(result.reasons, isNotEmpty);
    });
  });

  // Regressions: scams the detector used to rate "safe" (disconnection
  // threats, upfront fees, a caller asking for "the code") and genuine
  // messages it used to flag (a bank OTP with its "do not share" warning).
  group('ScamDetector — regressions', () {
    const scams = [
      'URGENT: Your SBI account is blocked. Update KYC now at http://sbi-kyc-update.top/login or it will be suspended. Share OTP 482913 with our agent.',
      'Congratulations! You won Rs 25,00,000 in KBC lottery. Pay Rs 5000 processing fee to claim.',
      'Dear customer your electricity will be disconnected tonight. Call 9876543210 immediately and pay Rs 10 via the link',
      'Your SIM will be deactivated within 24 hours due to incomplete KYC. Call 7003123456 now.',
      'Your parcel is held at customs. Pay customs charges of Rs 299 at http://bit.ly/parcel-fee to release it.',
      'Earn Rs 5000 daily working from home! Guaranteed returns, just pay Rs 500 registration fee to start.',
      'Hi this is the bank executive, please tell me the code you just received to stop the fraud transaction.',
      'Income tax refund of Rs 15,490 approved. Verify your account at http://incometax-refund.xyz to receive it.',
      'Your Netflix payment failed. Update your billing details at http://netflix-billing-help.top within 24 hours or your account will be suspended.',
      'Dear user, your PAN card is blocked. Click here to update: http://pan-update.info',
    ];
    const genuine = [
      'Hi Priya, are we still on for lunch at 1pm tomorrow? I will book the table.',
      'Your Amazon order 402-118 has shipped and arrives Thursday.',
      'Your OTP for HDFC netbanking login is 551203. Do not share it with anyone. Valid for 5 minutes.',
      '123456 is your WhatsApp code. Never share this code.',
      'Rs 2,340 debited from A/c XX4521 on 21-Oct via UPI to Zomato. Not you? Call 1800-202-6161.',
      'Your electricity bill of Rs 1,240 for October is generated. Due date 5 Nov. Pay via the official app.',
      'Meeting moved to 4pm, open the window in the conference room, it\'s stuffy.',
      'Your shipping label is ready. Pickup tomorrow between 10am and 2pm.',
      'Congratulations on your promotion! Let\'s celebrate this weekend.',
      'Reminder: your dentist appointment is on Monday at 11:30.',
    ];
    for (final text in scams) {
      test('flags: $text', () {
        expect(
          ScamDetector.analyze(text).classification,
          isNot(ScamClassification.safe),
        );
      });
    }
    for (final text in genuine) {
      test('safe: $text', () {
        expect(
          ScamDetector.analyze(text).classification,
          ScamClassification.safe,
        );
      });
    }
    test('OTP request vs delivery', () {
      expect(
        ScamDetector.asksForOtp('Share OTP 482913 with our agent'),
        isTrue,
      );
      expect(
        ScamDetector.asksForOtp(
          'Your OTP is 551203. Do not share it with anyone.',
        ),
        isFalse,
      );
      expect(
        ScamDetector.asksForOtp(
          '123456 is your WhatsApp code. Never share this code.',
        ),
        isFalse,
      );
    });
  });
}
