// lib/screens/quiz_screen.dart
// Full 15-question scam awareness quiz backed by QuizData + ProgressService.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../data/education/quiz_data.dart';
import '../data/education/models/quiz_question.dart';
import '../data/education/progress_service.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final ProgressService _progressService = ProgressService();

  bool _started = false;
  int _questionIndex = 0;
  int? _selectedOptionIndex;
  int _correctCount = 0;
  bool _finished = false;
  bool _isRecording = false;
  int _pointsEarned = 0;
  int _totalPoints = 0;

  List<QuizQuestion> get _questions => QuizData.questions;

  void _startQuiz() {
    setState(() {
      _started = true;
      _questionIndex = 0;
      _selectedOptionIndex = null;
      _correctCount = 0;
      _finished = false;
      _pointsEarned = 0;
    });
  }

  void _selectOption(int index) {
    if (_selectedOptionIndex != null) return;
    setState(() {
      _selectedOptionIndex = index;
      if (index == _questions[_questionIndex].correctIndex) {
        _correctCount++;
      }
    });
  }

  Future<void> _next() async {
    if (_questionIndex < _questions.length - 1) {
      setState(() {
        _questionIndex++;
        _selectedOptionIndex = null;
      });
    } else {
      await _finish();
    }
  }

  Future<void> _finish() async {
    setState(() {
      _finished = true;
      _isRecording = true;
    });
    final result = QuizResult(
      totalQuestions: _questions.length,
      correctAnswers: _correctCount,
      timeTaken: Duration.zero,
    );
    try {
      final progress = await _progressService.recordQuizResult(result);
      if (mounted) {
        setState(() {
          _isRecording = false;
          _pointsEarned = _correctCount * 5 + (result.passed ? 50 : 0);
          _totalPoints = progress.totalPoints;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _pointsEarned = _correctCount * 5;
          _totalPoints = 0;
        });
      }
    }
  }

  void _retry() {
    setState(() {
      _started = false;
      _questionIndex = 0;
      _selectedOptionIndex = null;
      _correctCount = 0;
      _finished = false;
      _pointsEarned = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scam Awareness Quiz', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: !_started
          ? _buildIntro()
          : _finished
              ? _buildResults()
              : _buildQuestion(),
    );
  }

  Widget _buildIntro() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.quiz_rounded, color: AppColors.primary, size: 56),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Test Your Scam IQ', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Answer ${_questions.length} real-world scam scenarios. Score 70% or higher to earn the Quiz Master badge and 50 bonus points.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildFact(Icons.question_answer_rounded, '${_questions.length} Questions'),
              const SizedBox(width: 16),
              _buildFact(Icons.emoji_events_rounded, '70% to Pass'),
              const SizedBox(width: 16),
              _buildFact(Icons.stars_rounded, '+5 pts / correct'),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _startQuiz,
              icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
              label: const Text('START QUIZ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFact(IconData icon, String text) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion() {
    final question = _questions[_questionIndex];
    final hasAnswered = _selectedOptionIndex != null;
    final isCorrect = hasAnswered && _selectedOptionIndex == question.correctIndex;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Question ${_questionIndex + 1} of ${_questions.length}',
                style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
              ),
              Text('Score: $_correctCount', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_questionIndex + 1) / _questions.length,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Text(question.question, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.5)),
          ),
          const SizedBox(height: 20),
          ...List.generate(question.options.length, (i) {
            final option = question.options[i];
            final isSelected = _selectedOptionIndex == i;
            final isCorrectOption = i == question.correctIndex;

            Color borderColor = Colors.transparent;
            Color bgColor = AppColors.surface;
            if (hasAnswered) {
              if (isCorrectOption) {
                borderColor = AppColors.success;
                bgColor = AppColors.success.withValues(alpha: 0.1);
              } else if (isSelected) {
                borderColor = AppColors.danger;
                bgColor = AppColors.danger.withValues(alpha: 0.1);
              }
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () => _selectOption(i),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor)),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? AppColors.primary : AppColors.background,
                        ),
                        child: Center(
                          child: Text(
                            String.fromCharCode(65 + i),
                            style: TextStyle(
                              color: isSelected ? Colors.black : AppColors.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Text(option.text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                      if (hasAnswered && isCorrectOption)
                        const Icon(Icons.check_circle, color: AppColors.success, size: 20)
                      else if (hasAnswered && isSelected)
                        const Icon(Icons.cancel, color: AppColors.danger, size: 20),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (hasAnswered) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isCorrect ? AppColors.success : AppColors.danger),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCorrect ? '✅ Correct!' : '❌ Incorrect',
                    style: TextStyle(fontWeight: FontWeight.bold, color: isCorrect ? AppColors.success : AppColors.danger),
                  ),
                  const SizedBox(height: 6),
                  Text(question.explanation, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _questionIndex < _questions.length - 1 ? 'NEXT QUESTION →' : 'SEE RESULTS →',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResults() {
    final percentage = ((_correctCount / _questions.length) * 100).toInt();
    final passed = percentage >= 70;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(passed ? '🏆' : '📚', style: const TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              passed ? 'Quiz Passed!' : 'Review & Retry',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'You scored $_correctCount / ${_questions.length} ($percentage%)',
              style: TextStyle(color: passed ? AppColors.success : AppColors.warning, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _resultRow('Correct Answers', '$_correctCount'),
                  const SizedBox(height: 8),
                  _resultRow('Points Earned', _isRecording ? '...' : '+$_pointsEarned'),
                  const SizedBox(height: 8),
                  _resultRow('Total Points', _isRecording ? '...' : '$_totalPoints'),
                  const SizedBox(height: 8),
                  _resultRow('Quiz Master Badge', passed ? '🏆 Unlocked' : 'Locked (need 70%)'),
                ],
              ),
            ),
            if (_isRecording) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(color: AppColors.primary),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: passed ? () => Navigator.pop(context) : _retry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  passed ? 'Complete & Return' : 'Retry Quiz',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}
