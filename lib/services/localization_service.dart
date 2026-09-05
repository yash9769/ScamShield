// lib/services/localization_service.dart
//
// App language selection.
//
// ── What this replaced ─────────────────────────────────────────────────────
// The previous version of this file was a stub: seven strings, a plain static
// `currentLanguage` field, no persistence, no way for the UI to notice a
// change, and — decisively — not a single call site anywhere in lib/. Changing
// the language did nothing, because nothing read it. This is a working
// version: the choice is persisted, the app rebuilds when it changes, and the
// strings below are actually used by the screens listed under "Coverage".
//
// ── Which languages ────────────────────────────────────────────────────────
// The stub offered English, Hindi, Spanish and French. Spanish and French are
// decoration for this app: everything it is built around — UPI payee
// verification, +91 number normalisation, the cybercrime.gov.in complaint
// export, the specific scam patterns in the detector — is aimed at users in
// India. So the set is English plus the Indian languages with the largest
// speaker counts among that audience. A person being talked into a UPI
// transfer by someone on the phone is exactly the person who should not also
// be translating a warning in their second language.
//
// > The non-English strings here were written for meaning rather than by a
// > native speaker, and deserve a native review pass before release. They are
// > checked in as a working default rather than a finished translation.
//
// ── Coverage, stated honestly ──────────────────────────────────────────────
// This covers the app's navigation, the scan flow, and every verdict and
// risk-level label — the text a user must understand to act correctly. It does
// not cover the Learn articles (long-form content, a translation project of
// its own) or the AI-generated summary of a scan, which arrives from the
// analysis service in English. `isFullyLocalized` reflects that, and the
// language picker says so rather than implying a complete translation.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLanguage {
  final String code;

  /// The language's name in that language — someone looking for their own
  /// language should not have to read English to find it.
  final String nativeName;

  final String englishName;

  const AppLanguage(this.code, this.nativeName, this.englishName);
}

class LocalizationService {
  LocalizationService._();

  static const String _prefsKey = 'scamshield_language';

  static const List<AppLanguage> supported = [
    AppLanguage('en', 'English', 'English'),
    AppLanguage('hi', 'हिन्दी', 'Hindi'),
    AppLanguage('mr', 'मराठी', 'Marathi'),
    AppLanguage('bn', 'বাংলা', 'Bengali'),
    AppLanguage('ta', 'தமிழ்', 'Tamil'),
    AppLanguage('te', 'తెలుగు', 'Telugu'),
  ];

  /// Drives a rebuild of the whole app. `MaterialApp` is wrapped in a
  /// `ValueListenableBuilder` on this, so a language change takes effect
  /// immediately instead of on next launch.
  static final ValueNotifier<String> language = ValueNotifier<String>('en');

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      if (stored != null && _strings.containsKey(stored)) {
        language.value = stored;
      }
      _initialized = true;
    } catch (e) {
      debugPrint('LocalizationService.init failed, using English: $e');
    }
  }

  static Future<void> setLanguage(String code) async {
    if (!_strings.containsKey(code)) return;
    language.value = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, code);
    } catch (e) {
      debugPrint('LocalizationService failed to persist language: $e');
    }
  }

  static AppLanguage get current =>
      supported.firstWhere((l) => l.code == language.value,
          orElse: () => supported.first);

  /// True only for the language every string here was written in. The picker
  /// uses this to tell the truth about partial coverage rather than presenting
  /// a half-translated app as a finished one.
  static bool get isFullyLocalized => language.value == 'en';

  /// Looks up a string, falling back to English and then to the key itself.
  ///
  /// Falling through to English rather than showing a raw key matters here:
  /// a missing translation on a scam warning should degrade to a warning the
  /// user can still read, not to `scan_result_scam`.
  static String tr(String key) {
    return _strings[language.value]?[key] ?? _strings['en']?[key] ?? key;
  }

  // ── Strings ───────────────────────────────────────────────────────────────
  //
  // Keys are grouped by where they appear. When adding one, add it to `en`
  // first — that map is the reference, and tr() falls back to it.

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      // Navigation
      'nav_home': 'HOME',
      'nav_scan': 'SCAN',
      'nav_breach': 'BREACH',
      'nav_history': 'HISTORY',
      'nav_learn': 'LEARN',
      'nav_profile': 'PROFILE',

      // Verdicts — the safety-critical strings
      'verdict_safe': 'SAFE',
      'verdict_suspicious': 'SUSPICIOUS',
      'verdict_scam': 'SCAM',
      'verdict_safe_detail': 'No known threats found',
      'verdict_suspicious_detail': 'Treat this with caution',
      'verdict_scam_detail': 'Do not reply, click, or pay',

      // Scan screen
      'scan_title': 'Threat Scanner',
      'scan_tab_message': 'Message',
      'scan_tab_link': 'Link',
      'scan_hint': 'Paste a suspicious message or link here',
      'scan_button': 'ANALYZE',
      'scan_analyzing': 'Analyzing…',
      'scan_clear': 'CLEAR',
      'scan_empty_input': 'Please enter some text or link to analyze.',
      'scan_risk_score': 'Risk Score',
      'scan_summary': 'SECURITY SUMMARY',
      'scan_factors': 'DETECTED RISK FACTORS',

      // Feedback
      'feedback_prompt': 'WAS THIS RIGHT?',
      'feedback_privacy': 'Only the verdict and a fingerprint of the text are '
          'sent — never the message itself.',
      'feedback_correct': 'Correct',
      'feedback_legit': "It's legitimate",
      'feedback_was_scam': 'It was a scam',
      'feedback_thanks': 'Thanks — that helps improve the detection.',

      // Common
      'common_cancel': 'Cancel',
      'common_not_now': 'Not now',
      'common_continue': 'Continue',
      'common_retry': 'Try again',
      'common_offline': 'Could not reach the ScamShield service.',

      // Language picker
      'language_title': 'Language',
      'language_subtitle': 'Choose the language for warnings and app screens',
      'language_partial': 'Warnings, verdicts and navigation are translated. '
          'Learn articles and AI-written scan summaries are still in English.',
    },
    'hi': {
      'nav_home': 'होम',
      'nav_scan': 'स्कैन',
      'nav_breach': 'लीक',
      'nav_history': 'इतिहास',
      'nav_learn': 'सीखें',
      'nav_profile': 'प्रोफ़ाइल',

      'verdict_safe': 'सुरक्षित',
      'verdict_suspicious': 'संदिग्ध',
      'verdict_scam': 'धोखाधड़ी',
      'verdict_safe_detail': 'कोई ज्ञात खतरा नहीं मिला',
      'verdict_suspicious_detail': 'सावधानी से आगे बढ़ें',
      'verdict_scam_detail': 'जवाब न दें, लिंक न खोलें, पैसे न भेजें',

      'scan_title': 'खतरा स्कैनर',
      'scan_tab_message': 'संदेश',
      'scan_tab_link': 'लिंक',
      'scan_hint': 'संदिग्ध संदेश या लिंक यहाँ पेस्ट करें',
      'scan_button': 'जाँच करें',
      'scan_analyzing': 'जाँच हो रही है…',
      'scan_clear': 'साफ़ करें',
      'scan_empty_input': 'कृपया जाँच के लिए कोई संदेश या लिंक डालें।',
      'scan_risk_score': 'जोखिम स्कोर',
      'scan_summary': 'सुरक्षा सारांश',
      'scan_factors': 'पाए गए जोखिम',

      'feedback_prompt': 'क्या यह नतीजा सही था?',
      'feedback_privacy': 'केवल नतीजा और टेक्स्ट की पहचान भेजी जाती है — '
          'संदेश कभी नहीं।',
      'feedback_correct': 'सही था',
      'feedback_legit': 'यह असली है',
      'feedback_was_scam': 'यह धोखाधड़ी थी',
      'feedback_thanks': 'धन्यवाद — इससे पहचान बेहतर होती है।',

      'common_cancel': 'रद्द करें',
      'common_not_now': 'अभी नहीं',
      'common_continue': 'आगे बढ़ें',
      'common_retry': 'फिर कोशिश करें',
      'common_offline': 'ScamShield सेवा से संपर्क नहीं हो सका।',

      'language_title': 'भाषा',
      'language_subtitle': 'चेतावनियों और ऐप के लिए भाषा चुनें',
      'language_partial': 'चेतावनियाँ, नतीजे और नेविगेशन अनुवादित हैं। '
          'सीखने के लेख और AI द्वारा लिखा सारांश अभी अंग्रेज़ी में है।',
    },
    'mr': {
      'nav_home': 'होम',
      'nav_scan': 'स्कॅन',
      'nav_breach': 'लीक',
      'nav_history': 'इतिहास',
      'nav_learn': 'शिका',
      'nav_profile': 'प्रोफाइल',

      'verdict_safe': 'सुरक्षित',
      'verdict_suspicious': 'संशयास्पद',
      'verdict_scam': 'फसवणूक',
      'verdict_safe_detail': 'कोणताही ज्ञात धोका आढळला नाही',
      'verdict_suspicious_detail': 'सावधगिरीने पुढे जा',
      'verdict_scam_detail': 'उत्तर देऊ नका, लिंक उघडू नका, पैसे पाठवू नका',

      'scan_title': 'धोका स्कॅनर',
      'scan_tab_message': 'संदेश',
      'scan_tab_link': 'लिंक',
      'scan_hint': 'संशयास्पद संदेश किंवा लिंक इथे पेस्ट करा',
      'scan_button': 'तपासा',
      'scan_analyzing': 'तपासत आहे…',
      'scan_clear': 'साफ करा',
      'scan_empty_input': 'कृपया तपासण्यासाठी संदेश किंवा लिंक टाका.',
      'scan_risk_score': 'धोका गुण',
      'scan_summary': 'सुरक्षा सारांश',
      'scan_factors': 'आढळलेले धोके',

      'feedback_prompt': 'हा निकाल बरोबर होता का?',
      'feedback_privacy': 'फक्त निकाल आणि मजकुराची ओळख पाठवली जाते — '
          'संदेश कधीच नाही.',
      'feedback_correct': 'बरोबर होता',
      'feedback_legit': 'हे खरे आहे',
      'feedback_was_scam': 'ही फसवणूक होती',
      'feedback_thanks': 'धन्यवाद — यामुळे ओळख सुधारते.',

      'common_cancel': 'रद्द करा',
      'common_not_now': 'आत्ता नको',
      'common_continue': 'पुढे चला',
      'common_retry': 'पुन्हा प्रयत्न करा',
      'common_offline': 'ScamShield सेवेशी संपर्क होऊ शकला नाही.',

      'language_title': 'भाषा',
      'language_subtitle': 'इशारे आणि अ‍ॅपसाठी भाषा निवडा',
      'language_partial': 'इशारे, निकाल आणि नेव्हिगेशन भाषांतरित आहेत. '
          'शिकण्याचे लेख आणि AI सारांश अजून इंग्रजीत आहेत.',
    },
    'bn': {
      'nav_home': 'হোম',
      'nav_scan': 'স্ক্যান',
      'nav_breach': 'ফাঁস',
      'nav_history': 'ইতিহাস',
      'nav_learn': 'শিখুন',
      'nav_profile': 'প্রোফাইল',

      'verdict_safe': 'নিরাপদ',
      'verdict_suspicious': 'সন্দেহজনক',
      'verdict_scam': 'প্রতারণা',
      'verdict_safe_detail': 'কোনো পরিচিত ঝুঁকি পাওয়া যায়নি',
      'verdict_suspicious_detail': 'সাবধানে এগোন',
      'verdict_scam_detail': 'উত্তর দেবেন না, লিঙ্কে ক্লিক করবেন না, টাকা পাঠাবেন না',

      'scan_title': 'ঝুঁকি স্ক্যানার',
      'scan_tab_message': 'বার্তা',
      'scan_tab_link': 'লিঙ্ক',
      'scan_hint': 'সন্দেহজনক বার্তা বা লিঙ্ক এখানে পেস্ট করুন',
      'scan_button': 'পরীক্ষা করুন',
      'scan_analyzing': 'পরীক্ষা চলছে…',
      'scan_clear': 'মুছুন',
      'scan_empty_input': 'অনুগ্রহ করে পরীক্ষার জন্য বার্তা বা লিঙ্ক দিন।',
      'scan_risk_score': 'ঝুঁকি স্কোর',
      'scan_summary': 'নিরাপত্তা সারাংশ',
      'scan_factors': 'শনাক্ত হওয়া ঝুঁকি',

      'feedback_prompt': 'এই রায় কি সঠিক ছিল?',
      'feedback_privacy': 'শুধু রায় ও লেখার শনাক্তচিহ্ন পাঠানো হয় — '
          'বার্তাটি কখনও নয়।',
      'feedback_correct': 'সঠিক ছিল',
      'feedback_legit': 'এটি আসল',
      'feedback_was_scam': 'এটি প্রতারণা ছিল',
      'feedback_thanks': 'ধন্যবাদ — এতে শনাক্তকরণ ভালো হয়।',

      'common_cancel': 'বাতিল',
      'common_not_now': 'এখন নয়',
      'common_continue': 'এগিয়ে যান',
      'common_retry': 'আবার চেষ্টা করুন',
      'common_offline': 'ScamShield সেবার সঙ্গে যোগাযোগ করা যায়নি।',

      'language_title': 'ভাষা',
      'language_subtitle': 'সতর্কতা ও অ্যাপের ভাষা বেছে নিন',
      'language_partial': 'সতর্কতা, রায় ও নেভিগেশন অনূদিত। '
          'শেখার নিবন্ধ ও AI সারাংশ এখনও ইংরেজিতে।',
    },
    'ta': {
      'nav_home': 'முகப்பு',
      'nav_scan': 'ஸ்கேன்',
      'nav_breach': 'கசிவு',
      'nav_history': 'வரலாறு',
      'nav_learn': 'கற்க',
      'nav_profile': 'சுயவிவரம்',

      'verdict_safe': 'பாதுகாப்பானது',
      'verdict_suspicious': 'சந்தேகத்திற்குரியது',
      'verdict_scam': 'மோசடி',
      'verdict_safe_detail': 'அறியப்பட்ட அபாயம் எதுவும் இல்லை',
      'verdict_suspicious_detail': 'கவனமாக இருங்கள்',
      'verdict_scam_detail': 'பதிலளிக்காதீர்கள், இணைப்பைத் திறக்காதீர்கள், பணம் அனுப்பாதீர்கள்',

      'scan_title': 'அபாய ஸ்கேனர்',
      'scan_tab_message': 'செய்தி',
      'scan_tab_link': 'இணைப்பு',
      'scan_hint': 'சந்தேகமான செய்தியை அல்லது இணைப்பை இங்கே ஒட்டவும்',
      'scan_button': 'சரிபார்',
      'scan_analyzing': 'சரிபார்க்கிறது…',
      'scan_clear': 'அழி',
      'scan_empty_input': 'சரிபார்க்க ஒரு செய்தியை அல்லது இணைப்பை உள்ளிடவும்.',
      'scan_risk_score': 'அபாய மதிப்பெண்',
      'scan_summary': 'பாதுகாப்பு சுருக்கம்',
      'scan_factors': 'கண்டறியப்பட்ட அபாயங்கள்',

      'feedback_prompt': 'இந்த முடிவு சரியா?',
      'feedback_privacy': 'முடிவும் உரையின் அடையாளமும் மட்டுமே அனுப்பப்படும் — '
          'செய்தி ஒருபோதும் இல்லை.',
      'feedback_correct': 'சரி',
      'feedback_legit': 'இது உண்மையானது',
      'feedback_was_scam': 'இது மோசடி',
      'feedback_thanks': 'நன்றி — இது கண்டறிதலை மேம்படுத்துகிறது.',

      'common_cancel': 'ரத்து',
      'common_not_now': 'இப்போது வேண்டாம்',
      'common_continue': 'தொடர',
      'common_retry': 'மீண்டும் முயற்சி',
      'common_offline': 'ScamShield சேவையை அணுக முடியவில்லை.',

      'language_title': 'மொழி',
      'language_subtitle': 'எச்சரிக்கைகளுக்கும் செயலிக்கும் மொழியைத் தேர்வுசெய்க',
      'language_partial': 'எச்சரிக்கைகள், முடிவுகள், வழிசெலுத்தல் மொழிபெயர்க்கப்பட்டுள்ளன. '
          'கற்றல் கட்டுரைகளும் AI சுருக்கமும் இன்னும் ஆங்கிலத்தில்.',
    },
    'te': {
      'nav_home': 'హోమ్',
      'nav_scan': 'స్కాన్',
      'nav_breach': 'లీక్',
      'nav_history': 'చరిత్ర',
      'nav_learn': 'నేర్చుకోండి',
      'nav_profile': 'ప్రొఫైల్',

      'verdict_safe': 'సురక్షితం',
      'verdict_suspicious': 'అనుమానాస్పదం',
      'verdict_scam': 'మోసం',
      'verdict_safe_detail': 'తెలిసిన ప్రమాదం ఏదీ కనిపించలేదు',
      'verdict_suspicious_detail': 'జాగ్రత్తగా ముందుకు వెళ్లండి',
      'verdict_scam_detail': 'బదులివ్వకండి, లింక్ తెరవకండి, డబ్బు పంపకండి',

      'scan_title': 'ప్రమాద స్కానర్',
      'scan_tab_message': 'సందేశం',
      'scan_tab_link': 'లింక్',
      'scan_hint': 'అనుమానాస్పద సందేశాన్ని లేదా లింక్‌ను ఇక్కడ అతికించండి',
      'scan_button': 'పరిశీలించు',
      'scan_analyzing': 'పరిశీలిస్తోంది…',
      'scan_clear': 'తొలగించు',
      'scan_empty_input': 'దయచేసి పరిశీలించడానికి సందేశం లేదా లింక్ ఇవ్వండి.',
      'scan_risk_score': 'ప్రమాద స్కోరు',
      'scan_summary': 'భద్రతా సారాంశం',
      'scan_factors': 'గుర్తించిన ప్రమాదాలు',

      'feedback_prompt': 'ఈ తీర్పు సరైనదా?',
      'feedback_privacy': 'తీర్పు మరియు వచనపు గుర్తు మాత్రమే పంపబడతాయి — '
          'సందేశం ఎప్పుడూ కాదు.',
      'feedback_correct': 'సరైనది',
      'feedback_legit': 'ఇది నిజమైనది',
      'feedback_was_scam': 'ఇది మోసం',
      'feedback_thanks': 'ధన్యవాదాలు — ఇది గుర్తింపును మెరుగుపరుస్తుంది.',

      'common_cancel': 'రద్దు',
      'common_not_now': 'ఇప్పుడు వద్దు',
      'common_continue': 'కొనసాగండి',
      'common_retry': 'మళ్లీ ప్రయత్నించండి',
      'common_offline': 'ScamShield సేవను చేరుకోలేకపోయాం.',

      'language_title': 'భాష',
      'language_subtitle': 'హెచ్చరికలకు మరియు యాప్‌కు భాషను ఎంచుకోండి',
      'language_partial': 'హెచ్చరికలు, తీర్పులు, నావిగేషన్ అనువదించబడ్డాయి. '
          'నేర్చుకునే వ్యాసాలు మరియు AI సారాంశం ఇంకా ఇంగ్లీషులో ఉన్నాయి.',
    },
  };
}
