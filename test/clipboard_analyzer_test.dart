import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/services/clipboard_analyzer.dart';

void main() {
  group('ClipboardAnalyzer', () {
    test('flags nothing for ordinary text', () {
      final a = ClipboardAnalyzer.analyze(
        'Meeting at 3pm tomorrow, bring the slides. 12345 is my room number.',
      );
      expect(a.isThreat, isFalse);
      expect(a.urls, isEmpty);
      expect(a.otpCodes, isEmpty);
    });

    test('detects a plain http link', () {
      final a = ClipboardAnalyzer.analyze('Check out https://example.com/page');
      expect(a.threats, contains(ClipboardThreat.url));
      expect(a.urls, ['https://example.com/page']);
      expect(a.topThreat, ClipboardThreat.url);
    });

    test('detects a shortened link with higher priority', () {
      final a = ClipboardAnalyzer.analyze('Your refund is ready: http://bit.ly/fix-bank');
      expect(a.threats, contains(ClipboardThreat.shortUrl));
      expect(a.topThreat, ClipboardThreat.shortUrl);
    });

    test('detects a link pointing at a raw IP host', () {
      final a = ClipboardAnalyzer.analyze('Verify your account: http://203.0.113.7/login');
      expect(a.threats, contains(ClipboardThreat.ipLiteralHost));
      expect(a.ipHosts, isNotEmpty);
      expect(a.topThreat, ClipboardThreat.ipLiteralHost);
    });

    test('detects a UPI VPA and rejects emails', () {
      final vpa = ClipboardAnalyzer.analyze('Pay me here: ramesh.kumar@ybl');
      expect(vpa.threats, contains(ClipboardThreat.upiVpa));
      expect(vpa.upiVpa, 'ramesh.kumar@ybl');

      final email = ClipboardAnalyzer.analyze('Contact ramesh@gmail.com for details');
      expect(email.threats, isNot(contains(ClipboardThreat.upiVpa)));
    });

    test('detects OTP only when a verification keyword is present', () {
      final otp = ClipboardAnalyzer.analyze('Your OTP for transaction is 834920. Do not share it.');
      expect(otp.threats, contains(ClipboardThreat.otp));
      expect(otp.otpCodes, contains('834920'));

      final plain = ClipboardAnalyzer.analyze('My pin is 834920, remember it.');
      expect(plain.threats, isNot(contains(ClipboardThreat.otp)));
    });

    test('empty text is never a threat', () {
      final a = ClipboardAnalyzer.analyze('   ');
      expect(a.isThreat, isFalse);
    });

    test('content hash dedups whitespace-normalised copies', () {
      final a1 = ClipboardAnalyzer.analyze('Pay me here: ramesh@ybl');
      final a2 = ClipboardAnalyzer.analyze('  Pay  me here:\nramesh@ybl ');
      expect(a1.contentHash, a2.contentHash);
    });
  });
}
