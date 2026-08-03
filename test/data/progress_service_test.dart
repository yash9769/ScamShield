// test/data/progress_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/data/education/progress_service.dart';
import 'package:scamshield/data/education/models/quiz_question.dart';

void main() {
  group('ProgressService — Badge definitions', () {
    test('all badges have non-empty ids', () {
      for (final badge in ProgressService.allBadges) {
        expect(badge.id, isNotEmpty);
        expect(badge.name, isNotEmpty);
        expect(badge.emoji, isNotEmpty);
      }
    });

    test('badge count is 13', () {
      expect(ProgressService.allBadges.length, equals(13));
    });
  });

  group('QuizResult — scoring', () {
    test('100% score is 100', () {
      final result = QuizResult(
        totalQuestions: 10,
        correctAnswers: 10,
        timeTaken: const Duration(minutes: 5),
      );
      expect(result.score, equals(100));
      expect(result.passed, isTrue);
    });

    test('70% score passes', () {
      final result = QuizResult(
        totalQuestions: 10,
        correctAnswers: 7,
        timeTaken: const Duration(minutes: 5),
      );
      expect(result.score, equals(70));
      expect(result.passed, isTrue);
    });

    test('60% score fails', () {
      final result = QuizResult(
        totalQuestions: 10,
        correctAnswers: 6,
        timeTaken: const Duration(minutes: 5),
      );
      expect(result.score, equals(60));
      expect(result.passed, isFalse);
    });

    test('0% score is 0', () {
      final result = QuizResult(
        totalQuestions: 5,
        correctAnswers: 0,
        timeTaken: const Duration(minutes: 2),
      );
      expect(result.score, equals(0));
      expect(result.passed, isFalse);
    });
  });
}
