import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/user_profile_service.dart';
import 'learning_module_screen.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  // Multi-question Spot the Scam Challenge
  int _challengeIndex = 0;
  int _score = 0;

  final List<Map<String, dynamic>> _challenges = [
    {
      'source': 'SMS Message • Today, 10:42 AM',
      'message': '”URGENT: Your Netflix account will be suspended in 24h due to payment failure. Verify details now at: bit.ly/nx-safe-check-99”',
      'question': 'The message looks urgent. Is this a safe message?',
      'isScam': true,
      'explanation': 'SCAM! Real services never demand urgent account updates via shortened bit.ly links in text messages.',
    },
    {
      'source': 'Email • Bank Alert',
      'message': '”Dear Customer, we noticed a new device login to your Chase online banking from Moscow, RU. If this was not you, reset your password immediately.”',
      'question': 'Is this a legitimate security notification?',
      'isScam': false,
      'explanation': 'SAFE ALERT! Standard security alert informing you of unusual activity. Verify by opening your official bank app directly.',
    },
    {
      'source': 'Phone Call • Unknown Number',
      'message': '”Hello, this is officer Davis from IRS Fraud Prevention. There is a warrant for your arrest for unpaid taxes. Pay \$500 in Target gift cards to clear your file.”',
      'question': 'Should you follow the caller instructions?',
      'isScam': true,
      'explanation': 'SCAM! Government agencies like the IRS or Police will NEVER demand payment in gift cards or crypto.',
    },
    {
      'source': 'WhatsApp • Unsaved Contact',
      'message': '”Hi Mom! I lost my phone and wallet. This is my new temporary number. Can you send \$450 via Zelle to help pay my taxi?”',
      'question': 'Is this a safe request to transfer funds?',
      'isScam': true,
      'explanation': 'SCAM! Classic Emergency Impersonation fraud. Always call your relative on their known original phone number to verify first.',
    },
    {
      'source': 'Website Pop-up • Safari',
      'message': '”WARNING! (3) Viruses Detected on your iPhone! System memory corrupted. Tap CLEAN NOW to install Security Cleaner 2026.”',
      'question': 'Is this system warning genuine?',
      'isScam': true,
      'explanation': 'SCAM! Web browsers cannot scan your phone for system viruses. These are rogue scareware ads trying to install malware.',
    },
  ];

  static const _phishingModule = LearningModuleData(
    title: 'Phishing 101',
    subtitle: 'Mastering Psychological Urgency & Identity Scams',
    icon: Icons.link_off,
    keyTakeaways: [
      'Artificial Urgency ("Act within 10 minutes") is designed to bypass logical reasoning.',
      'Scammers use spoofed sender IDs matching known brands like Amazon, FedEx, or Apple.',
      'Never open links directly from unsolicited SMS or email messages.',
    ],
    fullLessonText: '''
Phishing is the practice of sending fraud messages designed to trick victims into revealing sensitive information such as passwords, credit card numbers, or social security details.

1. Psychological Triggers:
Scammers exploit human emotions — panic ("account frozen"), greed ("you won a \$1,000 gift card"), or authority ("IRS tax audit"). When emotion is triggered, critical thinking drops.

2. Lookalike Domains & Shortened Links:
Attacking links often replace subtle characters (e.g. paypa1.com vs paypal.com or arnbc.com vs ambc.com). Shortened bit.ly or tinyurl links hide the true malicious destination.

3. Verification Golden Rule:
If you receive an alert from any service (Bank, Netflix, Courier), NEVER tap the link in the message. Always open your browser, type the official domain manually, or launch the official mobile app.
''',
    quizQuestions: [
      QuizQuestion(
        question: 'Which of the following is the most common indicator of a phishing email?',
        options: [
          'High urgency demanding immediate action or account closure',
          'Professional greeting using your full legal name',
          'Links leading to domain.com/help',
          'Customer support phone number listed at footer',
        ],
        correctIndex: 0,
        explanation: 'Artificial urgency designed to cause panic is the single biggest indicator of phishing attempts.',
      ),
      QuizQuestion(
        question: 'What is the safest action when you receive an SMS saying your package delivery failed?',
        options: [
          'Tap the link immediately to prevent return to sender',
          'Reply to the SMS asking for the driver name',
          'Ignore the link and check tracking directly on the official courier website or app',
          'Call the phone number included in the text',
        ],
        correctIndex: 2,
        explanation: 'Always verify package tracking through official carrier portals directly.',
      ),
    ],
  );

  static const _urlModule = LearningModuleData(
    title: 'URL Deep Dive',
    subtitle: 'Decoding Web Links & Identifying Spoofed Domains',
    icon: Icons.travel_explore,
    keyTakeaways: [
      'The true domain is located immediately to the left of the extension (.com, .org).',
      'Subdomains like bank.com.fakeportal.net belong to fakeportal.net, NOT bank.com.',
      'HTTPS indicates encrypted connection, NOT that the site owner is trustworthy.',
    ],
    fullLessonText: '''
Understanding URL structures is your strongest weapon against web-based fraud.

1. Anatomy of a URL:
In https://login.secure.bankofamerica.com.auth-verify.net/login:
- Scheme: https://
- Subdomain: login.secure.bankofamerica.com
- Primary Domain: auth-verify.net (THIS IS THE ACTUAL HOST!)

2. Typosquatting:
Scammers register domains with common misspellings (e.g. gogle.com, netfIix.com with capital I) to catch users making typing mistakes.

3. SSL / HTTPS Misconception:
Seeing a padlock icon (HTTPS) only means your communication with that server is encrypted. Anyone can generate free SSL certificates for fake phishing websites.
''',
    quizQuestions: [
      QuizQuestion(
        question: 'Who owns the website https://chase.com.security-alert-99.org?',
        options: [
          'Chase Bank',
          'security-alert-99.org',
          'Apple Inc.',
          'Google Cloud',
        ],
        correctIndex: 1,
        explanation: 'The domain name right before .org is the actual owner: security-alert-99.org.',
      ),
    ],
  );

  static const _bankModule = LearningModuleData(
    title: 'Bank Fraud',
    subtitle: 'Protecting OTPs, Banking Credentials, & MPINs',
    icon: Icons.account_balance_outlined,
    keyTakeaways: [
      'Bank staff will NEVER ask for your 6-digit OTP, password, or card CVV.',
      'Vishing calls often spoof official bank helpline numbers using VoIP services.',
      'Always use biometric authentication and in-app customer support.',
    ],
    fullLessonText: '''
Bank fraud attacks target direct financial loss through social engineering.

1. One-Time Passwords (OTPs):
OTPs act as the final key to authorization. Scammers pretend to be bank security officers helping you "cancel a fraudulent transaction", while actually asking you to read out the OTP to complete their transaction!

2. Caller ID Spoofing:
Caller ID can easily be manipulated using VoIP tools. Even if your caller ID says "Chase Customer Care", do not share confidential details. Hang up and call the number on the back of your debit card.
''',
    quizQuestions: [
      QuizQuestion(
        question: 'A caller claiming to be from your bank security team asks for your OTP to stop a hacker. What should you do?',
        options: [
          'Read out the OTP quickly to stop the transfer',
          'Hang up immediately. Bank staff will never ask for your OTP',
          'Give them a fake 4-digit PIN instead',
          'Ask them to email you the request first',
        ],
        correctIndex: 1,
        explanation: 'No legitimate bank employee will ever ask for your secret OTP under any circumstances.',
      ),
    ],
  );

  void _handleAnswer(bool userTappedYes) {
    final currentChallenge = _challenges[_challengeIndex];
    final isScam = currentChallenge['isScam'] as bool;
    final isCorrect = (userTappedYes && !isScam) || (!userTappedYes && isScam);

    setState(() {
      if (isCorrect) _score++;
    });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isCorrect ? Icons.check_circle : Icons.warning_rounded,
              color: isCorrect ? AppColors.success : AppColors.danger,
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              isCorrect ? 'Correct Analysis!' : 'Security Warning!',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isCorrect ? AppColors.success : AppColors.danger,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(currentChallenge['explanation'] as String, style: const TextStyle(fontSize: 13, height: 1.5)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (_challengeIndex < _challenges.length - 1) {
                setState(() {
                  _challengeIndex++;
                });
              } else {
                _showChallengeCompleteDialog();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(
              _challengeIndex < _challenges.length - 1 ? 'Next Scenario →' : 'View Results 🏆',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showChallengeCompleteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Text('🏆', style: TextStyle(fontSize: 28)),
            SizedBox(width: 10),
            Text('Challenge Complete!', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You scored $_score out of ${_challenges.length}!',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your vigilance score has been updated. Keep practicing daily scenarios to stay sharp against evolving threat tactics.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _challengeIndex = 0;
                _score = 0;
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Restart Quiz', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.shield, color: AppColors.primary),
            SizedBox(width: 8),
            Text('ScamShield', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          ValueListenableBuilder<String>(
            valueListenable: UserProfileService.avatarNotifier,
            builder: (ctx, avatar, _) => CircleAvatar(
              radius: 15,
              backgroundImage: NetworkImage(avatar),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVigilanceScore(),
            const SizedBox(height: 32),
            const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success, size: 18),
                SizedBox(width: 8),
                Text('Daily Safe Protocol', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            _buildProtocolCard(Icons.email_outlined, 'EMAIL SECURITY', 'Always hover over links to verify the actual destination URL before clicking.', AppColors.success),
            const SizedBox(height: 12),
            _buildProtocolCard(Icons.phonelink_lock, 'MFA ADVICE', 'Never share a One-Time Password (OTP) with anyone, even if they claim to be from support.', AppColors.success),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CHALLENGE MODE', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                    Text('Spot the Scam', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Scenario ${_challengeIndex + 1} of ${_challenges.length}', style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildChallengeCard(),
            const SizedBox(height: 32),
            const Text('INTERACTIVE LEARNING MODULES', style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.bold)),
            const Text('Read Concept → Pass Quiz', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildExploreCard(
              context,
              _phishingModule,
            ),
            const SizedBox(height: 16),
            _buildExploreCard(
              context,
              _urlModule,
            ),
            const SizedBox(height: 16),
            _buildExploreCard(
              context,
              _bankModule,
            ),
          ],
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
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: 0.78 + (_score * 0.04).clamp(0.0, 0.2),
                  strokeWidth: 8,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              Column(
                children: [
                  Text('${78 + (_score * 4)}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  const Text('VIGILANCE SCORE', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Elite Defender', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('You’re in the top 5% of secure users this week.', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildProtocolCard(IconData icon, String title, String description, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengeCard() {
    final current = _challenges[_challengeIndex];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.chat_bubble, color: AppColors.accent, size: 16),
                    const SizedBox(width: 8),
                    Text(current['source'] as String, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: const Border(left: BorderSide(color: AppColors.primary, width: 4)),
                  ),
                  child: Text(
                    current['message'] as String,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(current['question'] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _handleAnswer(true),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Safe'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.textSecondary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.danger, AppColors.warning]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () => _handleAnswer(false),
                    icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
                    label: const Text('Scam', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExploreCard(BuildContext context, LearningModuleData module) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(module.icon, color: AppColors.primary, size: 32),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('LESSON + QUIZ', style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(module.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(module.subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LearningModuleScreen(module: module)),
              );
            },
            child: const Row(
              children: [
                Text('START MODULE', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward, color: AppColors.primary, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
