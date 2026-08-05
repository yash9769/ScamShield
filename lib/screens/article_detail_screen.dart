// lib/screens/article_detail_screen.dart
// Full-length scam article reader with "Mark as Read & Earn Badge".

import 'package:flutter/material.dart';
import '../theme.dart';
import '../data/education/models/scam_article.dart';
import '../data/education/progress_service.dart';

class ArticleDetailScreen extends StatefulWidget {
  final ScamArticle article;

  const ArticleDetailScreen({super.key, required this.article});

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  final ProgressService _progressService = ProgressService();
  bool _isLoading = true;
  bool _isRead = false;
  String? _earnedBadgeName;

  @override
  void initState() {
    super.initState();
    _checkReadStatus();
  }

  Future<void> _checkReadStatus() async {
    final progress = await _progressService.load();
    if (mounted) {
      setState(() {
        _isRead = progress.articlesRead.contains(widget.article.id);
        _isLoading = false;
      });
    }
  }

  Future<void> _markAsRead() async {
    setState(() => _isLoading = true);
    await _progressService.markArticleRead(
      widget.article.id,
      widget.article.badgeId,
    );

    if (!mounted) return;
    setState(() {
      _isRead = true;
      _isLoading = false;
    });

    final badge = ProgressService.allBadges
        .where((b) => b.id == widget.article.badgeId)
        .firstOrNull;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          badge != null
              ? 'Badge earned: ${badge.emoji} ${badge.name} (+10 points)'
              : 'Marked as read (+10 points)',
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );

    setState(() => _earnedBadgeName = badge?.name);
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    return Scaffold(
      appBar: AppBar(
        title: Text(article.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
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
                  Text(article.iconEmoji, style: const TextStyle(fontSize: 40)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(article.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(article.shortDescription, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildContent(article.content),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: (_isRead || _isLoading) ? null : _markAsRead,
                icon: Icon(
                  _isRead ? Icons.verified_rounded : Icons.military_tech_rounded,
                  color: Colors.black,
                ),
                label: Text(
                  _isRead
                      ? (_earnedBadgeName != null ? '✓ ${_earnedBadgeName!} Badge Earned' : '✓ Marked as Read')
                      : 'Mark as Read & Earn Badge',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRead ? AppColors.success : AppColors.primary,
                  disabledBackgroundColor: AppColors.success.withValues(alpha: 0.5),
                  disabledForegroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(String content) {
    final blocks = content.split(RegExp(r'\n\s*\n'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((block) {
        final trimmed = block.trim();
        if (trimmed.isEmpty) return const SizedBox.shrink();

        final lines = trimmed.split('\n').map((l) => l.trim()).toList();
        final heading = lines.first;

        if (heading.startsWith('**') && heading.endsWith('**')) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              heading.replaceAll('**', ''),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          );
        }

        if (trimmed.startsWith('- ')) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines
                  .where((l) => l.startsWith('- '))
                  .map((l) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 7),
                              child: Icon(Icons.circle, size: 6, color: AppColors.primary),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l.substring(2),
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            trimmed,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.7),
          ),
        );
      }).toList(),
    );
  }
}
