// lib/data/education/daily_tips.dart

/// Provides a daily scam awareness tip.
/// 30 tips cycle based on the day of the year.
class DailyTips {
  static const List<String> _tips = [
    '🔐 Never share your OTP with anyone — not even bank representatives.',
    '🎣 Hover over links before clicking to check the real URL destination.',
    '📱 Install apps only from official app stores (Play Store / App Store).',
    '🏦 Your bank will never ask for your PIN, OTP, or full card number over the phone.',
    '🔗 Be suspicious of shortened URLs (bit.ly, tinyurl). Expand them first.',
    "🎰 If you didn't enter a lottery, you didn't win one.",
    '💳 Enable transaction alerts on all your bank accounts and cards.',
    '📧 Check the sender\'s full email address — not just the display name.',
    '🔒 Use a unique password for every account and use a password manager.',
    '📞 Caller ID can be spoofed. A call from your bank\'s number may not be real.',
    '🛡️ Enable two-factor authentication (2FA) on all critical accounts.',
    '💻 Microsoft, Apple, and Google will never call you about your computer.',
    '🔍 Do a reverse image search on online contacts you haven\'t met in person.',
    '💰 No legitimate investment guarantees high returns with zero risk.',
    '🤖 AI can clone voices — verify unusual requests via a different channel.',
    '📦 Real delivery services don\'t ask for payment via SMS links to release parcels.',
    '🌐 HTTPS (padlock) only means encrypted — a phishing site can have HTTPS too.',
    '💼 Legitimate employers never charge you money to start a job.',
    '🚨 If something feels urgent, that\'s a tactic. Pause and verify.',
    '🔑 Never allow remote access to your device from an unsolicited caller.',
    '💬 UPI collect requests debit your account — approving is NOT receiving.',
    '📵 Register on India\'s DND service to reduce spam calls (1909).',
    '📋 Check investment platforms on SEBI\'s registered intermediaries list.',
    '🧩 Scammers research victims on social media. Keep profiles private.',
    '🏥 Report cybercrime immediately at cybercrime.gov.in or call 1930.',
    '💎 If an offer seems too good to be true, it almost certainly is.',
    '🔄 Regularly update your apps and OS — patches fix security vulnerabilities.',
    '👴 Educate elderly family members — they are disproportionately targeted.',
    '📰 Scam tactics evolve. Stay informed by reading ScamShield\'s encyclopedia.',
    '❤️ Refuse any "emergency" money request from someone you\'ve never met in person.',
  ];

  /// Returns today's tip based on the day of the year.
  static String getTodaysTip() {
    final dayOfYear = _dayOfYear(DateTime.now());
    return _tips[dayOfYear % _tips.length];
  }

  /// Returns the tip for a given [date].
  static String getTipForDate(DateTime date) {
    return _tips[_dayOfYear(date) % _tips.length];
  }

  static int _dayOfYear(DateTime date) {
    return date.difference(DateTime(date.year, 1, 1)).inDays;
  }

  /// Returns all tips (for testing or preview).
  static List<String> get all => List.unmodifiable(_tips);
}
