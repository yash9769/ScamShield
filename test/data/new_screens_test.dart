import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/screens/cybercrime_screen.dart';
import 'package:scamshield/screens/qr_result_screen.dart';
import 'package:scamshield/theme.dart';

Widget host(Widget child) => MaterialApp(theme: appTheme, home: child);

void main() {
  testWidgets(
    'QR result shows the real destination and the impersonation warning',
    (tester) async {
      // Tall enough that the whole ListView is built, not just the first screen.
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          const QrResultScreen(raw: 'https://sbi.co.in.verify-login.top/kyc'),
        ),
      );
      await tester.pump();
      expect(find.text('Web link'), findsOneWidget);
      expect(find.text('Nothing has been opened yet.'), findsOneWidget);
      // The owner is the part that matters, not the brand-looking prefix.
      expect(find.text('verify-login.top'), findsOneWidget);
      expect(find.textContaining('mentions "sbi"'), findsOneWidget);
      expect(find.text('Trace where it redirects'), findsOneWidget);
      expect(find.text('Check against threat lists'), findsOneWidget);
      expect(find.text('Run a full scan on this'), findsOneWidget);
    },
  );

  testWidgets('QR result for plain text offers no link actions', (
    tester,
  ) async {
    await tester.pumpWidget(host(const QrResultScreen(raw: 'hello world')));
    await tester.pump();
    expect(find.text('Plain text'), findsOneWidget);
    expect(find.text('Trace where it redirects'), findsNothing);
    expect(find.text('Open link'), findsNothing);
  });

  testWidgets('Cybercrime screen leads with the helpline and the portal', (
    tester,
  ) async {
    await tester.pumpWidget(host(const CybercrimeScreen()));
    await tester.pump();
    expect(find.text('Call 1930'), findsOneWidget);
    expect(find.text('Open cybercrime.gov.in'), findsOneWidget);
    expect(find.textContaining('first hour'), findsOneWidget);
  });
}
