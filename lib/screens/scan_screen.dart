import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../services/scam_detector.dart';
import '../services/api_service.dart';
import '../services/share_intent_service.dart';
import '../services/community_report_service.dart';
import '../services/cloud_account_service.dart';
import '../services/verdict_feedback_service.dart';
import '../services/localization_service.dart';
import '../data/models/scan_record.dart';
import '../services/upi_parser.dart';
import '../data/repositories/scan_repository.dart';
import 'qr_scan_screen.dart';
import 'upi_verify_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  AnalysisResult? _result;
  bool _isAnalyzing = false;
  final ScanRepository _repo = ScanRepository();

  int _activeTab = 0; // 0 = Message/Text, 1 = Link/URL

  // Community reporting — only meaningful for a URL, so this is populated
  // from the Link/URL tab and cleared whenever the input changes.
  String? _reportableUrl;
  ReputationResult? _reputation;
  bool _reportSubmitting = false;
  bool _reportSubmitted = false;

  // Verdict feedback — "was this right?". Held per result rather than
  // persisted: the point is to catch the user's reaction while the verdict is
  // still in front of them.
  String? _analyzedText;
  VerdictAgreement? _feedbackGiven;
  bool _feedbackSending = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    ShareIntentService.pending.addListener(_onSharedContent);
    // Handle content shared before this screen instance existed (e.g. a
    // cold-start share landed while MainNavigation was still building).
    // Deferred to after the first frame so it's safe to call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSharedContent());
  }

  @override
  void dispose() {
    ShareIntentService.pending.removeListener(_onSharedContent);
    _controller.dispose();
    _focusNode.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onSharedContent() {
    final request = ShareIntentService.pending.value;
    if (request == null) return;
    ShareIntentService.consume();

    switch (request.kind) {
      case SharedScanKind.text:
        final isLink = request.value.startsWith('http://') || request.value.startsWith('https://');
        setState(() {
          _activeTab = isLink ? 1 : 0;
          _controller.text = request.value;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        });
        _analyze(source: 'Shared');
        break;
      case SharedScanKind.image:
        setState(() => _activeTab = 3);
        _analyzeSharedImage(request.value);
        break;
    }
  }

  Future<void> _analyzeSharedImage(String path) async {
    setState(() {
      _isAnalyzing = true;
      _result = null;
    });

    final result = await ApiService.analyzeImage(File(path));

    try {
      final record = ScanRecord.fromAnalysisResult(
        inputText: 'Shared image: $path',
        result: result,
        source: 'Shared Image',
      );
      await _repo.saveScan(record);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _result = result;
        _isAnalyzing = false;
        // A shared image has no reportable URL of its own — clear any
        // leftover community-report state from a previous text/link scan.
        _reportableUrl = null;
        _reputation = null;
        _reportSubmitted = false;
        // The OCR'd text isn't surfaced here, so there is nothing stable to
        // hash — feedback is offered on text and link scans only.
        _analyzedText = null;
        _feedbackGiven = null;
      });
    }
  }

  Future<void> _analyze({String? source}) async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _showSnackBar(LocalizationService.tr('scan_empty_input'), isError: true);
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _result = null;
    });

    AnalysisResult result;
    try {
      result = await ApiService.analyzeMessage(text);
      if (result.riskScore == 0 && !result.aiPowered &&
          (result.reasons.isEmpty || result.reasons.first.label == 'Analysis Unavailable')) {
        result = ScamDetector.analyze(text);
      }
    } catch (_) {
      result = ScamDetector.analyze(text);
    }

    try {
      final resolvedSource = source ?? (_activeTab == 1 ? 'Link' : 'Manual');
      final record = ScanRecord.fromAnalysisResult(
        inputText: text,
        result: result,
        source: resolvedSource,
      );
      await _repo.saveScan(record);
    } catch (_) {}

    _maybeAlertFamily(result);

    if (mounted) {
      setState(() {
        _result = result;
        _isAnalyzing = false;
        _reportableUrl = null;
        _reputation = null;
        _reportSubmitted = false;
        _analyzedText = text;
        _feedbackGiven = null;
      });
      _maybeCheckCommunityReputation(text);
    }
  }

  /// Relays a dangerous verdict to the user's family group, if they're in one.
  ///
  /// Fire-and-forget on purpose: a relative's phone being unreachable must
  /// never delay or fail the scan the user is standing there waiting for. Only
  /// the verdict and summary go out — never the message itself.
  void _maybeAlertFamily(AnalysisResult result) {
    final isDangerous = result.classification == ScamClassification.scam ||
        (result.classification == ScamClassification.suspicious && result.riskScore >= 60);
    if (!isDangerous) return;

    CloudAccountService.raiseAlert(
      classification: result.classification.name,
      riskScore: result.riskScore,
      summary: result.summary,
    );
  }

  /// A URL/link is a stable enough indicator to crowdsource against — free
  /// text isn't (two people rarely type the exact same scam message), so
  /// community reporting is scoped to the Link/URL tab.
  void _maybeCheckCommunityReputation(String text) {
    final looksLikeUrl = _activeTab == 1 || text.startsWith('http://') || text.startsWith('https://');
    if (!looksLikeUrl) return;

    final url = text;
    setState(() => _reportableUrl = url);
    CommunityReportService.checkReputation(type: IndicatorType.url, value: url).then((result) {
      if (mounted && _reportableUrl == url) {
        setState(() => _reputation = result);
      }
    });
  }

  Future<void> _reportCurrentUrlAsScam() async {
    final url = _reportableUrl;
    if (url == null || _reportSubmitting) return;

    setState(() => _reportSubmitting = true);
    final ok = await CommunityReportService.reportIndicator(
      type: IndicatorType.url,
      value: url,
      category: _result?.classification.name,
    );
    if (!mounted) return;
    setState(() {
      _reportSubmitting = false;
      _reportSubmitted = ok;
    });
    _showSnackBar(
      ok ? 'Thanks — reported to help protect other users.' : 'Could not submit the report. Check your connection.',
      isError: !ok,
    );
  }

  void _clearAll() {
    setState(() {
      _controller.clear();
      _result = null;
      _reportableUrl = null;
      _reputation = null;
      _reportSubmitted = false;
      _analyzedText = null;
      _feedbackGiven = null;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (data?.text != null && data!.text!.isNotEmpty) {
      _controller.text = data.text!;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    } else {
      _showSnackBar('Clipboard is empty.', isError: false);
    }
  }

  Future<void> _scanQrCode() async {
    final decoded = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (!mounted || decoded == null || decoded.isEmpty) return;

    // A UPI payment QR gets the dedicated pre-payment check rather than being
    // dropped into the text box: the payee handle is the thing that needs
    // verifying, and it needs verifying *before* the payment app opens.
    final upi = UpiParser.tryParse(decoded);
    if (upi != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UpiVerifyScreen(request: upi, rawPayload: decoded),
        ),
      );
      return;
    }

    setState(() {
      _activeTab = 1; // QR payloads are almost always a URL/UPI link
      _controller.text = decoded;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
    _analyze();
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService.tr('scan_title'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: false,
        actions: [
          if (_result != null || _controller.text.isNotEmpty)
            TextButton.icon(
              onPressed: _clearAll,
              icon: const Icon(Icons.refresh, color: AppColors.primary, size: 16),
              label: Text(LocalizationService.tr('scan_clear'), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Reveal(delay: Reveal.step(0), child: _buildTabHeader()),
            const SizedBox(height: 16),
            Reveal(delay: Reveal.step(1), child: _buildInputField()),
            const SizedBox(height: 16),
            Reveal(delay: Reveal.step(2), child: _buildActionButton()),
            const SizedBox(height: 20),
            if (_isAnalyzing) _buildAnalyzingWidget(),
            if (_result != null && !_isAnalyzing) Reveal(child: _buildResultCard()),
            if (_result != null && !_isAnalyzing && _analyzedText != null) ...[
              const SizedBox(height: 12),
              Reveal(child: _buildFeedbackSection()),
            ],
            if (_result != null && !_isAnalyzing && _reportableUrl != null) ...[
              const SizedBox(height: 12),
              Reveal(child: _buildCommunitySection()),
            ],
            if (_result == null && !_isAnalyzing)
              Reveal(delay: Reveal.step(3), child: _buildSamplePrompts()),
          ],
        ),
      ),
    );
  }

  Widget _buildTabHeader() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildTabButton(0, 'SMS / TEXT', Icons.message_outlined)),
              Expanded(child: _buildTabButton(1, 'URL / LINK', Icons.link)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _buildTabButton(2, 'VOICE NOTE', Icons.mic_none)),
              Expanded(child: _buildTabButton(3, 'SCREENSHOT', Icons.image_outlined)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSel = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSel ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSel ? Colors.black : AppColors.textSecondary, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSel ? Colors.black : AppColors.textSecondary,
                fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _activeTab == 0
                    ? 'PASTE SUSPICIOUS TEXT'
                    : _activeTab == 1
                        ? 'PASTE SUSPICIOUS LINK'
                        : _activeTab == 2
                            ? 'VOICE NOTE TRANSCRIPT / PROMPT'
                            : 'SCREENSHOT OCR / EXTRACTED TEXT',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: _scanQrCode,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: const [
                          Icon(Icons.qr_code_scanner, color: AppColors.primary, size: 14),
                          SizedBox(width: 4),
                          Text('SCAN QR', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _pasteFromClipboard,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: const [
                          Icon(Icons.content_paste, color: AppColors.primary, size: 14),
                          SizedBox(width: 4),
                          Text('PASTE', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: 5,
            minLines: 3,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: _activeTab == 0
                  ? 'e.g. "URGENT: Your bank account is locked! Click http://bit.ly/fake-bank to verify now."'
                  : _activeTab == 1
                      ? 'e.g. "https://secure-login-verify.top/auth"'
                      : _activeTab == 2
                          ? 'Paste audio transcript or tap scan to analyze voice note.'
                          : 'Paste image text or tap scan to run screenshot OCR.',
              filled: false,
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    final hasText = _controller.text.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: hasText
            ? const LinearGradient(colors: [AppColors.primary, AppColors.accent])
            : null,
        color: hasText ? null : AppColors.surfaceLight.withValues(alpha: 0.4),
      ),
      child: ElevatedButton(
        onPressed: _isAnalyzing ? null : _analyze,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.security, color: hasText ? Colors.black : AppColors.textSecondary, size: 20),
            const SizedBox(width: 10),
            Text(
              'ANALYZE FOR THREATS',
              style: TextStyle(
                color: hasText ? Colors.black : AppColors.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyzingWidget() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.psychology, color: AppColors.primary, size: 48),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Analyzing with Gemini AI...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Extracting entities, scam patterns, and risk factors', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 20),
          const LinearProgressIndicator(color: AppColors.primary, backgroundColor: AppColors.surfaceLight),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final r = _result!;
    final Color badgeColor;
    final IconData badgeIcon;
    switch (r.classification.name.toLowerCase()) {
      case 'scam':
        badgeColor = AppColors.danger;
        badgeIcon = Icons.gpp_bad_outlined;
        break;
      case 'suspicious':
        badgeColor = AppColors.warning;
        badgeIcon = Icons.gpp_maybe_outlined;
        break;
      default:
        badgeColor = AppColors.success;
        badgeIcon = Icons.gpp_good_outlined;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(color: badgeColor.withValues(alpha: 0.12), blurRadius: 20, spreadRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                child: Icon(badgeIcon, color: badgeColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          // Translated, not `r.classification.name` upcased:
                          // this is the one line the user has to understand.
                          LocalizationService.tr('verdict_${r.classification.name}'),
                          style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1),
                        ),
                        const SizedBox(width: 8),
                        if (r.aiPowered)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                            child: const Text('GEMINI AI', style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${LocalizationService.tr('scan_risk_score')}: ${r.riskScore}/100', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(LocalizationService.tr('scan_summary'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(r.summary, style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textPrimary)),
          if (r.reasons.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(LocalizationService.tr('scan_factors'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1)),
            const SizedBox(height: 10),
            ...r.reasons.asMap().entries.map((entry) => Reveal(
              delay: Reveal.step(entry.key, baseMs: 120),
              offsetY: 14,
              child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: entry.value.scoreContribution > 20 ? AppColors.danger : AppColors.warning, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.value.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Text(entry.value.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ))),
          ],
        ],
      ),
    );
  }

  Future<void> _submitFeedback(VerdictAgreement agreement) async {
    final text = _analyzedText;
    final result = _result;
    if (text == null || result == null || _feedbackSending) return;

    setState(() => _feedbackSending = true);
    final ok = await VerdictFeedbackService.submit(
      text: text,
      classification: result.classification.name,
      riskScore: result.riskScore,
      agreement: agreement,
    );
    if (!mounted) return;

    setState(() {
      _feedbackSending = false;
      // Only claim it landed if it actually did — a thank-you for something
      // that never left the device is worse than an error.
      _feedbackGiven = ok ? agreement : null;
    });
    if (!ok) {
      _showSnackBar("Couldn't send that just now. Your scan is unaffected.", isError: true);
    }
  }

  /// "Was this right?" — the one thing the detection pipeline cannot work out
  /// on its own. A false positive on a real bank SMS is invisible to us unless
  /// the person who received it says so.
  Widget _buildFeedbackSection() {
    final r = _result!;
    final flagged = r.classification != ScamClassification.safe;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: _feedbackGiven != null
          ? Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppColors.success, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    LocalizationService.tr('feedback_thanks'),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocalizationService.tr('feedback_prompt'),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                Text(
                  LocalizationService.tr('feedback_privacy'),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.4),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _feedbackButton(
                        label: LocalizationService.tr('feedback_correct'),
                        icon: Icons.thumb_up_outlined,
                        color: AppColors.success,
                        agreement: VerdictAgreement.correct,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      // The useful wrong answer differs by verdict: on a
                      // flagged message the mistake worth reporting is "this
                      // is actually fine", and on a safe one it is "this was
                      // actually a scam". Offering both every time just makes
                      // the user work out which one applies.
                      child: flagged
                          ? _feedbackButton(
                              label: LocalizationService.tr('feedback_legit'),
                              icon: Icons.verified_outlined,
                              color: AppColors.warning,
                              agreement: VerdictAgreement.falsePositive,
                            )
                          : _feedbackButton(
                              label: LocalizationService.tr('feedback_was_scam'),
                              icon: Icons.report_gmailerrorred_outlined,
                              color: AppColors.danger,
                              agreement: VerdictAgreement.missed,
                            ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _feedbackButton({
    required String label,
    required IconData icon,
    required Color color,
    required VerdictAgreement agreement,
  }) {
    return OutlinedButton.icon(
      onPressed: _feedbackSending ? null : () => _submitFeedback(agreement),
      icon: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildCommunitySection() {
    final reputation = _reputation;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.groups_outlined, color: AppColors.textSecondary, size: 16),
              SizedBox(width: 8),
              Text('COMMUNITY REPORTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 10),
          if (reputation == null)
            const Text('Checking community reports...', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))
          else if (!reputation.checked)
            const Text('Could not reach the community database right now.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))
          else if (reputation.reported)
            Text(
              'Flagged by ${reputation.reportCount} user(s) as a scam${reputation.category != null ? " (${reputation.category})" : ""}.',
              style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.bold),
            )
          else if (reputation.reportCount > 0)
            Text(
              'Reported ${reputation.reportCount} time(s) — not yet enough reports to confirm.',
              style: const TextStyle(color: AppColors.warning, fontSize: 12),
            )
          else
            const Text('No prior reports for this link.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_reportSubmitting || _reportSubmitted) ? null : _reportCurrentUrlAsScam,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: Icon(
                _reportSubmitted ? Icons.check_circle_outline : Icons.flag_outlined,
                color: AppColors.danger,
                size: 16,
              ),
              label: Text(
                _reportSubmitted ? 'REPORTED — THANK YOU' : 'REPORT THIS LINK AS A SCAM',
                style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSamplePrompts() {
    final samples = [
      'URGENT: Your account has been suspended. Verify at http://bit.ly/bank-fix',
      'Congratulations! You won \$10,000 cash. Reply with your bank details.',
      'Your package #92819 is waiting. Pay \$2.50 fee at http://fake-post.top',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('TRY SAMPLE MESSAGES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1)),
        const SizedBox(height: 10),
        ...samples.asMap().entries.map((entry) => Reveal(
          delay: Reveal.step(entry.key, baseMs: 90),
          child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Pressable(
            onTap: () {
              _controller.text = entry.value;
              _analyze();
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.touch_app_outlined, color: AppColors.primary, size: 16),
                  const SizedBox(width: 10),
                  Expanded(child: Text(entry.value, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                ],
              ),
            ),
          ),
        ))),
      ],
    );
  }
}
