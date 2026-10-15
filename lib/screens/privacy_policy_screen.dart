// lib/screens/privacy_policy_screen.dart
//
// In-app Privacy Notice (DPDP Act, 2023 alignment). Content reflects what
// the app actually does today, based on DPDP_AUDIT.md and the protection-
// suite features added afterward (see DPDP_COMPLIANCE.md's dated addenda —
// most importantly, that a server-side account system now exists, which is
// a materially different data flow than the local-only accounts this notice
// originally described). Placeholders are used only where genuinely
// unavailable (entity/contact details) — see DPDP_COMPLIANCE.md for what
// still requires a product/legal decision.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/consent_service.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key, this.showAcceptedVersion = true});

  final bool showAcceptedVersion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showAcceptedVersion)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
                ),
                child: Text(
                  'Policy version ${ConsentService.currentPolicyVersion}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            _section(
              'What this notice covers',
              'This notice explains, in plain language, what personal data the ScamShield '
              'app processes, why, and what controls you have. It reflects the current, '
              'audited behaviour of the app rather than aspirational feature claims — every '
              'feature listed below is something the shipped app actually does.',
            ),
            _section(
              'What data ScamShield processes',
              '• Device account: an email address and password, hashed on your device and '
              'never sent anywhere. Signing in with Google works the same way, using '
              'Google\'s own verification instead of a password. \n'
              '• Profile: a display name, title and avatar you choose, stored only on your device. \n'
              '• Scan content: text/SMS/links you paste or that are auto-detected on your '
              'clipboard, sent to our analysis server to classify as safe/suspicious/scam. \n'
              '• APK files: files you choose to scan, uploaded temporarily for static '
              'security analysis and deleted immediately after the response is sent. \n'
              '• Email (breach lookup): an email address you enter, sent to our server and '
              'forwarded to a third-party breach-database provider to check for exposure. \n'
              '• Safe Vault: any notes, PINs or credentials you choose to store, encrypted '
              'on-device only — never transmitted anywhere. \n'
              '• Cloud sync account, scam call screening, family alerts, learning progress and '
              'verdict feedback: each is a separate, additional data flow, described in its own '
              'section below — none of them run unless you turn that specific feature on.',
            ),
            _section(
              'How scans are analysed',
              'When you submit text for analysis, it is sent to the ScamShield server, which '
              'either uses a third-party AI provider (Groq or Gemini, whichever is configured) '
              'to classify it, or falls back to an on-device rule-based engine if AI analysis '
              'is unavailable or if you have turned off AI-assisted analysis in '
              'Settings > Privacy & Data. You can disable AI-assisted analysis at any time; '
              'scanning continues to work using only the on-device engine.',
            ),
            _section(
              'Screenshot and voice-note processing',
              'The current release does not upload screenshot image bytes or audio bytes for '
              'analysis — screenshots are analysed by filename only, and voice-note upload is '
              'not exposed in the app UI. If/when these features are completed, this notice '
              'will be updated before they process image or audio content.',
            ),
            _section(
              'Cloud sync account (optional)',
              'This is a second, separate account from the one that unlocks the app on this '
              'device — you only get one if you set it up yourself, from Family Protection or '
              'Learn > Leaderboard. Creating one sends an email and password (or a verified '
              'Google identity) to the ScamShield server, which stores them there so the same '
              'account can be used from more than one phone.\n\n'
              'Once signed in, the full text of scans made on this device is uploaded to our '
              'server so your scan history can follow you to another device. This is the one '
              'point where scan content — which otherwise stays entirely on your device — '
              'leaves it for a reason other than one-time classification. It is stored under '
              'your account until you delete it (see "Your controls").',
            ),
            _section(
              'Family Protection (optional)',
              'If you create or join a family group, a high-risk scan on your device can raise '
              'an alert on a family member\'s phone. Only the verdict, a risk score and a short '
              'summary travel with that alert — never the message itself, so a parent\'s scam '
              'text routinely containing a bank name or partial card number never has to reach '
              'a relative\'s phone. \n\n'
              'The people in your family group can see your email or display name, and can see '
              'every alert you\'ve raised (verdict/score/summary, as above). Anyone with your '
              'invite code can join, so treat it like you would a password. Leaving a group '
              '(Family Protection > Leave) stops new alerts; it does not retroactively remove '
              'alerts you already sent that other members already have in their app.',
            ),
            _section(
              'Push notifications (optional)',
              'If you allow notifications, this device\'s notification token is registered with '
              'our server and, through it, with Google\'s Firebase Cloud Messaging service, so a '
              'family alert can wake your phone rather than waiting for you to next open the '
              'app. Only a generic "you may have been targeted" notification is sent this way — '
              'never the scam message itself. Turning notifications off, or signing out, removes '
              'this device\'s token.',
            ),
            _section(
              'Scam call screening (optional, Android 10+)',
              'If you turn this on, ScamShield becomes your phone\'s call-screening app and can '
              'warn you — never block the call — when a number that has already sent you a scam '
              'message, or one you\'ve added yourself, calls you. That list of numbers is built '
              'and kept entirely on your device from your own scan history and your own manual '
              'additions; it is not uploaded anywhere by default.\n\n'
              'A separate, off-by-default toggle ("check unknown callers online") sends an '
              'unrecognised caller\'s number to our server to check community reports about it. '
              'Leave that off and no caller\'s number ever leaves your device for this feature.',
            ),
            _section(
              'Learning progress & leaderboard (optional)',
              'The Learn tab tracks points, quiz results, articles read and a daily streak '
              'locally, whether or not you have a cloud account. If you do, that summary — '
              'never which specific quiz questions you got right or wrong — is also pushed to '
              'the server so you can appear on a leaderboard. Ranked against your family, your '
              'email or name is shown to the other members, since they already know you; ranked '
              'globally, your email is never shown — only a display name, or "ScamShield user" '
              'if you haven\'t set one.',
            ),
            _section(
              'Verdict feedback (anonymous)',
              'On any scan result you can say whether the verdict was right. This never sends '
              'the scanned message — only a one-way cryptographic fingerprint of it (so repeat '
              'votes on the same message don\'t get double-counted), the verdict, and your '
              'answer. No account is needed and none of it can be traced back to you or to the '
              'original message.',
            ),
            _section(
              'Encrypted local backup (optional)',
              'Settings > Privacy & Data > Backup & Restore lets you export your scan history, '
              'profile and settings to a file, encrypted with a passphrase only you know. '
              'ScamShield never transmits this file anywhere — creating and storing it '
              'is entirely your own action, the same as saving any other file on your phone. '
              'Safe Vault contents and sign-in credentials are deliberately left out of it.',
            ),
            _section(
              'Third-party services',
              'Depending on server configuration and which optional features you use, data may '
              'be forwarded to: Groq or Google Gemini (AI text classification of scan content), '
              'VirusTotal (file-hash reputation), Google Safe Browsing (URL reputation), '
              'XposedOrNot (email breach data), and Google Firebase Cloud Messaging (delivering '
              'family-alert push notifications, if you\'ve enabled them). A full list with what '
              'is sent to each is in THIRD_PARTY_DATA_PROCESSORS.md. We do not sell personal '
              'data or use it for advertising.',
            ),
            _section(
              'Where your data is stored',
              'Your device account, profile, settings, scan history and Safe Vault items are '
              'stored only on your device (secure OS-backed storage or local SQLite) — that '
              'part never changed. If you use a cloud sync account, family protection, push '
              'notifications, or the leaderboard, the data described in those sections above is '
              'additionally held on the ScamShield server for as long as that account exists. A '
              'short, redacted operational log (message excerpts and filenames, for abuse '
              'detection) is also kept on the server; see "Data retention" below.',
            ),
            _section(
              'Data retention',
              'Local scan history stays on your device until you delete it — individually, in '
              'bulk from History, or via Settings > Privacy & Data > Delete My Data. Automatic '
              'retention periods are configurable in Settings > Privacy & Data > Data Retention '
              '(default: kept until you delete it). Deleting a scan that was ever synced to a '
              'cloud account also removes the server\'s copy of it, not just the one on your '
              'device. Server-side operational logs are retained per the operator\'s configured '
              'retention window, or indefinitely if none has been set (REQUIRES PRODUCT '
              'DECISION; see DPDP_COMPLIANCE.md).',
            ),
            _section(
              'Your controls',
              '• View and edit your profile in Profile > Edit Profile & Avatar. \n'
              '• Delete individual scans, or clear all history, from the History screen — this '
              'also removes the server copy if the scan was ever synced. \n'
              '• Delete all Safe Vault items from the Safe Vault screen. \n'
              '• Export a copy of everything ScamShield holds about you, including your cloud '
              'account\'s data if you have one: Settings > Privacy & Data > My Data. \n'
              '• Delete your locally stored data (keeping your account) or delete your account '
              'entirely — the latter also deletes your cloud sync account, if you have one, and '
              'everything under it (synced scans, family membership, learning progress, push '
              'token): Settings > Privacy & Data. \n'
              '• Leave a family group at any time from Family Protection. \n'
              '• Turn off scam call screening, real-time SMS screening, online caller lookup, '
              'or push notifications independently, from Profile and Settings. \n'
              '• Withdraw AI-processing consent at any time: Settings > Privacy & Data > '
              'Manage Consent.',
            ),
            _section(
              'Security measures',
              'Local device passwords are hashed with PBKDF2-HMAC-SHA256 (120,000 iterations, '
              'random salt); cloud sync account passwords are hashed server-side with scrypt. '
              'Neither is ever stored or transmitted in plaintext. Account and Safe Vault data '
              'are stored using your device\'s secure keystore (Android Keystore / iOS '
              'Keychain). Encrypted backups use AES-256-GCM with a key derived from your '
              'passphrase. APK uploads are validated (type, size, structure) and deleted '
              'immediately after analysis. Server admin endpoints require a separate admin '
              'credential.',
            ),
            _section(
              'Grievance / contact',
              'PLACEHOLDER — this build does not yet have a designated Grievance Officer or '
              'support contact configured. REQUIRES PRODUCT/LEGAL DECISION: add a named '
              'contact and grievance-redressal process before production release, as required '
              'under the DPDP Act.',
            ),
            _section(
              'Changes to this notice',
              'If this notice changes materially, you will be asked to re-confirm your consent '
              'the next time you open the app.',
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary)),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
