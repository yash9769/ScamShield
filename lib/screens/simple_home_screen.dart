// lib/screens/simple_home_screen.dart
//
// The entire app, in Simple Mode. See simple_mode_service.dart for why this
// exists at all rather than as a text-size setting.
//
// ── Rules this screen follows ──────────────────────────────────────────────
// 1. One action visible at a time. There is no navigation bar, no tabs, and
//    nothing to get lost in — paste, check, read the answer.
// 2. The verdict is an instruction, not a measurement. No risk score, no
//    percentage, no confidence. "Do not reply. Do not send money." is
//    something a frightened person can act on; "62/100" is not.
// 3. Colour is never the only signal. Every verdict pairs its colour with a
//    large icon and unambiguous words, because a red banner means nothing to
//    someone with red-green colour blindness — a group that overlaps heavily
//    with the older users this mode is for.
// 4. Nothing is destructive or hard to undo. The only way out is a clearly
//    labelled button back to the full app.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../services/api_service.dart';
import '../services/scam_detector.dart';
import '../services/simple_mode_service.dart';
import '../services/cloud_account_service.dart';
import '../data/models/scan_record.dart';
import '../data/repositories/scan_repository.dart';

class SimpleHomeScreen extends StatefulWidget {
  const SimpleHomeScreen({super.key});

  @override
  State<SimpleHomeScreen> createState() => _SimpleHomeScreenState();
}

class _SimpleHomeScreenState extends State<SimpleHomeScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScanRepository _repo = ScanRepository();

  bool _checking = false;
  AnalysisResult? _result;

  // Every size on this screen is deliberately larger than the standard app's.
  // These are named rather than sprinkled inline so the whole scale can be
  // adjusted in one place if it turns out still to be too small in testing.
  static const double _bodySize = 18;
  static const double _buttonSize = 20;
  static const double _verdictSize = 34;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) {
      _toast('There is nothing copied to paste.');
      return;
    }
    setState(() {
      _controller.text = text;
      _result = null;
    });
  }

  Future<void> _check() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _toast('Paste or type the message first.');
      return;
    }

    setState(() {
      _checking = true;
      _result = null;
    });

    // Identical analysis path to the standard app, including the offline
    // fallback. Simple Mode changes how the answer is presented, never how it
    // is reached — a second, differently-behaved scanner is exactly the kind
    // of drift that gets someone hurt.
    AnalysisResult result;
    try {
      result = await ApiService.analyzeMessage(text);
      if (result.riskScore == 0 &&
          !result.aiPowered &&
          (result.reasons.isEmpty ||
              result.reasons.first.label == 'Analysis Unavailable')) {
        result = ScamDetector.analyze(text);
      }
    } catch (_) {
      result = ScamDetector.analyze(text);
    }

    try {
      await _repo.saveScan(ScanRecord.fromAnalysisResult(
        inputText: text,
        result: result,
        source: 'Simple Mode',
      ));
    } catch (_) {}

    // Same family relay as the standard app: in this mode especially, the
    // person best placed to help may be a relative rather than the user.
    if (result.classification == ScamClassification.scam ||
        (result.classification == ScamClassification.suspicious &&
            result.riskScore >= 60)) {
      CloudAccountService.raiseAlert(
        classification: result.classification.name,
        riskScore: result.riskScore,
        summary: result.summary,
      );
    }

    if (!mounted) return;
    setState(() {
      _result = result;
      _checking = false;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: _bodySize)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceLight,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Is this a scam?',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Paste the message you received and press Check.',
                style: TextStyle(
                  fontSize: _bodySize,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              _buildInput(),
              const SizedBox(height: 16),
              _buildBigButton(
                label: 'Paste message',
                icon: Icons.content_paste,
                filled: false,
                onPressed: _checking ? null : _paste,
              ),
              const SizedBox(height: 12),
              _buildBigButton(
                label: _checking ? 'Checking…' : 'Check this message',
                icon: Icons.search,
                filled: true,
                onPressed: _checking ? null : _check,
              ),
              if (_result != null) ...[
                const SizedBox(height: 28),
                _buildVerdict(_result!),
              ],
              const SizedBox(height: 36),
              TextButton(
                onPressed: () => SimpleModeService.setEnabled(false),
                child: const Text(
                  'Switch to the full app',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      padding: const EdgeInsets.all(4),
      child: TextField(
        controller: _controller,
        maxLines: 6,
        minLines: 4,
        style: const TextStyle(fontSize: _bodySize, height: 1.4),
        decoration: const InputDecoration(
          hintText: 'The message goes here',
          hintStyle: TextStyle(fontSize: _bodySize, color: AppColors.textSecondary),
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(14),
        ),
      ),
    );
  }

  Widget _buildBigButton({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback? onPressed,
  }) {
    // A 64pt target, well above the 48dp minimum — this mode is used by people
    // with less steady hands, and a mis-tap here is a real cost.
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 24, color: filled ? Colors.black : AppColors.primary),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: _buttonSize,
              fontWeight: FontWeight.bold,
              color: filled ? Colors.black : AppColors.primary,
            ),
          ),
        ),
      ],
    );

    return SizedBox(
      height: 64,
      child: filled
          ? ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: child,
            ),
    );
  }

  Widget _buildVerdict(AnalysisResult result) {
    // The verdict, and what to do about it. No score, no percentage, no
    // "confidence" — those are things to think about, and someone mid-scam
    // does not need more to think about.
    final (Color color, IconData icon, String headline, String advice) =
        switch (result.classification) {
      ScamClassification.scam => (
          AppColors.danger,
          Icons.dangerous,
          'This is a scam',
          'Do not reply. Do not click any link. Do not send money or share any '
              'code. It is safe to delete this message.',
        ),
      ScamClassification.suspicious => (
          AppColors.warning,
          Icons.warning_amber_rounded,
          'Be careful',
          'This may not be genuine. Do not send money or share any code. If it '
              'claims to be your bank, hang up and call the number printed on '
              'your card.',
        ),
      ScamClassification.safe => (
          AppColors.success,
          Icons.check_circle,
          'This looks safe',
          'Nothing dangerous was found. Still never share a code or password '
              'with anyone who contacts you first.',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 64),
          const SizedBox(height: 14),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _verdictSize,
              fontWeight: FontWeight.bold,
              color: color,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            advice,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: _bodySize,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
