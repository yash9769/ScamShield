// lib/screens/consent_screen.dart
//
// First-launch (and post-policy-change) consent gate. Shown before the
// login/main app whenever ConsentService.hasGivenCurrentConsent() is false.
// The checkbox starts UNCHECKED (no pre-selected consent) and "I Agree &
// Continue" stays disabled until the user affirmatively checks it — a
// deliberate, informed action, not a default.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/consent_service.dart';
import 'privacy_policy_screen.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, required this.onConsented});

  final VoidCallback onConsented;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _agreed = false;
  bool _saving = false;
  final _consentService = ConsentService();

  Future<void> _continue() async {
    if (!_agreed || _saving) return;
    setState(() => _saving = true);
    await _consentService.grantEssentialConsent();
    if (!mounted) return;
    widget.onConsented();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Icon(Icons.privacy_tip_outlined, color: AppColors.primary, size: 42),
              const SizedBox(height: 16),
              const Text(
                'Before you continue',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'ScamShield needs to process the text, links and files you submit in order to '
                'give you a scam/safety verdict, and stores your scan history and account '
                'locally on this device. Please review how your data is handled before you '
                'continue.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen(showAcceptedVersion: false)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.article_outlined, color: AppColors.primary, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Read the full Privacy Policy',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _agreed,
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => _agreed = v ?? false),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _agreed = !_agreed),
                        child: const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'I have read and agree to the Privacy Policy, including that my '
                            'submitted scan content may be sent to third-party AI providers for '
                            'analysis.',
                            style: TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _agreed && !_saving ? _continue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.surfaceLight.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(
                          'I Agree & Continue',
                          style: TextStyle(
                            color: _agreed ? Colors.black : AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
