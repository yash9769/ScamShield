import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../widgets/premium_cta.dart';
import '../services/user_profile_service.dart';
import 'learning_module_screen.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
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
      'message': '”Dear Customer, we noticed a new device login to your online banking from Moscow, RU. If this was not you, check your account settings.”',
      'question': 'Is this a legitimate security notification?',
      'isScam': false,
      'explanation': 'SAFE ALERT! Standard security alert informing you of unusual activity. Verify by opening your official bank app directly.',
    },
    {
      'source': 'Phone Call • Unknown Number',
      'message': '”Hello, this is officer Davis from IRS Fraud Prevention. Pay \$500 in Target gift cards immediately to clear your tax arrest warrant.”',
      'question': 'Should you follow the caller instructions?',
      'isScam': true,
      'explanation': 'SCAM! Government agencies like the IRS or Police will NEVER demand payment in gift cards or crypto.',
    },
    {
      'source': 'WhatsApp • Unsaved Contact',
      'message': '”Hi Mom! I lost my phone and wallet. This is my temporary number. Can you send \$450 via Zelle to pay my taxi?”',
      'question': 'Is this a safe request to transfer funds?',
      'isScam': true,
      'explanation': 'SCAM! Classic Emergency Impersonation fraud. Always call your relative on their known original phone number to verify first.',
    },
  ];

  static const _phishingModule = LearningModuleData(
    title: 'Phishing 101',
    subtitle: 'Mastering Psychological Urgency & Identity Scams',
    icon: Icons.link_off_rounded,
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
Attacking links often replace subtle characters (e.g. paypa1.com vs paypal.com). Shortened bit.ly or tinyurl links hide the true malicious destination.

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
    title: 'URL & Web Safety',
    subtitle: 'Spotting Malicious Domains & Typosquatting',
    icon: Icons.public_rounded,
    keyTakeaways: [
      'Typosquatting replaces subtle characters (e.g., "rn" looking like "m").',
      'HTTPS encrypts traffic but DOES NOT mean the website is legitimate.',
      'Top-Level Domains like .top, .xyz, .cc are heavily abused by scammers.',
    ],
    fullLessonText: '''
Websites can be cloned in minutes to mirror legitimate banking or shopping portals.

1. Typosquatting & Subdomain Tricks:
Scammers register lookalike domains like `paypal-security-update.com` where the actual domain owner is `paypal-security-update.com`, NOT `paypal.com`.

2. The HTTPS Fallback Fallacy:
Green padlock (HTTPS) only means the connection is encrypted. Fraudulent phishing sites can easily obtain free SSL certificates.

3. Domain Inspection Rule:
Look at the characters directly before `.com`, `.org`, or `.gov`. In `login.chase.com.fake-login.xyz`, the actual domain is `fake-login.xyz`.
''',
    quizQuestions: [
      QuizQuestion(
        question: 'In the URL http://login.apple.com.security-verify.top, what is the actual domain owner?',
        options: [
          'apple.com',
          'security-verify.top',
          'login.apple.com',
          'Apple Inc.',
        ],
        correctIndex: 1,
        explanation: 'The domain owner is determined by the string immediately preceding the TLD (.top). Here, security-verify.top owns the domain.',
      ),
    ],
  );

  static const _bankModule = LearningModuleData(
    title: 'Banking & Financial Scams',
    subtitle: 'Protecting OTPs, Wire Transfers & QR Codes',
    icon: Icons.account_balance_rounded,
    keyTakeaways: [
      'Banks will NEVER ask for your One-Time Password (OTP) or PIN over the phone.',
      'Fake buyers on marketplaces send QR codes claiming "Scan to RECEIVE payment".',
      'Never send funds via wire or Zelle to "secure your account".',
    ],
    fullLessonText: '''
Financial scams trick victims into transferring money or surrendering bank credentials.

1. Fake Bank Agent Calls:
Caller ID spoofing makes the call look like it originates from your bank's official number. The caller claims your account is under attack and asks for your 2FA OTP to "block" the transaction.

2. QR Code Payment Traps:
Scanning a QR code in payment apps (Zelle, Venmo, UPI) requests money FROM you. Scanning a QR code NEVER deposits money into your bank account.
''',
    quizQuestions: [
      QuizQuestion(
        question: 'A caller claiming to be from your bank asks for your 6-digit SMS verification code to stop a fraudulent charge. What should you do?',
        options: [
          'Read out the code quickly before it expires',
          'Hang up immediately. Bank staff never ask for 2FA OTP codes',
          'Ask the caller for their employee ID before giving the code',
          'Transfer your money to a new account',
        ],
        correctIndex: 1,
        explanation: 'OTP codes grant full account access. Bank representatives will NEVER ask for your OTP.',
      ),
    ],
  );

  void _answerChallenge(bool choice) {
    final current = _challenges[_challengeIndex];
    final isCorrect = choice == current['isScam'];

    if (isCorrect) {
      setState(() => _score++);
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: isCorrect ? AppColors.safeEmerald : AppColors.danger,
            ),
            const SizedBox(width: 8),
            Text(
              isCorrect ? 'Correct Decision!' : 'Incorrect Analysis',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          current['explanation'],
          style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.4, color: AppColors.textPrimary),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _challengeIndex = (_challengeIndex + 1) % _challenges.length;
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.cobalt),
            child: Text('Next Scenario', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cyber Threat Academy', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: false,
        actions: [
          GestureDetector(
            onTap: () {},
            child: ValueListenableBuilder<String>(
              valueListenable: UserProfileService.avatarNotifier,
              builder: (ctx, avatar, _) => CircleAvatar(
                radius: 14,
                backgroundImage: NetworkImage(avatar),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Reveal(delay: Reveal.step(0), child: _buildVigilanceScore()),
            const SizedBox(height: 28),

            Text('SPOT THE SCAM CHALLENGE', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.mutedText, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Reveal(delay: Reveal.step(1), child: _buildChallengeCard()),
            const SizedBox(height: 28),

            Text('INTERACTIVE SECURITY MODULES', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.mutedText, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Reveal(delay: Reveal.step(2), child: _buildExploreCard(context, _phishingModule)),
            const SizedBox(height: 12),
            Reveal(delay: Reveal.step(3), child: _buildExploreCard(context, _urlModule)),
            const SizedBox(height: 12),
            Reveal(delay: Reveal.step(4), child: _buildExploreCard(context, _bankModule)),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }

  Widget _buildVigilanceScore() {
    final rating = 78 + (_score * 4);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 110,
                height: 110,
                child: CircularProgressIndicator(
                  value: rating / 100.0,
                  strokeWidth: 8,
                  backgroundColor: AppColors.border,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cobalt),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                children: [
                  Text('$rating', style: GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  Text('SCORE', style: GoogleFonts.plusJakartaSans(fontSize: 9, color: AppColors.mutedText, letterSpacing: 1)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Cyber Vigilance Rating', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Complete scenarios to level up your threat awareness rating.', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildChallengeCard() {
    final current = _challenges[_challengeIndex];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(current['source'], style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.mutedText, fontWeight: FontWeight.bold)),
              Text('${_challengeIndex + 1}/${_challenges.length}', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.cobalt, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(current['message'], style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.4, color: AppColors.textPrimary)),
          ),
          const SizedBox(height: 14),
          Text(current['question'], style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PremiumCTA(
                  label: "SCAM",
                  isDanger: true,
                  icon: Icons.gpp_bad_rounded,
                  height: 48,
                  onPressed: () => _answerChallenge(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PremiumCTA(
                  label: "SAFE",
                  icon: Icons.verified_rounded,
                  height: 48,
                  onPressed: () => _answerChallenge(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExploreCard(BuildContext context, LearningModuleData data) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => LearningModuleScreen(module: data)));
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.cobalt.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
              child: Icon(data.icon, color: AppColors.electricBlue, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data.title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(data.subtitle, style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.cobalt, size: 16),
          ],
        ),
      ),
    );
  }
}
