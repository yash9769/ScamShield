// lib/data/education/models/quiz_question.dart

/// A single quiz question with multiple choice options.
class QuizQuestion {
  final String id;
  final String question;
  final List<QuizOption> options;
  final String explanation; // Shown after answering
  final String category;

  const QuizQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.explanation,
    required this.category,
  });

  /// Index of the correct option.
  int get correctIndex =>
      options.indexWhere((o) => o.isCorrect);
}

/// A single option within a [QuizQuestion].
class QuizOption {
  final String text;
  final bool isCorrect;

  const QuizOption({required this.text, required this.isCorrect});
}

/// Result of a completed quiz session.
class QuizResult {
  final int totalQuestions;
  final int correctAnswers;
  final Duration timeTaken;

  const QuizResult({
    required this.totalQuestions,
    required this.correctAnswers,
    required this.timeTaken,
  });

  int get score => ((correctAnswers / totalQuestions) * 100).round();
  bool get passed => score >= 70;
}
