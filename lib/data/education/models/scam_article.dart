// lib/data/education/models/scam_article.dart

/// A single educational article in the Scam Encyclopedia.
class ScamArticle {
  final String id;
  final String title;
  final String shortDescription;
  final String content;
  final String category; // 'phishing' | 'vishing' | 'smishing' | 'lottery' | 'job' | 'romance' | 'tech_support' | 'investment'
  final Difficulty difficulty;
  final String badgeId;
  final String iconEmoji;

  const ScamArticle({
    required this.id,
    required this.title,
    required this.shortDescription,
    required this.content,
    required this.category,
    required this.difficulty,
    required this.badgeId,
    required this.iconEmoji,
  });
}

enum Difficulty { beginner, intermediate, advanced }
