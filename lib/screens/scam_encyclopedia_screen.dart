// lib/screens/scam_encyclopedia_screen.dart
// Scam Encyclopedia: browsable library of scam-education articles.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../data/education/scam_encyclopedia.dart';
import '../data/education/models/scam_article.dart';
import 'article_detail_screen.dart';

class ScamEncyclopediaScreen extends StatefulWidget {
  const ScamEncyclopediaScreen({super.key});

  @override
  State<ScamEncyclopediaScreen> createState() => _ScamEncyclopediaScreenState();
}

class _ScamEncyclopediaScreenState extends State<ScamEncyclopediaScreen> {
  String _selectedCategory = 'All';

  List<String> get _categories {
    final cats = ScamEncyclopedia.articles.map((a) => a.category).toSet().toList()
      ..sort();
    return ['All', ...cats];
  }

  List<ScamArticle> get _filteredArticles {
    if (_selectedCategory == 'All') return ScamEncyclopedia.articles;
    return ScamEncyclopedia.byCategory(_selectedCategory);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scam Encyclopedia', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '${ScamEncyclopedia.articles.length} guides to help you recognise and defeat every major scam type.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ),
          _buildCategoryChips(),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: _filteredArticles.length,
              itemBuilder: (ctx, i) {
                final article = _filteredArticles[i];
                return _buildArticleCard(article);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final category = _categories[i];
          final isSelected = _selectedCategory == category;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = category),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                category[0].toUpperCase() + category.substring(1).replaceAll('_', ' '),
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildArticleCard(ScamArticle article) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ArticleDetailScreen(article: article)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(child: Text(article.iconEmoji, style: const TextStyle(fontSize: 26))),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(article.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                        article.shortDescription,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildTag(_difficultyLabel(article.difficulty), _difficultyColor(article.difficulty)),
                          const SizedBox(width: 8),
                          _buildTag(
                            article.category.replaceAll('_', ' ').toUpperCase(),
                            AppColors.accent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  String _difficultyLabel(Difficulty d) => switch (d) {
        Difficulty.beginner => 'BEGINNER',
        Difficulty.intermediate => 'INTERMEDIATE',
        Difficulty.advanced => 'ADVANCED',
      };

  Color _difficultyColor(Difficulty d) => switch (d) {
        Difficulty.beginner => AppColors.success,
        Difficulty.intermediate => AppColors.warning,
        Difficulty.advanced => AppColors.danger,
      };
}
