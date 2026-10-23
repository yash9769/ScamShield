import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/screens/apk_scan_screen.dart';
import 'package:scamshield/screens/cybercrime_screen.dart';
import 'package:scamshield/screens/scan_screen.dart';
import 'package:scamshield/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpScan(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: appTheme, home: const ScanScreen()),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('Scan tab lists every other kind of check', (tester) async {
    await pumpScan(tester);
    expect(find.text('More ways to check'), findsOneWidget);
    for (final title in [
      'App (APK)',
      'QR or UPI code',
      'File or clipboard',
      'Email leak',
      'Device check',
      'Report a scam',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('App (APK) opens the APK scanner', (tester) async {
    await pumpScan(tester);
    await tester.tap(find.text('App (APK)'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ApkScanScreen), findsOneWidget);
  });

  testWidgets('Report a scam opens the cybercrime screen', (tester) async {
    await pumpScan(tester);
    await tester.tap(find.text('Report a scam'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CybercrimeScreen), findsOneWidget);
  });
}
