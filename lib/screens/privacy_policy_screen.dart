// lib/screens/privacy_policy_screen.dart
//
// In-app Privacy Notice (DPDP Act, 2023 alignment). Content reflects what
// the app actually does today, based on DPDP_AUDIT.md. Placeholders are
// used only where genuinely unavailable (entity/contact details) — see
// DPDP_COMPLIANCE.md for what still requires a product/legal decision.

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
              'audited behaviour of the app (see DPDP_AUDIT.md in the project repository) '
              'rather than aspirational feature claims.',
            ),
            _section(
              'What data ScamShield processes',
              '• Account: an email address and password, hashed on your device and never '
              'sent anywhere — there is no account server. \n'
              '• Profile: a display name, title and avatar you choose, stored only on your device. \n'
              '• Scan content: text/SMS/links you paste or that are auto-detected on your '
              'clipboard, sent to our analysis server to classify as safe/suspicious/scam. \n'
              '• APK files: files you choose to scan, uploaded temporarily for static '
              'security analysis and deleted immediately after the response is sent. \n'
              '• Email (breach lookup): an email address you enter, sent to our server and '
              'forwarded to a third-party breach-database provider to check for exposure. \n'
              '• Safe Vault: any notes, PINs or credentials you choose to store, encrypted '
              'on-device only — never transmitted anywhere.',
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
              'Third-party services',
              'Depending on server configuration, scan content, extracted URLs/hashes, or the '
              'email you look up may be forwarded to: Groq or Google Gemini (AI text '
              'classification), VirusTotal (file-hash reputation), Google Safe Browsing '
              '(URL reputation), and XposedOrNot (email breach data). A full list with what '
              'is sent to each is in THIRD_PARTY_DATA_PROCESSORS.md. We do not sell personal '
              'data or use it for advertising.',
            ),
            _section(
              'Where your data is stored',
              'Account credentials, profile, settings, scan history and Safe Vault items are '
              'stored only on your device (secure OS-backed storage or local SQLite). A short, '
              'redacted operational log (message excerpts and filenames, for abuse detection) '
              'is kept on the ScamShield server; see "Data retention" below.',
            ),
            _section(
              'Data retention',
              'Local scan history stays on your device until you delete it — individually, in '
              'bulk from History, or via Settings > Privacy & Data > Delete My Data. Automatic '
              'retention periods are configurable in Settings > Privacy & Data > Data Retention '
              '(default: kept until you delete it — REQUIRES PRODUCT DECISION on a mandatory '
              'default; see DPDP_COMPLIANCE.md). Server-side operational logs are retained per '
              'the operator\'s configured retention window, or indefinitely if none has been set '
              '(REQUIRES PRODUCT DECISION).',
            ),
            _section(
              'Your controls',
              '• View and edit your profile in Profile > Edit Profile & Avatar. \n'
              '• Delete individual scans, or clear all history, from the History screen. \n'
              '• Delete all Safe Vault items from the Safe Vault screen. \n'
              '• Export a copy of the data ScamShield holds about you: Settings > Privacy & '
              'Data > My Data. \n'
              '• Delete your locally stored data (keeping your account) or delete your account '
              'entirely: Settings > Privacy & Data. \n'
              '• Withdraw AI-processing consent at any time: Settings > Privacy & Data > '
              'Manage Consent.',
            ),
            _section(
              'Security measures',
              'Passwords are hashed with PBKDF2-HMAC-SHA256 (120,000 iterations, random salt) '
              'and never stored or transmitted in plaintext. Account and Safe Vault data are '
              'stored using your device\'s secure keystore (Android Keystore / iOS Keychain). '
              'APK uploads are validated (type, size, structure) and deleted immediately after '
              'analysis. Server admin endpoints require a separate admin credential.',
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
