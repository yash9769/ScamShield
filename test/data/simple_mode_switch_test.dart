// Why Profile pops to the root after switching Simple Mode.
//
// The app swaps MaterialApp.home when Simple Mode changes. Profile opened from
// the Home screen is a *pushed route*, which sits above `home`, so the swap
// happens underneath it and the user sees nothing change. This reproduces that
// with the same structure as lib/main.dart, and shows popUntil(isFirst) fixes it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(ValueNotifier<bool> simple, {required bool popToRoot}) {
  return ValueListenableBuilder<bool>(
    valueListenable: simple,
    builder: (context, isSimple, _) => MaterialApp(
      home: isSimple
          ? const Scaffold(body: Text('SIMPLE HOME'))
          : Builder(
              builder: (home) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    home,
                    MaterialPageRoute(
                      builder: (_) => Builder(
                        builder: (profile) => Scaffold(
                          body: TextButton(
                            onPressed: () {
                              simple.value = true;
                              if (popToRoot) {
                                Navigator.of(
                                  profile,
                                ).popUntil((r) => r.isFirst);
                              }
                            },
                            child: const Text('TURN ON SIMPLE MODE'),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('OPEN PROFILE'),
                ),
              ),
            ),
    ),
  );
}

void main() {
  testWidgets('without popping, the pushed Profile stays on top (the bug)', (
    tester,
  ) async {
    final simple = ValueNotifier<bool>(false);
    await tester.pumpWidget(app(simple, popToRoot: false));
    await tester.tap(find.text('OPEN PROFILE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TURN ON SIMPLE MODE'));
    await tester.pumpAndSettle();
    expect(find.text('SIMPLE HOME'), findsNothing);
    expect(find.text('TURN ON SIMPLE MODE'), findsOneWidget);
  });

  testWidgets('popping to the root shows Simple Mode (the fix)', (
    tester,
  ) async {
    final simple = ValueNotifier<bool>(false);
    await tester.pumpWidget(app(simple, popToRoot: true));
    await tester.tap(find.text('OPEN PROFILE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TURN ON SIMPLE MODE'));
    await tester.pumpAndSettle();
    expect(find.text('SIMPLE HOME'), findsOneWidget);
    expect(find.text('TURN ON SIMPLE MODE'), findsNothing);
  });
}
