import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../services/scam_detector.dart';
import '../services/api_service.dart';
import '../services/app_capabilities_service.dart';
import '../data/models/scan_record.dart';
import '../data/repositories/scan_repository.dart';

class ScanScreen extends StatefulWidget {
  final String? initialText;
  
  const ScanScreen({super.key, this.initialText});

  /// Set by [ScamShieldApp]'s navigation when the user taps "SCAN NOW" on a
  /// clipboard alert. The scanner picks the value up, prefills the input, and
  /// runs the explicit backend scan.
  static final ValueNotifier<String?> pendingClipboardScan =
      ValueNotifier<String?>(null);

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

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    ScanScreen.pendingClipboardScan.addListener(_handlePendingClipboardScan);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // If initialText was provided (via deep link), prefill and analyze
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _controller.text = widget.initialText!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _analyze();
      });
    }
  }

  void _handlePendingClipboardScan() {
    final text = ScanScreen.pendingClipboardScan.value;
    if (text == null || text.isEmpty || !mounted) return;
    ScanScreen.pendingClipboardScan.value = null;
    _controller.text = text;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    setState(() {
      _activeTab = RegExp(r'https?://', caseSensitive: false).hasMatch(text) ? 1 : 0;
    });
    _analyze();
  }

  @override
  void dispose() {
    ScanScreen.pendingClipboardScan.removeListener(_handlePendingClipboardScan);
    _controller.dispose();
    _focusNode.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      HapticFeedback.lightImpact();
      _showSnackBar('Please enter some text or link to analyze.', isError: true);
      return;
    }

    // Add haptic feedback when scan starts
    HapticFeedback.mediumImpact();
    setState(() {
      _isAnalyzing = true;
      _result = null;
    });

    AnalysisResult result;
    try {
      result = await ApiService.analyzeMessage(text);
      // If the backend was unreachable (status != analyzed), fall back to the
      // local engine, which genuinely analyses the text. The result is then
      // a real verdict rather than a "not checked" placeholder.
      if (!result.isAnalyzed) {
        result = ScamDetector.analyze(text);
      }
    } catch (_) {
      result = ScamDetector.analyze(text);
    }

    try {
      final source = _activeTab == 1 ? 'Link' : 'Manual';
      final record = ScanRecord.fromAnalysisResult(
        inputText: text,
        result: result,
        source: source,
      );
      await _repo.saveScan(record);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _result = result;
        _isAnalyzing = false;
      });
    }
  }

  void _clearAll() {
    HapticFeedback.mediumImpact();
    setState(() {
      _controller.clear();
      _result = null;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _controller.text = data.text!;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    } else {
      _showSnackBar('Clipboard is empty.', isError: false);
    }
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
        title: const Text('Threat Scanner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: false,
        actions: [
          if (_result != null || _controller.text.isNotEmpty)
            TextButton.icon(
              onPressed: _clearAll,
              icon: const Icon(Icons.refresh, color: AppColors.primary, size: 16),
              label: const Text('CLEAR', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
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
                          ? 'Paste or record audio content. ScamShield will transcribe and analyze for scam patterns.'
                          : 'Paste or upload a screenshot. ScamShield will extract and analyze text for threats.',
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
              'SCAN',
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
    final caps = AppCapabilitiesService.capabilities.value;
    final isFullAiMode = r.aiPowered && r.isAnalyzed && caps.hasFullAi;

    final Color badgeColor;
    final IconData badgeIcon;
    final String badgeLabel;
    if (!r.isAnalyzed) {
      // NEVER render "we could not check" as a green Safe verdict.
      badgeColor = AppColors.textSecondary;
      badgeIcon = Icons.help_outline;
      badgeLabel = 'NOT ANALYZED';
    } else {
      switch (r.classification.name.toLowerCase()) {
        case 'scam':
          badgeColor = AppColors.danger;
          badgeIcon = Icons.gpp_bad_outlined;
          badgeLabel = 'SCAM';
          break;
        case 'suspicious':
          badgeColor = AppColors.warning;
          badgeIcon = Icons.gpp_maybe_outlined;
          badgeLabel = 'SUSPICIOUS';
          break;
        default:
          // Rule: Never show green "safe" styling when AI/OSINT was unavailable.
          badgeColor = isFullAiMode ? AppColors.success : AppColors.warning;
          badgeIcon = isFullAiMode ? Icons.gpp_good_outlined : Icons.shield_outlined;
          badgeLabel = isFullAiMode ? 'SAFE' : 'NO THREATS FOUND (HEURISTIC ONLY)';
      }
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
                        Flexible(
                          child: Text(
                            badgeLabel,
                            style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isFullAiMode ? AppColors.primary : AppColors.warning).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isFullAiMode
                                ? (caps.hasOsint ? 'GEMINI AI + LIVE OSINT' : 'GEMINI AI (OSINT LIMITED)')
                                : 'LOCAL HEURISTIC ONLY',
                            style: TextStyle(
                              color: isFullAiMode ? AppColors.primary : AppColors.warning,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.isAnalyzed ? 'Risk Score: ${r.riskScore}/100' : 'No risk score — content was not analysed',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (r.isAnalyzed) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: r.riskScore / 100,
                minHeight: 8,
                backgroundColor: AppColors.surfaceLight,
                color: badgeColor,
              ),
            ),
            const SizedBox(height: 16),
          ],
          const Text('SECURITY SUMMARY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(r.summary, style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textPrimary)),
          if (r.reasons.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('RISK INDICATORS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1)),
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
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              final shareText = 'ScamShield Audit: ${r.classification.name.toUpperCase()} (Score: ${r.riskScore}/100)\n'
                  'Summary: ${r.summary}';
              Clipboard.setData(ClipboardData(text: shareText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Audit verdict copied to clipboard.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 16, color: AppColors.primary),
            label: const Text('COPY SECURITY VERDICT', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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