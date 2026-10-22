import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/services/qr_content.dart';

QrContent parse(String s) => QrContentParser.parse(s);
bool has(QrContent c, QrWarningLevel l, String needle) => c.warnings.any(
  (w) => w.level == l && w.message.toLowerCase().contains(needle.toLowerCase()),
);

void main() {
  group('registrable domain', () {
    test('plain and multi-part suffixes', () {
      expect(
        QrContentParser.registrableDomainOf('login.sbi.co.in'),
        'sbi.co.in',
      );
      expect(
        QrContentParser.registrableDomainOf('www.google.com'),
        'google.com',
      );
      expect(
        QrContentParser.registrableDomainOf('sbi.co.in.evil.top'),
        'evil.top',
      );
    });
  });

  group('links', () {
    test('a normal https site shows its owner and no danger', () {
      final c = parse('https://www.amazon.in/gp/help');
      expect(c.kind, QrKind.url);
      expect(c.registrableDomain, 'amazon.in');
      expect(c.hasDanger, isFalse);
    });

    test('bare domain is treated as a link, with a note', () {
      final c = parse('example.com/pay');
      expect(c.isLink, isTrue);
      expect(c.uri!.host, 'example.com');
      expect(has(c, QrWarningLevel.info, 'without http'), isTrue);
    });

    test('http is flagged as unencrypted', () {
      expect(
        has(
          parse('http://example.com'),
          QrWarningLevel.caution,
          'not encrypted',
        ),
        isTrue,
      );
    });

    test('brand look-alike is a danger', () {
      final c = parse('https://sbi.co.in.verify-login.top/kyc');
      expect(c.registrableDomain, 'verify-login.top');
      expect(has(c, QrWarningLevel.danger, 'mentions "sbi"'), isTrue);
    });

    test('the real brand domain is not flagged as impersonation', () {
      final c = parse('https://retail.onlinesbi.sbi/login');
      expect(has(c, QrWarningLevel.danger, 'mentions'), isFalse);
      final c2 = parse('https://www.sbi.co.in');
      expect(has(c2, QrWarningLevel.danger, 'mentions'), isFalse);
    });

    test('user-info trick: the real host is after the @', () {
      final c = parse('https://google.com@evil.example.xyz/login');
      expect(c.uri!.host, 'evil.example.xyz');
      expect(has(c, QrWarningLevel.danger, '@'), isTrue);
    });

    test('raw IP, punycode and apk downloads are dangers', () {
      expect(
        has(
          parse('http://192.168.4.7/pay'),
          QrWarningLevel.danger,
          'ip address',
        ),
        isTrue,
      );
      expect(
        has(
          parse('https://xn--pypal-4ve.com'),
          QrWarningLevel.danger,
          'punycode',
        ),
        isTrue,
      );
      expect(
        has(
          parse('https://cdn.example.com/app.apk'),
          QrWarningLevel.danger,
          '.apk',
        ),
        isTrue,
      );
    });

    test('shorteners and cheap TLDs are cautions', () {
      expect(
        has(parse('https://bit.ly/3abc'), QrWarningLevel.caution, 'shortener'),
        isTrue,
      );
      expect(
        has(parse('https://prize.top/x'), QrWarningLevel.caution, '.top'),
        isTrue,
      );
    });

    test('query parameters are listed', () {
      final c = parse('https://example.com/p?amount=500&to=abc');
      final passes = c.fields.firstWhere((f) => f.key == 'Passes along').value;
      expect(passes, contains('amount=500'));
      expect(passes, contains('to=abc'));
    });
  });

  group('other content', () {
    test(
      'UPI request lists payee and amount, and warns scanning never receives money',
      () {
        final c = parse('upi://pay?pa=shop@okbank&pn=Shop&am=250&cu=INR');
        expect(c.kind, QrKind.payment);
        expect(
          c.fields.any(
            (f) => f.key == 'Pay to (UPI ID)' && f.value == 'shop@okbank',
          ),
          isTrue,
        );
        expect(has(c, QrWarningLevel.caution, 'never receives money'), isTrue);
      },
    );

    test('wifi network name and open-network warning', () {
      final c = parse('WIFI:T:nopass;S:Cafe Free;;');
      expect(c.kind, QrKind.wifi);
      expect(c.fields.first.value, 'Cafe Free');
      expect(has(c, QrWarningLevel.caution, 'no password'), isTrue);
      final secured = parse(r'WIFI:T:WPA;S:Home\;Net;P:secret;;');
      expect(secured.fields.first.value, 'Home;Net');
      expect(has(secured, QrWarningLevel.caution, 'no password'), isFalse);
    });

    test('phone, sms, email, text', () {
      expect(parse('tel:+911234567890').kind, QrKind.phone);
      final sms = parse('SMSTO:56767:STOP');
      expect(sms.kind, QrKind.sms);
      expect(sms.fields.first.value, '56767');
      expect(parse('mailto:a@b.com?subject=x').kind, QrKind.email);
      expect(parse('hello there').kind, QrKind.text);
    });
  });
}
