// Smoke test: the app boots through the branded splash to the login screen
// and validates empty input.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scamshield/main.dart';

Future<void> pumpThroughSplash(WidgetTester tester) async {
  await tester.pumpWidget(const ScamShieldApp());
  // Let the mock SharedPreferences-backed bootstrap resolve, then swap to the
  // login screen. Explicit pumps (not pumpAndSettle) because the splash uses
  // an indeterminate loading bar while it is visible.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App shows a branded splash before the login screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ScamShieldApp());
    expect(find.text('ScamShield'), findsOneWidget);
  });

  testWidgets('App boots to the login screen', (WidgetTester tester) async {
    await pumpThroughSplash(tester);

    expect(find.text('Welcome to ScamShield'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
  });

  testWidgets('Sign In shows validation when fields are empty',
      (WidgetTester tester) async {
    await pumpThroughSplash(tester);

    await tester.tap(find.text('Sign In'));
    await tester.pump();

    expect(find.text('Please enter both email and password.'), findsOneWidget);
  });
}
