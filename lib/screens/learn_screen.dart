// lib/screens/learn_screen.dart

import 'package:flutter/material.dart';
import '../theme.dart';
import '../data/education/scam_encyclopedia.dart';
import '../data/education/quiz_data.dart';
import '../data/education/daily_tips.dart';
import '../data/education/progress_service.dart';
import '../data/education/models/scam_article.dart';
import '../data/education/models/quiz_question.dart';
import '../data/education/models/user_progress.dart';
import '../widgets/offline_banner.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  final ProgressService _progressService = ProgressService();
  UserProgress _progress = const UserProgress();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final p = await _progressService.load();
    await _progressService.updateStreak();
    final updated = await _progressService.load();
    setState(() {
      _progress = updated;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return OfflineBanner(
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Icon(Icons.shield, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('ScamShield', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _loadProgress,
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildVigilanceScore(),
                const SizedBox(height: 20),
                _buildDailyTip(),
                const SizedBox(height: 24),
                _buildBadgesSection(),
                const SizedBox(height: 24),
                _buildQuizSection(),
                const SizedBox(height: 24),
                const Text('📚 Scam Encyclopedia',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Tap any article to learn more',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 16),
                ...ScamEncyclopedia.articles.map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildArticleCard(a),
                    )),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVigilanceScore() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            height: 90,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _progress.vigilanceScore / 100,
                  strokeWidth: 7,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
                Text(
                  '${_progress.vigilanceScore}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_progress.rank,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  '🔥 ${_progress.streakDays}-day streak  •  ${_progress.totalPoints} pts',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_progress.articlesRead.length}/${ScamEncyclopedia.articles.length} articles  •  ${_progress.quizzesPassedCount} quizzes passed',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyTip() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accent.withOpacity(0.3), AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, color: AppColors.warning, size: 16),
              SizedBox(width: 6),
              Text('TIP OF THE DAY',
                  style: TextStyle(
                      color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            DailyTips.getTodaysTip(),
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgesSection() {
    final earned = _progress.badgesEarned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('🏆 Badges', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('${earned.length}/${ProgressService.allBadges.length}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: ProgressService.allBadges.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final badge = ProgressService.allBadges[i];
              final isEarned = earned.contains(badge.id);
              return Tooltip(
                message: isEarned ? badge.description : 'Locked: ${badge.description}',
                child: Container(
                  width: 68,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isEarned ? AppColors.primary.withOpacity(0.15) : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isEarned
                          ? AppColors.primary.withOpacity(0.5)
                          : AppColors.textSecondary.withOpacity(0.15),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isEarned ? badge.emoji : '🔒',
                        style: const TextStyle(fontSize: 24),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        badge.name,
                        style: TextStyle(
                          fontSize: 8,
                          color: isEarned ? Colors.white : AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQuizSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🧠 CHALLENGE MODE',
                  style: TextStyle(
                      color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Test Your Knowledge',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            '${QuizData.questions.length} questions covering phishing, smishing, UPI fraud, and more.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildQuizStat('${_progress.quizzesTaken}', 'Taken'),
              const SizedBox(width: 24),
              _buildQuizStat('${_progress.quizzesPassedCount}', 'Passed'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _startQuiz(context),
              icon: const Icon(Icons.play_arrow, color: Colors.black),
              label: const Text('START QUIZ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildArticleCard(ScamArticle article) {
    final isRead = _progress.articlesRead.contains(article.id);
    final difficultyColor = _difficultyColor(article.difficulty);
    return GestureDetector(
      onTap: () => _openArticle(context, article),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRead ? AppColors.success.withOpacity(0.2) : AppColors.textSecondary.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Text(article.iconEmoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(article.title,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                      if (isRead)
                        const Icon(Icons.check_circle, color: AppColors.success, size: 16),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(article.shortDescription,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: difficultyColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      article.difficulty.name.toUpperCase(),
                      style: TextStyle(
                          color: difficultyColor, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Color _difficultyColor(Difficulty d) {
    switch (d) {
      case Difficulty.beginner:
        return AppColors.success;
      case Difficulty.intermediate:
        return AppColors.warning;
      case Difficulty.advanced:
        return AppColors.danger;
    }
  }

  void _openArticle(BuildContext context, ScamArticle article) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ArticleDetailScreen(
          article: article,
          progressService: _progressService,
          onRead: () => _loadProgress(),
        ),
      ),
    );
  }

  void _startQuiz(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _QuizScreen(
          questions: QuizData.questions,
          progressService: _progressService,
          onComplete: () => _loadProgress(),
        ),
      ),
    );
  }
}

// ── Article Detail Screen ──────────────────────────────────────────────────

class _ArticleDetailScreen extends StatefulWidget {
  final ScamArticle article;
  final ProgressService progressService;
  final VoidCallback onRead;

  const _ArticleDetailScreen({
    required this.article,
    required this.progressService,
    required this.onRead,
  });

  @override
  State<_ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<_ArticleDetailScreen> {
  bool _marked = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.article.title),
        actions: [
          if (!_marked)
            TextButton.icon(
              onPressed: _markRead,
              icon: const Icon(Icons.check, color: AppColors.primary),
              label: const Text('Mark Read', style: TextStyle(color: AppColors.primary)),
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.check_circle, color: AppColors.success),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(widget.article.iconEmoji, style: const TextStyle(fontSize: 40)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(widget.article.shortDescription,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                widget.article.content,
                style: const TextStyle(height: 1.7, fontSize: 14),
              ),
            ),
            const SizedBox(height: 24),
            if (!_marked)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _markRead,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('✓ Mark as Read & Earn Badge',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _markRead() async {
    await widget.progressService.markArticleRead(widget.article.id, widget.article.badgeId);
    setState(() => _marked = true);
    widget.onRead();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Badge earned! ${widget.article.badgeId.replaceAll('_', ' ').toUpperCase()}'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}

// ── Quiz Screen ────────────────────────────────────────────────────────────

class _QuizScreen extends StatefulWidget {
  final List<QuizQuestion> questions;
  final ProgressService progressService;
  final VoidCallback onComplete;

  const _QuizScreen({
    required this.questions,
    required this.progressService,
    required this.onComplete,
  });

  @override
  State<_QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<_QuizScreen> {
  int _currentIndex = 0;
  int _selectedOption = -1;
  bool _answered = false;
  int _correctCount = 0;
  final DateTime _startTime = DateTime.now();

  QuizQuestion get _current => widget.questions[_currentIndex];

  @override
  Widget build(BuildContext context) {
    final progress = (_currentIndex + 1) / widget.questions.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('Question ${_currentIndex + 1} / ${widget.questions.length}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(_current.question,
                  style: const TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 20),
            ..._current.options.asMap().entries.map((e) => _buildOption(e.key, e.value)),
            const SizedBox(height: 20),
            if (_answered) _buildExplanation(),
            const SizedBox(height: 20),
            if (_answered)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _nextQuestion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    _currentIndex < widget.questions.length - 1 ? 'NEXT QUESTION →' : 'SEE RESULTS',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(int index, QuizOption option) {
    Color borderColor = AppColors.textSecondary.withOpacity(0.2);
    Color bgColor = AppColors.surface;
    IconData? trailingIcon;
    Color iconColor = Colors.white;

    if (_answered) {
      if (option.isCorrect) {
        borderColor = AppColors.success;
        bgColor = AppColors.success.withOpacity(0.1);
        trailingIcon = Icons.check_circle;
        iconColor = AppColors.success;
      } else if (index == _selectedOption && !option.isCorrect) {
        borderColor = AppColors.danger;
        bgColor = AppColors.danger.withOpacity(0.1);
        trailingIcon = Icons.cancel;
        iconColor = AppColors.danger;
      }
    } else if (index == _selectedOption) {
      borderColor = AppColors.primary;
      bgColor = AppColors.primary.withOpacity(0.1);
    }

    return GestureDetector(
      onTap: _answered ? null : () => _selectOption(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderColor),
                color: index == _selectedOption && !_answered
                    ? AppColors.primary
                    : Colors.transparent,
              ),
              child: Center(
                child: Text(
                  ['A', 'B', 'C', 'D'][index],
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(option.text, style: const TextStyle(fontSize: 14))),
            if (trailingIcon != null) Icon(trailingIcon, color: iconColor, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanation() {
    final isCorrect = _current.options[_selectedOption].isCorrect;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCorrect ? AppColors.success.withOpacity(0.08) : AppColors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCorrect ? AppColors.success.withOpacity(0.3) : AppColors.danger.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isCorrect ? '✅ Correct!' : '❌ Incorrect',
              style: TextStyle(
                  color: isCorrect ? AppColors.success : AppColors.danger,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_current.explanation,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }

  void _selectOption(int index) {
    setState(() {
      _selectedOption = index;
      _answered = true;
      if (_current.options[index].isCorrect) _correctCount++;
    });
  }

  void _nextQuestion() {
    if (_currentIndex < widget.questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOption = -1;
        _answered = false;
      });
    } else {
      _finishQuiz();
    }
  }

  void _finishQuiz() async {
    final result = QuizResult(
      totalQuestions: widget.questions.length,
      correctAnswers: _correctCount,
      timeTaken: DateTime.now().difference(_startTime),
    );
    await widget.progressService.recordQuizResult(result);
    widget.onComplete();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => _QuizResultScreen(result: result),
      ),
    );
  }
}

// ── Quiz Result Screen ─────────────────────────────────────────────────────

class _QuizResultScreen extends StatelessWidget {
  final QuizResult result;

  const _QuizResultScreen({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result.passed ? AppColors.success : AppColors.danger;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
            Text(result.passed ? '🏆' : '📖', style: const TextStyle(fontSize: 80)),
            const SizedBox(height: 24),
            Text('${result.score}%',
                style: TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 8),
            Text(result.passed ? 'Quiz Passed!' : 'Keep Practising',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(
              '${result.correctAnswers} / ${result.totalQuestions} correct',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('BACK TO LEARN',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
