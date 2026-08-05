// lib/screens/learning_module_screen.dart
// Interactive learning module screen: Learning Content First -> Knowledge Check Quiz.

import 'package:flutter/material.dart';
import '../theme.dart';

class QuizQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const QuizQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}

class LearningModuleData {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> keyTakeaways;
  final String fullLessonText;
  final List<QuizQuestion> quizQuestions;

  const LearningModuleData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.keyTakeaways,
    required this.fullLessonText,
    required this.quizQuestions,
  });
}

class LearningModuleScreen extends StatefulWidget {
  final LearningModuleData module;

  const LearningModuleScreen({super.key, required this.module});

  @override
  State<LearningModuleScreen> createState() => _LearningModuleScreenState();
}

class _LearningModuleScreenState extends State<LearningModuleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Quiz state
  int _currentQuestionIndex = 0;
  int? _selectedOptionIndex;
  int _score = 0;
  bool _quizCompleted = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _submitAnswer(int optionIndex) {
    if (_selectedOptionIndex != null) return; // already answered this question

    final currentQ = widget.module.quizQuestions[_currentQuestionIndex];
    setState(() {
      _selectedOptionIndex = optionIndex;
      if (optionIndex == currentQ.correctIndex) {
        _score++;
      }
    });
  }

  void _nextQuestion() {
    if (_currentQuestionIndex < widget.module.quizQuestions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _selectedOptionIndex = null;
      });
    } else {
      setState(() {
        _quizCompleted = true;
      });
    }
  }

  void _resetQuiz() {
    setState(() {
      _currentQuestionIndex = 0;
      _selectedOptionIndex = null;
      _score = 0;
      _quizCompleted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.module.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.menu_book_rounded), text: '1. Learn Concept'),
            Tab(icon: Icon(Icons.quiz_rounded), text: '2. Knowledge Check'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLessonTab(),
          _buildQuizTab(),
        ],
      ),
    );
  }

  Widget _buildLessonTab() {
    final m = widget.module;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary.withValues(alpha: 0.15), AppColors.surface],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(m.icon, color: AppColors.primary, size: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(m.subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Key Defense Principles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...m.keyTakeaways.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.verified, color: AppColors.success, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(t, style: const TextStyle(fontSize: 14, height: 1.5))),
                  ],
                ),
              )),
          const SizedBox(height: 24),
          const Text('Detailed Intelligence Report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              m.fullLessonText,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.7),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                _tabController.animateTo(1);
              },
              icon: const Icon(Icons.arrow_forward, color: Colors.black),
              label: const Text('PROCEED TO QUIZ →', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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

  Widget _buildQuizTab() {
    final questions = widget.module.quizQuestions;

    if (_quizCompleted) {
      final percentage = questions.isEmpty
          ? 100
          : ((_score / questions.length) * 100).toInt();
      final passed = percentage >= 70;

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(passed ? '🏆' : '📚', style: const TextStyle(fontSize: 60)),
              const SizedBox(height: 16),
              Text(
                passed ? 'Module Passed!' : 'Review & Retry',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'You scored $_score / ${questions.length} ($percentage%)',
                style: TextStyle(
                  color: passed ? AppColors.success : AppColors.warning,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  if (passed) {
                    Navigator.pop(context);
                  } else {
                    _resetQuiz();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  passed ? 'Complete & Return' : 'Retry Quiz',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final currentQ = questions[_currentQuestionIndex];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Question ${_currentQuestionIndex + 1} of ${questions.length}',
                style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
              ),
              Text('Score: $_score', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_currentQuestionIndex + 1) / questions.length,
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
            child: Text(
              currentQ.question,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          ...List.generate(currentQ.options.length, (i) {
            final isSelected = _selectedOptionIndex == i;
            final isCorrectOption = i == currentQ.correctIndex;

            Color borderColor = Colors.transparent;
            Color bgColor = AppColors.surface;

            if (_selectedOptionIndex != null) {
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
                onTap: () => _submitAnswer(i),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
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
                      Expanded(
                        child: Text(
                          currentQ.options[i],
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (_selectedOptionIndex != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _selectedOptionIndex == currentQ.correctIndex ? AppColors.success : AppColors.danger,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedOptionIndex == currentQ.correctIndex ? '✅ Correct!' : '❌ Incorrect',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _selectedOptionIndex == currentQ.correctIndex ? AppColors.success : AppColors.danger,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(currentQ.explanation, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _nextQuestion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _currentQuestionIndex < questions.length - 1 ? 'NEXT QUESTION →' : 'SEE RESULTS →',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
