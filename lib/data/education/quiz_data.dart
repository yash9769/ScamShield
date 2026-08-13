// lib/data/education/quiz_data.dart

import 'models/quiz_question.dart';

/// Static bank of 15 quiz questions for the Education Module.
class QuizData {
  static const List<QuizQuestion> questions = [
    QuizQuestion(
      id: 'q1',
      category: 'phishing',
      question: 'You receive an email from "support@paypa1.com" asking you to verify your PayPal account. What should you do?',
      options: [
        QuizOption(text: 'Click the link and verify your details', isCorrect: false),
        QuizOption(text: 'Ignore it — the domain "paypa1.com" is not PayPal', isCorrect: true),
        QuizOption(text: 'Forward it to your contacts as a warning', isCorrect: false),
        QuizOption(text: 'Reply and ask if it is legitimate', isCorrect: false),
      ],
      explanation: 'Scammers use typo domains (paypa1 instead of paypal) to trick you. Always check the full sender email address carefully before clicking anything.',
    ),

    QuizQuestion(
      id: 'q2',
      category: 'smishing',
      question: 'An SMS says: "Your HDFC parcel is undeliverable. Reschedule here: bit.ly/hdfctrack". What is the safest action?',
      options: [
        QuizOption(text: 'Click the link to reschedule delivery', isCorrect: false),
        QuizOption(text: 'Call the number in the SMS', isCorrect: false),
        QuizOption(text: "Do not click — go to HDFC's official website directly", isCorrect: true),
        QuizOption(text: 'Reply STOP to unsubscribe', isCorrect: false),
      ],
      explanation: 'Shortened URLs (bit.ly) hide the real destination. Delivery companies send notifications from their official domains, not random short links. Always navigate directly.',
    ),

    QuizQuestion(
      id: 'q3',
      category: 'general',
      question: 'In UPI, if someone sends you a "collect request" claiming it is a refund, what happens when you approve it?',
      options: [
        QuizOption(text: 'You receive the refund amount', isCorrect: false),
        QuizOption(text: 'Nothing — it is just a verification', isCorrect: false),
        QuizOption(text: 'Money is SENT from your account to theirs', isCorrect: true),
        QuizOption(text: 'Your UPI is temporarily blocked for security', isCorrect: false),
      ],
      explanation: 'A UPI collect request asks YOU to authorise a DEBIT from your account. Approving it means you send money — not receive it. Scammers exploit this by calling it a "refund."',
    ),

    QuizQuestion(
      id: 'q4',
      category: 'vishing',
      question: 'A caller says "I\'m from Microsoft. Your computer is sending virus alerts to us. Allow remote access immediately." What do you do?',
      options: [
        QuizOption(text: 'Allow remote access to fix the issue', isCorrect: false),
        QuizOption(text: 'Give them your Microsoft account password', isCorrect: false),
        QuizOption(text: 'Hang up — Microsoft never calls you proactively', isCorrect: true),
        QuizOption(text: 'Ask them to send an email confirmation first', isCorrect: false),
      ],
      explanation: 'Microsoft, Apple, Google, and Amazon will NEVER proactively call you about computer problems. This is a classic tech support scam designed to install malware or steal money.',
    ),

    QuizQuestion(
      id: 'q5',
      category: 'url',
      question: 'Which of the following URLs is most likely a phishing site pretending to be State Bank of India?',
      options: [
        QuizOption(text: 'https://onlinesbi.sbi', isCorrect: false),
        QuizOption(text: 'https://sbi.co.in/login', isCorrect: false),
        QuizOption(text: 'https://secure-login.sbi-netbanking-support.com', isCorrect: true),
        QuizOption(text: 'https://retail.onlinesbi.sbi', isCorrect: false),
      ],
      explanation: 'The real domain in option C is "sbi-netbanking-support.com" — not sbi.co.in or sbi. The words "secure-login" and "support" are used to seem legitimate, but they\'re just subdomains of the scammer\'s domain.',
    ),

    QuizQuestion(
      id: 'q6',
      category: 'lottery',
      question: 'You receive a message: "Congratulations! You\'ve won ₹25 Lakh in the KBC Lottery. Pay ₹5,000 processing fee to claim." This is:',
      options: [
        QuizOption(text: 'Legitimate — KBC does run lotteries', isCorrect: false),
        QuizOption(text: 'An advance fee scam — legitimate lotteries never charge to claim prizes', isCorrect: true),
        QuizOption(text: 'Suspicious but possibly real — pay ₹500 to check', isCorrect: false),
        QuizOption(text: 'A government scheme — follow the instructions', isCorrect: false),
      ],
      explanation: 'Legitimate prize schemes never ask you to pay money upfront to receive winnings. "Processing fees," "taxes," and "insurance deposits" are all classic advance fee scam tactics.',
    ),

    QuizQuestion(
      id: 'q7',
      category: 'otp',
      question: 'A bank employee calls and says they need your OTP to "process a refund." You should:',
      options: [
        QuizOption(text: 'Share it — they work for the bank', isCorrect: false),
        QuizOption(text: 'Share only the last 4 digits', isCorrect: false),
        QuizOption(text: 'Refuse — banks will NEVER ask for your OTP', isCorrect: true),
        QuizOption(text: 'Ask them to hold and call the bank to verify them', isCorrect: false),
      ],
      explanation: 'No legitimate bank, service, or government agency will ever ask for your OTP. OTPs are a one-time authentication token meant only for you. Sharing it allows attackers to authorise transactions.',
    ),

    QuizQuestion(
      id: 'q8',
      category: 'job',
      question: 'A job offer promises ₹50,000/month to "like YouTube videos from home, no experience needed." You are asked to pay ₹2,000 for a starter kit. This is:',
      options: [
        QuizOption(text: 'Legitimate — social media jobs pay well', isCorrect: false),
        QuizOption(text: 'A job scam — no legitimate employer charges you to start', isCorrect: true),
        QuizOption(text: 'Worth trying if you need money', isCorrect: false),
        QuizOption(text: 'A government digital initiative', isCorrect: false),
      ],
      explanation: 'Paying to get a job is always a scam. Legitimate employers pay you — not the other way around. These scams often continue to demand more money for "training," "tools," or "ID verification."',
    ),

    QuizQuestion(
      id: 'q9',
      category: 'general',
      question: 'Which of these is NOT a warning sign of a scam message?',
      options: [
        QuizOption(text: 'Urgency language like "Act Now" or "24 Hours"', isCorrect: false),
        QuizOption(text: 'Requests to click a shortened URL', isCorrect: false),
        QuizOption(text: 'A message from a contact you know, with no suspicious links', isCorrect: true),
        QuizOption(text: 'Unsolicited prize notification', isCorrect: false),
      ],
      explanation: 'A message from a known contact with no links or suspicious requests is generally safe. However, even known contacts can be impersonated — always verify unusual requests through a different channel.',
    ),

    QuizQuestion(
      id: 'q10',
      category: 'romance',
      question: 'Someone you met online professes love after two weeks and now needs ₹80,000 for a medical emergency. They cannot video call due to "camera issues." What do you do?',
      options: [
        QuizOption(text: 'Send the money — they are in danger', isCorrect: false),
        QuizOption(text: 'Send half — be cautious', isCorrect: false),
        QuizOption(text: 'Do a reverse image search and refuse until you video call', isCorrect: true),
        QuizOption(text: 'Report them to police before deciding', isCorrect: false),
      ],
      explanation: 'Classic romance scam pattern: fast emotional attachment, avoiding video, then a financial crisis. Do a reverse image search on their photos. Genuine people can always find a way to video call.',
    ),

    QuizQuestion(
      id: 'q11',
      category: 'technical',
      question: 'What does a green padlock (🔒) in your browser\'s address bar guarantee?',
      options: [
        QuizOption(text: 'The website is safe and legitimate', isCorrect: false),
        QuizOption(text: 'The website is encrypted — but it could still be a phishing site', isCorrect: true),
        QuizOption(text: 'The website is government-verified', isCorrect: false),
        QuizOption(text: 'Your payment details are 100% secure', isCorrect: false),
      ],
      explanation: 'HTTPS/SSL (the padlock) only means your connection to the site is encrypted. It does NOT mean the site owner is trustworthy. Phishing sites routinely use HTTPS.',
    ),

    QuizQuestion(
      id: 'q12',
      category: 'general',
      question: 'You want to report a cybercrime in India. Which helpline should you call?',
      options: [
        QuizOption(text: '100 (Police)', isCorrect: false),
        QuizOption(text: '1930 (National Cybercrime Helpline)', isCorrect: true),
        QuizOption(text: '112 (Emergency Services)', isCorrect: false),
        QuizOption(text: '1800-11-0011', isCorrect: false),
      ],
      explanation: '1930 is India\'s National Cyber Crime Helpline. You can also file a complaint at cybercrime.gov.in. Report immediately after a cybercrime for the best chance of recovery.',
    ),

    QuizQuestion(
      id: 'q13',
      category: 'investment',
      question: 'A platform promises 20% monthly returns on cryptocurrency with "zero risk." How should you evaluate this?',
      options: [
        QuizOption(text: 'It is a great opportunity — invest immediately', isCorrect: false),
        QuizOption(text: 'Ask for more details before investing', isCorrect: false),
        QuizOption(text: 'It is almost certainly a scam — guaranteed high returns don\'t exist', isCorrect: true),
        QuizOption(text: 'Invest a small amount to test', isCorrect: false),
      ],
      explanation: 'No legitimate investment offers guaranteed high returns. 20% monthly = 240% annually — this is economically impossible through legal means. This is a classic Ponzi or pig-butchering scam pattern.',
    ),

    QuizQuestion(
      id: 'q14',
      category: 'technical',
      question: 'What is caller ID spoofing?',
      options: [
        QuizOption(text: 'When a scammer uses a hidden number', isCorrect: false),
        QuizOption(text: 'When a caller fakes their displayed phone number to appear as a trusted entity', isCorrect: true),
        QuizOption(text: 'When your call is recorded without consent', isCorrect: false),
        QuizOption(text: 'When your SIM card is cloned', isCorrect: false),
      ],
      explanation: 'Spoofing technology allows scammers to display any number — including your bank\'s official hotline — on your caller ID. A call appearing from a legitimate number does not guarantee it is legitimate.',
    ),

    QuizQuestion(
      id: 'q15',
      category: 'general',
      question: 'Which action is the MOST effective way to protect yourself from all types of scams?',
      options: [
        QuizOption(text: 'Never use the internet or phone', isCorrect: false),
        QuizOption(text: 'Use a premium antivirus only', isCorrect: false),
        QuizOption(text: 'Verify independently before acting, and never share OTPs/PINs/passwords', isCorrect: true),
        QuizOption(text: 'Only communicate with people you know personally', isCorrect: false),
      ],
      explanation: 'The golden rules: independently verify any unusual request (call back using an official number), and NEVER share authentication credentials. These two rules stop the vast majority of scam attempts.',
    ),
  ];
}
