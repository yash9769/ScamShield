// lib/widgets/google_sign_in_button.dart
//
// Shared "Continue with Google" control for the login and register screens.
//
// NOTE ON BRANDING: this draws a plain "G" mark rather than Google's official
// multi-colour logo, because that logo is a trademarked asset that has to be
// downloaded from Google's brand guidelines page and added to assets/. Before
// shipping to the Play Store, drop the official mark in and swap the
// _GoogleMark widget for it — Google's Sign-In branding guidelines require the
// official asset and specific button proportions.

import 'package:flutter/material.dart';
import '../theme.dart';

class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;

  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.label = 'Continue with Google',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.6),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF4285F4)),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _GoogleMark(),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF1F1F1F),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF4285F4),
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Text(
        'G',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

/// Divider with a centred "or" — used between the Google button and the
/// email/password form on both auth screens.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.surfaceLight.withValues(alpha: 0.8))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(child: Divider(color: AppColors.surfaceLight.withValues(alpha: 0.8))),
      ],
    );
  }
}
