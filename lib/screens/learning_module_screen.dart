import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../widgets/premium_cta.dart';

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
    if (_selectedOptionIndex != null) return;

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
        title: Text(widget.module.title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.cobalt,
          labelColor: AppColors.cobalt,
          unselectedLabelColor: AppColors.mutedText,
          labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13),
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
          Reveal(
            delay: Reveal.step(0),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(m.icon, color: AppColors.cobalt, size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.title, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text(m.subtitle, style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Reveal(
            delay: Reveal.step(1),
            child: Text('Key Defense Principles', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ),
          const SizedBox(height: 12),
          ...m.keyTakeaways.asMap().entries.map((entry) => Reveal(
                delay: Reveal.step(entry.key + 2, baseMs: 80),
                offsetY: 14,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.verified_rounded, color: AppColors.safeEmerald, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(entry.value, style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.4, color: AppColors.textPrimary))),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 24),
          Reveal(
            delay: Reveal.step(6),
            child: Text('Detailed Intelligence Report', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ),
          const SizedBox(height: 12),
          Reveal(
            delay: Reveal.step(7),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                m.fullLessonText,
                style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13, height: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Reveal(
            delay: Reveal.step(8),
            child: PremiumCTA(
              label: "PROCEED TO QUIZ →",
              onPressed: () => _tabController.animateTo(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizTab() {
    final questions = widget.module.quizQuestions;

    if (_quizCompleted) {
      final percentage = ((_score / questions.length) * 100).toInt();
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
                style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'You scored $_score / ${questions.length} ($percentage%)',
                style: GoogleFonts.plusJakartaSans(
                  color: passed ? AppColors.safeEmerald : AppColors.warning,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              PremiumCTA(
                label: passed ? 'Complete & Return' : 'Retry Quiz',
                onPressed: () {
                  if (passed) {
                    Navigator.pop(context);
                  } else {
                    _resetQuiz();
                  }
                },
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
                style: GoogleFonts.plusJakartaSans(color: AppColors.mutedText, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              Text('Score: $_score', style: GoogleFonts.plusJakartaSans(color: AppColors.cobalt, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_currentQuestionIndex + 1) / questions.length,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cobalt),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              currentQ.question,
              style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.bold, height: 1.4, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 20),
          ...List.generate(currentQ.options.length, (i) {
            final isSelected = _selectedOptionIndex == i;
            final isCorrectOption = i == currentQ.correctIndex;

            Color borderColor = AppColors.border;
            Color bgColor = AppColors.surface;

            if (_selectedOptionIndex != null) {
              if (isCorrectOption) {
                borderColor = AppColors.safeEmerald;
                bgColor = AppColors.safeEmerald.withValues(alpha: 0.12);
              } else if (isSelected) {
                borderColor = AppColors.danger;
                bgColor = AppColors.danger.withValues(alpha: 0.12);
              }
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => _submitAnswer(i),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? AppColors.cobalt : AppColors.background,
                        ),
                        child: Center(
                          child: Text(
                            String.fromCharCode(65 + i),
                            style: GoogleFonts.plusJakartaSans(
                              color: isSelected ? Colors.white : AppColors.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          currentQ.options[i],
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
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
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _selectedOptionIndex == currentQ.correctIndex ? AppColors.safeEmerald : AppColors.danger,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedOptionIndex == currentQ.correctIndex ? '✓ Correct Decision' : '✕ Incorrect Analysis',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.bold,
                      color: _selectedOptionIndex == currentQ.correctIndex ? AppColors.safeEmerald : AppColors.danger,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(currentQ.explanation, style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            PremiumCTA(
              label: _currentQuestionIndex < questions.length - 1 ? 'NEXT QUESTION →' : 'SEE RESULTS →',
              onPressed: _nextQuestion,
            ),
          ],
        ],
      ),
    );
  }
}
