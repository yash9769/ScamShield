// lib/data/education/scam_encyclopedia.dart

import 'models/scam_article.dart';

/// Static catalogue of educational articles for the Scam Encyclopedia.
class ScamEncyclopedia {
  static const List<ScamArticle> articles = [
    ScamArticle(
      id: 'phishing_101',
      title: 'Phishing 101',
      shortDescription: 'Learn how email scammers impersonate trusted brands.',
      category: 'phishing',
      difficulty: Difficulty.beginner,
      badgeId: 'badge_phishing',
      iconEmoji: '🎣',
      content: '''
**What is Phishing?**
Phishing is a type of social engineering attack where a scammer sends a fraudulent email that appears to come from a reputable source — such as a bank, government agency, or popular service like Netflix.

**Common Red Flags**
- Mismatched or suspicious sender email domain (e.g. support@netfl1x-help.com)
- Generic greetings ("Dear Customer") instead of your name
- Urgent language: "Your account will be closed in 24 hours!"
- Links that hover to a different URL than displayed
- Attachments you were not expecting

**Real-World Example**
You receive an email from "PayPaI-Security@paypa1.com" asking you to verify your account. The link leads to a look-alike login page designed to steal your credentials.

**How to Stay Safe**
1. Always check the sender's full email address.
2. Hover over links before clicking to see the real destination.
3. Go directly to the website by typing the URL into your browser.
4. Enable two-factor authentication on all accounts.
5. Use ScamShield to scan suspicious links before opening them.
''',
    ),

    ScamArticle(
      id: 'smishing_guide',
      title: 'Smishing: SMS Scams',
      shortDescription: 'Why your text messages are a prime attack vector.',
      category: 'smishing',
      difficulty: Difficulty.beginner,
      badgeId: 'badge_smishing',
      iconEmoji: '📱',
      content: '''
**What is Smishing?**
Smishing (SMS + phishing) is the use of text messages to trick you into revealing personal information or clicking malicious links. Scammers spoof legitimate business numbers to make the message appear authentic.

**Typical Smishing Scenarios**
- "Your parcel is delayed. Track it here: bit.ly/track-pkg" (fake delivery notification)
- "Your bank account has been locked. Call 1-800-FAKE-BANK immediately."
- "Congratulations! You've won a ₹10,000 Flipkart voucher. Claim now."

**Why SMS is Dangerous**
Unlike email, SMS clients don't show full sender details. People tend to trust texts more and act impulsively, especially when the message looks official.

**Defence Checklist**
- Never click links in unexpected SMS messages.
- Call the company directly using a number from their official website.
- Use ScamShield — paste the SMS text to scan for scam patterns instantly.
- Register your number on the Do Not Disturb (DND) registry.
''',
    ),

    ScamArticle(
      id: 'vishing_calls',
      title: 'Vishing: Voice Call Scams',
      shortDescription: 'How scammers use phone calls to steal your money.',
      category: 'vishing',
      difficulty: Difficulty.intermediate,
      badgeId: 'badge_vishing',
      iconEmoji: '📞',
      content: '''
**What is Vishing?**
Vishing (voice phishing) involves scammers calling victims and impersonating banks, government agencies (like the IRS or IT department), tech companies, or relatives in distress.

**Caller ID Spoofing**
Modern tools allow scammers to display any phone number they choose. A call appearing to come from your bank's official number could still be fake.

**Classic Vishing Scripts**
- "This is the CBI. We've detected suspicious activity linked to your Aadhaar. Press 1 to speak to an officer."
- "Your computer is sending error signals to Microsoft. Allow us remote access to fix it."
- "Your grandson is in jail. We need ₹50,000 bail money wired immediately."

**Never Do This On A Call**
- Share your OTP, PIN, or CVV.
- Allow remote access to your device.
- Transfer money under pressure.
- Stay on the line if you feel coerced.

**What to Do Instead**
Hang up and call back the organisation using the official number from their website.
''',
    ),

    ScamArticle(
      id: 'lottery_scam',
      title: 'Lottery & Prize Scams',
      shortDescription: "You didn't win — but you might lose money believing you did.",
      category: 'lottery',
      difficulty: Difficulty.beginner,
      badgeId: 'badge_lottery',
      iconEmoji: '🎰',
      content: '''
**How Lottery Scams Work**
You receive a message claiming you've won a lottery, prize, or sweepstake you never entered. To "claim" your prize, you must first pay a processing fee, tax, or insurance deposit.

**The Advance Fee Trap**
Once you pay the initial fee, the scammer invents additional fees. The prize never materialises but victims keep paying in hope of recovering their money.

**Warning Signs**
- You won a lottery you never entered.
- The prize organisation has a generic Gmail/Yahoo email.
- You're asked to keep the win secret.
- Payment is required upfront via wire transfer, gift cards, or cryptocurrency.
- The "prize" message was unsolicited.

**Rule of Thumb**
Legitimate lotteries never ask winners to pay money to receive their prize. If you didn't enter, you didn't win.
''',
    ),

    ScamArticle(
      id: 'job_scam',
      title: 'Fake Job Offers',
      shortDescription: 'Protect yourself from employment fraud and work-from-home traps.',
      category: 'job',
      difficulty: Difficulty.intermediate,
      badgeId: 'badge_job',
      iconEmoji: '💼',
      content: '''
**The Job Scam Landscape**
Fake job offers exploit job seekers by promising high pay for minimal work. Common variants include:
- Data entry / form-filling from home
- Product testing / mystery shopping
- Social media influencer assistants
- Cryptocurrency trading assistants

**Red Flags**
- The job pays unusually high for minimal skill requirements.
- You're hired without an interview.
- You're asked to pay for training materials, background checks, or equipment.
- The "employer" contacts you first, unsolicited.
- Payment is via gift cards, wire transfer, or crypto.

**The "Reshipping Mule" Trick**
Some scams ask victims to receive and reship packages — these are stolen goods and participants can face criminal charges.

**Verify Before You Apply**
- Research the company independently on LinkedIn and their official website.
- Never pay to get a job.
- Never share your bank details before receiving your first legitimate payslip.
''',
    ),

    ScamArticle(
      id: 'romance_scam',
      title: 'Romance Scams',
      shortDescription: 'How scammers exploit emotional connections to steal money.',
      category: 'romance',
      difficulty: Difficulty.advanced,
      badgeId: 'badge_romance',
      iconEmoji: '💔',
      content: '''
**What is a Romance Scam?**
Scammers create fake online personas on dating apps or social media to build a romantic relationship with a target. After gaining trust over weeks or months, they invent a crisis requiring financial help.

**The Long Con**
Romance scams are the most emotionally damaging type of fraud. Victims often refuse to believe they've been deceived even when evidence is presented.

**Common Crisis Scenarios**
- A medical emergency requiring immediate funds.
- An investment gone wrong that the scammer needs "just a bit more" to fix.
- Being "stuck" abroad and needing a plane ticket.
- Military personnel asking for care packages or emergency funds.

**Signs You're Being Scammed**
- The person has only professional-looking photos (often stolen from social media).
- They profess deep love unusually quickly.
- They always have excuses to avoid video calls.
- They ultimately ask for money.

**What to Do**
Perform a reverse image search on profile photos. Tell a trusted friend. Never send money to someone you have not met in person.
''',
    ),

    ScamArticle(
      id: 'tech_support_scam',
      title: 'Tech Support Scams',
      shortDescription: 'Fake virus alerts and remote access traps explained.',
      category: 'tech_support',
      difficulty: Difficulty.beginner,
      badgeId: 'badge_tech',
      iconEmoji: '💻',
      content: '''
**How Tech Support Scams Work**
A pop-up appears on your screen claiming your computer is infected with a virus. It shows a fake "Microsoft" or "Apple" phone number to call. The scammer then:
1. Convinces you to install remote-access software (TeamViewer, AnyDesk).
2. Pretends to find serious threats on your computer.
3. Charges hundreds of rupees/dollars for "repairs."
4. May steal banking credentials while they have access.

**Browser Lock Screens**
Some scams display a full-screen browser pop-up that appears to lock your computer. Close the browser using Task Manager (Ctrl+Alt+Del) or force-quit on Mac.

**Key Facts**
- Microsoft, Apple, Google, and Amazon will NEVER proactively call you about your computer.
- Real virus scanners don't need you to call a phone number.
- Legitimate support companies don't ask for gift card payments.

**If You Gave Access**
Change all your passwords immediately. Run a legitimate antivirus scan. Contact your bank if you shared financial details.
''',
    ),

    ScamArticle(
      id: 'investment_fraud',
      title: 'Investment & Crypto Fraud',
      shortDescription: 'Spot Ponzi schemes and fake trading platforms before you lose savings.',
      category: 'investment',
      difficulty: Difficulty.advanced,
      badgeId: 'badge_invest',
      iconEmoji: '📈',
      content: '''
**Types of Investment Scams**
- **Ponzi Schemes**: Returns paid from new investors' money, not real profits. Eventually collapses.
- **Pump and Dump**: Scammers hype a cheap cryptocurrency/stock, sell at the peak, and it crashes.
- **Pig Butchering (Sha Zhu Pan)**: Long-term romance + crypto investment scam. Victim is fattened (encouraged to invest more) before being slaughtered (platform disappears).
- **Fake Trading Platforms**: Websites show fake profits to encourage deposits. Withdrawal is always blocked.

**Warning Signs**
- Guaranteed high returns (15–30% monthly) with "no risk."
- Pressure to recruit friends/family.
- Withdrawal difficulties or extra "tax" fees before withdrawal.
- The platform only exists as an app not on official app stores.
- Investment tips from someone you met online.

**Regulatory Check**
Always verify investment platforms with SEBI (India), SEC (USA), or FCA (UK) before investing any money.
''',
    ),

    ScamArticle(
      id: 'url_deep_dive',
      title: 'URL & Link Analysis',
      shortDescription: 'How to read URLs and spot hidden phishing domains.',
      category: 'phishing',
      difficulty: Difficulty.intermediate,
      badgeId: 'badge_url',
      iconEmoji: '🔗',
      content: '''
**Anatomy of a URL**
`https://secure-login.bank-of-india-support.com/verify`

- **Protocol**: https:// (look for padlock — but padlock alone doesn't mean safe!)
- **Subdomain**: secure-login
- **Domain**: bank-of-india-support ← This is the real domain, not Bank of India!
- **TLD**: .com
- **Path**: /verify

**Homograph Attacks**
Scammers use characters that look like Latin letters but are from other alphabets:
- paypa**l**.com vs paypa**ӏ**.com (Cyrillic l)
- g**o**ogle.com vs g**0**ogle.com (zero instead of O)

**Shortened URLs**
URLs like bit.ly/xyz hide the real destination. Always expand them using a URL expander tool before clicking. ScamShield detects shortened URLs automatically.

**Checklist Before Clicking**
1. Does the domain match the company exactly?
2. Is there an unnecessary subdomain?
3. Is the URL shortened or obfuscated?
4. Did you expect this link?
5. If in doubt, navigate to the site directly via your browser.
''',
    ),

    ScamArticle(
      id: 'bank_fraud',
      title: 'Banking & UPI Fraud',
      shortDescription: 'Protect your UPI, net banking, and debit/credit cards.',
      category: 'phishing',
      difficulty: Difficulty.intermediate,
      badgeId: 'badge_bank',
      iconEmoji: '🏦',
      content: '''
**Common Banking Scams in India**
- **UPI Payment Requests**: Scammer sends a "collect" request disguised as a refund. You approve it and lose money.
- **KYC Fraud**: Fake bank representatives ask you to share OTP to "complete KYC."
- **Card Skimming**: Physical devices attached to ATMs capture card data.
- **Sim Swap**: Scammer convinces telecom to transfer your number to their SIM, intercepting OTPs.

**The "Collect Request" Trap**
In UPI, accepting a collect request SENDS money — it does not receive it. Scammers phrase these as "verification deposits" or "refund confirmations."

**How Your Bank Will Never Communicate**
- Ask for your full card number over the phone.
- Ask for your OTP.
- Ask for your ATM PIN.
- Ask you to transfer money to a "safe account."

**Immediate Steps if Compromised**
1. Call your bank's 24/7 helpline immediately.
2. Block your cards and freeze UPI.
3. File a cybercrime complaint at cybercrime.gov.in.
4. Report to the National Cyber Crime Reporting Portal (1930 helpline).
''',
    ),
  ];

  /// Returns articles filtered by [category].
  static List<ScamArticle> byCategory(String category) =>
      articles.where((a) => a.category == category).toList();

  /// Returns articles at [difficulty] level.
  static List<ScamArticle> byDifficulty(Difficulty difficulty) =>
      articles.where((a) => a.difficulty == difficulty).toList();

  /// Finds an article by [id], returns null if not found.
  static ScamArticle? findById(String id) {
    try {
      return articles.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }
}
