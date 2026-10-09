// lib/screens/language_screen.dart
//
// Language picker.
//
// Each option is labelled in its own script first, because someone looking for
// their own language should not have to read English to find it — which is the
// whole reason they are on this screen.

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/motion.dart';
import '../services/localization_service.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocalizationService.tr('language_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            LocalizationService.tr('language_subtitle'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 18),
          ...LocalizationService.supported.asMap().entries.map(
                (e) => Reveal(
                  delay: Reveal.step(e.key, stepMs: 45),
                  child: _buildOption(e.value),
                ),
              ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  // Says plainly what is and isn't translated. A user who
                  // switches language and then meets an English scan summary
                  // should have been told, not left wondering whether the app
                  // is broken.
                  child: Text(
                    LocalizationService.tr('language_partial'),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(AppLanguage lang) {
    final selected = LocalizationService.language.value == lang.code;
    return GestureDetector(
      onTap: () async {
        await LocalizationService.setLanguage(lang.code);
        if (mounted) setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.6)
                : AppColors.surfaceLight.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lang.nativeName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.primary : AppColors.textPrimary,
                    ),
                  ),
                  // Skipped for English, where it would just repeat itself.
                  if (lang.nativeName != lang.englishName) ...[
                    const SizedBox(height: 2),
                    Text(
                      lang.englishName,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
