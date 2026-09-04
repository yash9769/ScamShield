// test/widget_test.dart
//
// This file used to be the unmodified Flutter "counter app" template test,
// asserting a counter UI that has never existed in ScamShield — so it could
// never pass, and failed on every CI run. Replaced with a real smoke test of
// the app's actual entry widget.
//
// Kept deliberately plugin-free: ScamShieldApp's own build() only chooses
// between LoginScreen and MainNavigation, and LoginScreen has no initState,
// so this renders without needing SharedPreferences, secure storage or
// sqflite to be available in the test environment.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scamshield/main.dart';

void main() {
  testWidgets('ScamShieldApp builds and shows the sign-in screen when signed out',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ScamShieldApp(startLoggedIn: false));
    // The sign-in screen's reveal animations schedule timers; let them drain
    // so the test doesn't trip the "timer still pending" teardown assertion.
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('SIGN IN TO SHIELD'), findsOneWidget);
    expect(find.text('CONTINUE AS GUEST'), findsOneWidget);
  });
}
