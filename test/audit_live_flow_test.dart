// Audit driver test — exercises the REAL app widget tree against the LIVE
// backend. This is test-only tooling; it does not modify application code.
//
// Run with:
//   flutter test test/audit_live_flow_test.dart \
//     --dart-define=SCAMSHIELD_BACKEND_URL=http://localhost:8010
//
// It boots ScamShieldApp, taps through the real screens, and performs real
// HTTP calls to the running backend (only storage/connectivity plugins are
// mocked so the widget tree can mount in the test host).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  // Real async work (HTTP, etc.) completes on the real event loop.
  await tester.runAsync(() => Future<void>.delayed(duration));
  // Advance fake time so Reveal/animations fire.
  await tester.pump(duration);
}

Future<void> _settleNetwork(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await _pumpFor(tester, const Duration(milliseconds: 400));
  }
}

Future<void> _flushTimers(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Restore the REAL HTTP client (flutter_test stubs it to return 400s).
  HttpOverrides.global = null;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    // Mock storage plugins that have no test host.
    final secureStore = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'read':
            return secureStore[call.arguments['key']];
          case 'write':
            secureStore[call.arguments['key']] = call.arguments['value'];
            return null;
          case 'delete':
            secureStore.remove(call.arguments['key']);
            return null;
          case 'readAll':
            return Map<String, String>.from(secureStore);
          case 'deleteAll':
            secureStore.clear();
            return null;
          case 'containsKey':
            return secureStore.containsKey(call.arguments['key']);
        }
        return null;
      },
    );

    // connectivity_plus: pretend wifi is available.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => ['wifi'],
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(
        onListen: (arguments, events) => events.success(['wifi']),
      ),
    );
  });

  testWidgets('boots logged out -> shows LoginScreen', (tester) async {
    await tester.pumpWidget(const ScamShieldApp(startLoggedIn: false));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('SIGN IN TO SHIELD'), findsWidgets,
        reason: 'Login screen should render');
    await _flushTimers(tester);
  });

  testWidgets('boots logged in -> home + limited-mode banner (real /health)',
      (tester) async {
    await tester.pumpWidget(const ScamShieldApp(startLoggedIn: true));
    await _settleNetwork(tester);

    expect(find.text('ScamShield'), findsWidgets);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('No Threat Scans Yet'), findsOneWidget);
    await _flushTimers(tester);
  });

  testWidgets('scan a scam message against the live backend', (tester) async {
    await tester.pumpWidget(const ScamShieldApp(startLoggedIn: true));
    await _settleNetwork(tester);

    await tester.tap(find.text('SCAN'));
    await _pumpFor(tester, const Duration(milliseconds: 600));

    await tester.enterText(
      find.byType(TextField),
      'URGENT: Your bank account is locked! Verify your account now, click '
      'https://bit.ly/bank-fix and send your OTP 482913 immediately. Pay '
      'Rs 5000 processing fee to unlock.',
    );
    await tester.tap(find.text('ANALYZE FOR THREATS'));
    await _settleNetwork(tester);

    expect(find.text('SCAM'), findsOneWidget,
        reason: 'Real heuristic engine should flag a scam message');
    expect(find.text('DETECTED RISK FACTORS'), findsOneWidget);
    expect(find.textContaining('Risk Score:'), findsWidgets,
        reason: 'Score rendered from the live backend response');
    await _flushTimers(tester);
  });

  testWidgets('scan a safe message -> heuristic-only badge (no green SAFE)',
      (tester) async {
    await tester.pumpWidget(const ScamShieldApp(startLoggedIn: true));
    await _settleNetwork(tester);

    await tester.tap(find.text('SCAN'));
    await _pumpFor(tester, const Duration(milliseconds: 600));

    await tester.enterText(find.byType(TextField), 'Hi, are you free for coffee tomorrow?');
    await tester.tap(find.text('ANALYZE FOR THREATS'));
    await _settleNetwork(tester);

    expect(find.text('NO THREATS FOUND (HEURISTIC ONLY)'), findsOneWidget,
        reason: 'Never show green SAFE when AI unavailable');
    expect(find.text('SAFE'), findsNothing);
    await _flushTimers(tester);
  });

  testWidgets('breach check against the live backend', (tester) async {
    await tester.pumpWidget(const ScamShieldApp(startLoggedIn: true));
    await _settleNetwork(tester);

    await tester.tap(find.text('BREACH'));
    await _pumpFor(tester, const Duration(milliseconds: 600));
    await _settleNetwork(tester);

    final emailField = find.byType(TextField);
    await tester.ensureVisible(emailField);
    await _pumpFor(tester, const Duration(milliseconds: 200));
    await tester.enterText(emailField, 'test@example.com');

    final checkBtn = find.widgetWithText(ElevatedButton, 'CHECK EMAIL BREACH STATUS');
    expect(checkBtn, findsOneWidget);
    await tester.ensureVisible(checkBtn);
    await _pumpFor(tester, const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      tester.widget<ElevatedButton>(checkBtn).onPressed!();
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pump();
    await _pumpFor(tester, const Duration(seconds: 3));
    await _pumpFor(tester, const Duration(seconds: 2));

    expect(find.textContaining('BREACH DETAILS FOR'), findsOneWidget,
        reason: 'Live breach verdict should render for test@example.com');
    expect(find.textContaining('test@example.com'), findsWidgets);
    await _flushTimers(tester);
  });

  testWidgets('history shows empty state', (tester) async {
    await tester.pumpWidget(const ScamShieldApp(startLoggedIn: true));
    await _settleNetwork(tester);

    await tester.tap(find.text('HISTORY'));
    await _settleNetwork(tester);

    expect(find.text('No Scan Records Found'), findsOneWidget);
    expect(find.text('NEW SCAN'), findsOneWidget);
    await _flushTimers(tester);
  });

  testWidgets('learn tab opens a security module', (tester) async {
    await tester.pumpWidget(const ScamShieldApp(startLoggedIn: true));
    await _settleNetwork(tester);

    await tester.tap(find.text('LEARN'));
    await _settleNetwork(tester);

    expect(find.text('Cyber Threat Academy'), findsOneWidget);
    expect(find.text('Phishing 101'), findsOneWidget);

    await tester.ensureVisible(find.text('Phishing 101'));
    await _pumpFor(tester, const Duration(milliseconds: 200));
    await tester.tap(find.text('Phishing 101'));
    await _settleNetwork(tester);
    expect(find.text('Phishing 101'), findsWidgets);
    await _flushTimers(tester);
  });

  testWidgets('profile shows version and mode via About dialog', (tester) async {
    await tester.pumpWidget(const ScamShieldApp(startLoggedIn: true));
    await _settleNetwork(tester);

    await tester.tap(find.text('PROFILE'));
    await _settleNetwork(tester);

    expect(find.text('ScamShield Profile'), findsOneWidget);

    final about = find.text('About ScamShield');
    await tester.ensureVisible(about);
    await _pumpFor(tester, const Duration(milliseconds: 200));
    await tester.tap(about);
    await _pumpFor(tester, const Duration(milliseconds: 600));

    expect(find.text('ScamShield v2.1'), findsOneWidget);
    expect(find.textContaining('Active Mode:'), findsOneWidget);
    expect(find.textContaining('Server AI Analysis (Gemini/Groq)'), findsOneWidget);
    await _flushTimers(tester);
  });
}
