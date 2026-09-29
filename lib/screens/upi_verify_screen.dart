// lib/screens/upi_verify_screen.dart
//
// The pre-payment interstitial: shown after scanning a UPI QR, before the user
// opens their payment app.
//
// This is the highest-leverage moment in an Indian payment scam. Once the user
// is inside GPay/PhonePe with the payee pre-filled, they are one tap and a PIN
// from an irreversible transfer, and every UI cue there is designed to make
// that tap fast. So this screen deliberately slows things down: it names who
// is actually being paid, checks that handle against community reports, and
// makes "not now" the easy option.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/motion.dart';
import '../services/community_report_service.dart';
import '../services/upi_parser.dart';

class UpiVerifyScreen extends StatefulWidget {
  final UpiPaymentRequest request;
  final String rawPayload;

  const UpiVerifyScreen({
    super.key,
    required this.request,
    required this.rawPayload,
  });

  @override
  State<UpiVerifyScreen> createState() => _UpiVerifyScreenState();
}

class _UpiVerifyScreenState extends State<UpiVerifyScreen> {
  ReputationResult? _reputation;
  bool _checking = true;
  bool _reporting = false;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final result = await CommunityReportService.checkReputation(
      type: IndicatorType.upi,
      value: widget.request.payeeAddress,
    );
    if (!mounted) return;
    setState(() {
      _reputation = result;
      _checking = false;
    });
  }

  Future<void> _report() async {
    setState(() => _reporting = true);
    final ok = await CommunityReportService.reportIndicator(
      type: IndicatorType.upi,
      value: widget.request.payeeAddress,
      category: 'upi fraud',
    );
    if (!mounted) return;
    setState(() {
      _reporting = false;
      _reported = ok;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Reported. Thanks — this warns the next person who scans it.'
            : 'Could not submit the report. Check your connection.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ok ? AppColors.surfaceLight : AppColors.danger,
      ),
    );
  }

  Future<void> _openPaymentApp() async {
    final uri = Uri.parse(widget.rawPayload);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No UPI app could handle this code.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open a UPI app for this code.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Three states, and they are not the same thing: reported (danger),
  /// checked-and-clean (no reports, but that is not a guarantee), and
  /// unavailable (we could not check — which must never look like "clean").
  ({Color color, IconData icon, String title, String body}) get _verdict {
    final rep = _reputation;
    if (rep == null || !rep.checked) {
      return (
        color: AppColors.textSecondary,
        icon: Icons.help_outline,
        title: 'Could not check this payee',
        body: 'The reputation service is unreachable, so this handle has NOT been '
            'checked. That is not the same as it being safe.',
      );
    }
    if (rep.reported) {
      return (
        color: AppColors.danger,
        icon: Icons.dangerous_outlined,
        title: 'Reported as a scam',
        body: '${rep.reportCount} ScamShield user(s) have reported this UPI handle'
            '${rep.category != null ? ' (${rep.category})' : ''}. Do not pay it.',
      );
    }
    if (rep.reportCount > 0) {
      return (
        color: AppColors.warning,
        icon: Icons.warning_amber_rounded,
        title: 'Reported ${rep.reportCount} time(s)',
        body: 'Not yet enough reports to confirm, but treat this handle with caution.',
      );
    }
    return (
      color: AppColors.success,
      icon: Icons.verified_user_outlined,
      title: 'No reports for this payee',
      body: 'Nobody has reported this handle. That is not proof it is genuine — '
          'only pay if you know who it belongs to.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final verdict = _verdict;

    return Scaffold(
      appBar: AppBar(title: const Text('Check before you pay')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Reveal(delay: Reveal.step(0), child: _buildVerdictCard(verdict)),
            const SizedBox(height: 18),
            Reveal(delay: Reveal.step(1), child: _buildPayeeCard(req)),
            const SizedBox(height: 18),
            Reveal(delay: Reveal.step(2), child: _buildGuidance(req)),
            const SizedBox(height: 24),
            Reveal(delay: Reveal.step(3), child: _buildActions()),
          ],
        ),
      ),
    );
  }

  Widget _buildVerdictCard(({Color color, IconData icon, String title, String body}) v) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: v.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: v.color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _checking
              ? const SizedBox(
                  width: 26, height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary))
              : Icon(v.icon, color: v.color, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _checking ? 'Checking this payee…' : v.title,
                  style: TextStyle(color: v.color, fontWeight: FontWeight.w700, fontSize: 15.5),
                ),
                if (!_checking) ...[
                  const SizedBox(height: 6),
                  Text(v.body,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 12.5, height: 1.45)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayeeCard(UpiPaymentRequest req) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('YOU WOULD BE PAYING',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 1.1,
              )),
          const SizedBox(height: 10),
          SelectableText(
            req.payeeAddress,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (req.payeeName != null) ...[
            const SizedBox(height: 4),
            Text(req.payeeName!,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _fact(
                  'Amount',
                  req.hasFixedAmount ? '${req.currency ?? 'INR'} ${req.amount}' : 'You would enter it',
                  highlight: !req.hasFixedAmount,
                ),
              ),
              Expanded(child: _fact('Handle', req.handleProvider.isEmpty ? '—' : req.handleProvider)),
            ],
          ),
          if (req.note != null) ...[
            const SizedBox(height: 12),
            _fact('Note', req.note!),
          ],
        ],
      ),
    );
  }

  Widget _fact(String label, String value, {bool highlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: highlight ? AppColors.warning : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildGuidance(UpiPaymentRequest req) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text('Worth knowing',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            ],
          ),
          const SizedBox(height: 10),
          const _Bullet(
            'Scanning a UPI QR always SENDS money. No QR code can ever pull money '
            'into your account, whatever you were told.',
          ),
          if (!req.hasFixedAmount)
            const _Bullet(
              'This code does not fix an amount — you would type it in. That is how '
              '"scan to receive your refund" scams get you to send the amount yourself.',
            ),
          const _Bullet(
            'The name shown in your payment app is set by the payee\'s bank, not '
            'verified by whoever gave you this code.',
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final dangerous = _reputation?.reported == true;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.black, size: 18),
            label: const Text("Don't pay — go back",
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: (_reporting || _reported) ? null : _report,
            icon: Icon(_reported ? Icons.check : Icons.flag_outlined,
                color: AppColors.danger, size: 18),
            label: Text(
              _reported ? 'Reported — thank you' : 'Report this payee as a scam',
              style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.danger),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Continuing is deliberately the quietest control on the screen, and
        // disappears entirely once the handle is known-bad.
        if (!dangerous)
          TextButton(
            onPressed: _openPaymentApp,
            child: const Text(
              'I know this payee — open my UPI app',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          )
        else
          const Text(
            'This payee has been reported as a scam, so ScamShield will not open '
            'your payment app for it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.danger, fontSize: 12, height: 1.4),
          ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: SizedBox(
              width: 5,
              height: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              ),
            ),
          ),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12, height: 1.45)),
          ),
        ],
      ),
    );
  }
}
