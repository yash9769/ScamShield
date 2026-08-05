// Screen smoke test: every screen builds and renders its core content
// without throwing. DB-backed screens use the FFI SQLite factory.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scamshield/theme.dart';
import 'package:scamshield/data/database/database_helper.dart';
import 'package:scamshield/data/education/scam_encyclopedia.dart';
import 'package:scamshield/screens/scam_encyclopedia_screen.dart';
import 'package:scamshield/screens/article_detail_screen.dart';
import 'package:scamshield/screens/quiz_screen.dart';
import 'package:scamshield/screens/badges_screen.dart';
import 'package:scamshield/screens/history_screen.dart';
import 'package:scamshield/screens/learn_screen.dart';
import 'package:scamshield/screens/profile_screen.dart';
import 'package:scamshield/screens/privacy_data_screen.dart';
import 'package:scamshield/screens/scan_screen.dart';
import 'package:scamshield/screens/image_scan_screen.dart';
import 'package:scamshield/screens/voice_scan_screen.dart';
import 'package:scamshield/screens/batch_scan_screen.dart';

import 'helpers/fake_http.dart';

Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(theme: appTheme, home: screen));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Pumps until [finder] matches or a timeout is reached, allowing async
/// (DB / preferences) init to complete. Uses [tester.runAsync] so real I/O
/// (SQLite) can finish inside the test's fake-async zone.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Widget screen,
  Finder finder, {
  int attempts = 20,
}) async {
  await tester.pumpWidget(MaterialApp(theme: appTheme, home: screen));
  for (var i = 0; i < attempts && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  await tester.pump();
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

  testWidgets('ScamEncyclopediaScreen renders', (tester) async {
    await pumpScreen(tester, const ScamEncyclopediaScreen());
    expect(find.text('Scam Encyclopedia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ArticleDetailScreen renders article', (tester) async {
    final article = ScamEncyclopedia.articles.first;
    await pumpScreen(tester, ArticleDetailScreen(article: article));
    expect(find.text(article.title), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('QuizScreen renders intro', (tester) async {
    await pumpScreen(tester, const QuizScreen());
    expect(find.text('Scam Awareness Quiz'), findsOneWidget);
    expect(find.text('START QUIZ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BadgesScreen renders', (tester) async {
    await pumpScreen(tester, const BadgesScreen());
    expect(find.text('Badges & Achievements'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HistoryScreen renders', (tester) async {
    await pumpUntilFound(tester, const HistoryScreen(), find.text('All Scans'));
    expect(find.text('History'), findsOneWidget);
    expect(find.text('All Scans'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LearnScreen renders', (tester) async {
    await pumpUntilFound(
        tester, const LearnScreen(), find.text('VIGILANCE SCORE'));
    expect(find.text('VIGILANCE SCORE'), findsOneWidget);
    expect(find.text('LEARNING HUB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProfileScreen renders', (tester) async {
    await pumpUntilFound(
        tester, const ProfileScreen(), find.text('EDIT INTELLIGENCE PROFILE'));
    expect(find.text('EDIT INTELLIGENCE PROFILE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PrivacyDataScreen renders', (tester) async {
    await pumpUntilFound(
        tester, const PrivacyDataScreen(), find.text('Privacy & Data'));
    expect(find.text('Privacy & Data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ScanScreen renders', (tester) async {
    await pumpScreen(tester, const ScanScreen());
    expect(find.text('Threat Scanner'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ImageScanScreen renders', (tester) async {
    await pumpScreen(tester, const ImageScanScreen());
    expect(find.text('Image Scanner'), findsOneWidget);
    expect(find.text('No image selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('VoiceScanScreen renders', (tester) async {
    await pumpScreen(tester, const VoiceScanScreen());
    expect(find.text('Voice Scanner'), findsOneWidget);
    expect(find.text('No audio selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BatchScanScreen renders', (tester) async {
    await pumpScreen(tester, const BatchScanScreen());
    expect(find.text('Batch Scanner'), findsOneWidget);
    expect(find.text('0/20 messages'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
