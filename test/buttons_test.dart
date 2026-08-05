// Button interaction tests: verify every key button performs its real action
// (navigates, scans, saves, or signs out) rather than being a dead tap.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scamshield/theme.dart';
import 'package:scamshield/data/database/database_helper.dart';
import 'package:scamshield/data/repositories/scan_repository.dart';
import 'package:scamshield/data/models/scan_record.dart';
import 'package:scamshield/data/education/scam_encyclopedia.dart';
import 'package:scamshield/data/education/quiz_data.dart';
import 'package:scamshield/screens/scam_encyclopedia_screen.dart';
import 'package:scamshield/screens/article_detail_screen.dart';
import 'package:scamshield/screens/quiz_screen.dart';
import 'package:scamshield/screens/history_screen.dart';
import 'package:scamshield/screens/learn_screen.dart';
import 'package:scamshield/screens/profile_screen.dart';
import 'package:scamshield/screens/privacy_data_screen.dart';
import 'package:scamshield/screens/scan_screen.dart';
import 'package:scamshield/screens/login_screen.dart';
import 'package:scamshield/screens/register_screen.dart';
import 'package:scamshield/main.dart';

import 'helpers/fake_http.dart';

Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(theme: appTheme, home: screen));
  await tester.pump();
}

/// Lets real I/O (SQLite) settle, then pumps a frame.
Future<void> settleIO(WidgetTester tester, {int attempts = 20}) async {
  for (var i = 0; i < attempts; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = FakeHttpOverrides();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
  });

  group('Login / Auth', () {
    testWidgets('Create Account navigates to register screen',
        (tester) async {
      await pumpScreen(tester, const LoginScreen());
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sign In with credentials navigates to main navigation',
        (tester) async {
      await pumpScreen(tester, const LoginScreen());
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'password123');
      await tester.tap(find.text('Sign In'));
      // _login() waits 600ms of fake-clock time, then navigates.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Home tab is the default screen.
      expect(find.text('Quick Actions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ScanScreen', () {
    testWidgets('Analyze button produces a real result', (tester) async {
      await pumpScreen(tester, const ScanScreen());
      await tester.enterText(
          find.byType(TextField),
          'URGENT: Your bank account is locked. Verify at bit.ly/secure now. '
          'Share your OTP 482913 to unlock.');
      await tester.pump(); // Rebuild so the button becomes enabled.
      await tester.tap(find.text('Analyze Content'));
      await tester.pump();
      // Pass the simulated 1800ms analysis delay (fake clock).
      await tester.pump(const Duration(seconds: 2));
      // Let the SQLite persistence settle (real I/O).
      await settleIO(tester);
      expect(find.text('Detection Breakdown'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('CLEAR button resets the analysis', (tester) async {
      await pumpScreen(tester, const ScanScreen());
      await tester.enterText(find.byType(TextField), 'some content');
      await tester.pump();
      await tester.tap(find.text('Analyze Content'));
      await tester.pump(const Duration(seconds: 2));
      await settleIO(tester);
      expect(find.text('Detection Breakdown'), findsOneWidget);
      await tester.tap(find.text('CLEAR'));
      await tester.pump();
      expect(find.text('Detection Breakdown'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Encyclopedia / Articles', () {
    testWidgets('Tapping an article card opens the reader', (tester) async {
      await pumpScreen(tester, const ScamEncyclopediaScreen());
      final article = ScamEncyclopedia.articles.first;
      await tester.tap(find.text(article.title));
      await tester.pumpAndSettle();
      expect(find.byType(ArticleDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Mark as Read awards the badge', (tester) async {
      final article = ScamEncyclopedia.articles.first;
      await pumpScreen(tester, ArticleDetailScreen(article: article));
      await tester.tap(find.text('Mark as Read & Earn Badge'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Badge earned'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Quiz', () {
    testWidgets('START QUIZ shows questions and NEXT advances',
        (tester) async {
      await pumpScreen(tester, const QuizScreen());
      await tester.tap(find.text('START QUIZ'));
      await tester.pumpAndSettle();
      expect(find.text('Question 1 of 15'), findsOneWidget);

      final question = QuizData.questions.first;
      await tester.tap(find.text(question.options[question.correctIndex].text));
      await tester.pump();
      final next = find.text('NEXT QUESTION →');
      await tester.ensureVisible(next);
      await tester.pump();
      await tester.tap(next);
      await tester.pump();
      expect(find.text('Question 2 of 15'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Learn Hub', () {
    testWidgets('Hub cards navigate to their screens', (tester) async {
      await pumpScreen(tester, const LearnScreen());
      await settleIO(tester);

      await tester.tap(find.text('Encyclopedia'));
      await tester.pumpAndSettle();
      expect(find.text('Scam Encyclopedia'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Awareness Quiz'));
      await tester.pumpAndSettle();
      expect(find.text('Scam Awareness Quiz'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      final badges = find.text('Badges');
      await tester.ensureVisible(badges);
      await tester.pump();
      await tester.tap(badges);
      await tester.pumpAndSettle();
      expect(find.text('Badges & Achievements'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('History', () {
    testWidgets('Swipe to delete removes a record', (tester) async {
      await tester.runAsync(() => ScanRepository().saveScan(ScanRecord(
            inputText: 'Swipe me away',
            classification: 'scam',
            riskScore: 80,
            summary: 'Test record',
            timestamp: DateTime.now(),
          )));
      await settleIO(tester);

      await pumpScreen(tester, const HistoryScreen());
      await settleIO(tester);

      expect(find.text('Swipe me away'), findsOneWidget);
      await tester.drag(find.text('Swipe me away'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await settleIO(tester);
      await tester.pump();
      expect(find.text('Swipe me away'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Clear history button shows confirm dialog and deletes',
        (tester) async {
      await tester.runAsync(() => ScanRepository().saveScan(ScanRecord(
            inputText: 'To be cleared',
            classification: 'safe',
            riskScore: 5,
            summary: 'Test record',
            timestamp: DateTime.now(),
          )));
      await settleIO(tester);

      await pumpScreen(tester, const HistoryScreen());
      await settleIO(tester);

      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Clear Scan History?'), findsOneWidget);

      await tester.tap(find.text('Delete All'));
      await tester.pumpAndSettle();
      await settleIO(tester);
      await tester.pump();
      expect(find.text('To be cleared'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Profile', () {
    testWidgets('Privacy & Data row navigates', (tester) async {
      await pumpScreen(tester, const ProfileScreen());
      await settleIO(tester);
      await tester.ensureVisible(find.text('Privacy & Data'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Privacy & Data'));
      await tester.pump(const Duration(milliseconds: 300));
      await settleIO(tester);
      expect(find.byType(PrivacyDataScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Scan History row navigates', (tester) async {
      await pumpScreen(tester, const ProfileScreen());
      await settleIO(tester);
      await tester.ensureVisible(find.text('Scan History'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Scan History'));
      await tester.pump(const Duration(milliseconds: 300));
      await settleIO(tester);
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sign Out navigates back to login', (tester) async {
      await pumpScreen(tester, const ProfileScreen());
      await settleIO(tester);
      await tester.ensureVisible(find.text('Secure Sign Out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Secure Sign Out'));
      await tester.pumpAndSettle();
      expect(find.text('Secure Sign Out?'), findsOneWidget);
      await tester.tap(find.text('Sign Out'));
      await settleIO(tester);
      await tester.pump();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Privacy & Data', () {
    testWidgets('Retention option saves and snackbars', (tester) async {
      await pumpScreen(tester, const PrivacyDataScreen());
      await settleIO(tester);
      await tester.tap(find.text('Delete after 30 days'));
      await tester.pump();
      await settleIO(tester);
      expect(find.textContaining('deleted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Main navigation tabs', () {
    testWidgets('All six tabs switch screens', (tester) async {
      await tester.pumpWidget(const ScamShieldApp(loggedIn: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('SCAN'));
      await tester.pump();
      expect(find.text('Threat Scanner'), findsOneWidget);

      await tester.tap(find.text('APK SCAN'));
      await tester.pump();
      expect(find.text('APK Scanner'), findsOneWidget);

      await tester.tap(find.text('HISTORY'));
      await settleIO(tester);
      expect(find.text('History'), findsOneWidget);

      await tester.tap(find.text('LEARN'));
      await settleIO(tester);
      expect(find.text('LEARNING HUB'), findsOneWidget);

      await tester.tap(find.text('PROFILE'));
      await settleIO(tester);
      expect(find.text('EDIT INTELLIGENCE PROFILE'), findsOneWidget);

      await tester.tap(find.text('HOME'));
      await tester.pump();
      expect(find.text('Quick Actions'), findsOneWidget);
      await settleIO(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
