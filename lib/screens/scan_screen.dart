import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../widgets/scamshield_hero_visual.dart';
import '../widgets/security_score.dart';
import '../widgets/premium_cta.dart';
import '../services/scam_detector.dart';
import '../services/api_service.dart';
import '../services/file_scanner_service.dart';
import '../data/models/scan_record.dart';
import '../data/repositories/scan_repository.dart';

class ScanScreen extends StatefulWidget {
  final String? initialText;
  final int initialTab;
  final bool autoPick;

  const ScanScreen({
    super.key,
    this.initialText,
    this.initialTab = 0,
    this.autoPick = false,
  });

  static final ValueNotifier<String?> pendingClipboardScan =
      ValueNotifier<String?>(null);

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  AnalysisResult? _result;
  bool _isAnalyzing = false;
  String _analyzingLabel = 'Analyzing with Gemini AI...';
  final ScanRepository _repo = ScanRepository();

  int _activeTab = 0; // 0=Message/SMS, 1=URL, 2=Voice, 3=Screenshot, 4=File, 5=APK Shortcut

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab.clamp(0, 4);
    _controller.addListener(() => setState(() {}));
    ScanScreen.pendingClipboardScan.addListener(_handlePendingClipboardScan);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialText != null && widget.initialText!.isNotEmpty) {
        _controller.text = widget.initialText!;
        _analyzeText();
      } else if (widget.autoPick) {
        if (_activeTab == 3) {
          _pickAndScanImage();
        } else if (_activeTab == 4) {
          _pickAndScanFile();
        }
      }
    });
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
      _activeTab =
          RegExp(r'https?://', caseSensitive: false).hasMatch(text) ? 1 : 0;
    });
    _analyzeText();
  }

  @override
  void dispose() {
    ScanScreen.pendingClipboardScan.removeListener(_handlePendingClipboardScan);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Scan entry points ─────────────────────────────────────────────────────

  Future<void> _analyzeText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      HapticFeedback.lightImpact();
      _showSnackBar('Please enter text or a link to analyze.', isError: true);
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _isAnalyzing = true;
      _result = null;
      _analyzingLabel = 'Analyzing threat intelligence...';
    });

    AnalysisResult result;
    try {
      result = await ApiService.analyzeMessage(text);
      if (!result.isAnalyzed) result = ScamDetector.analyze(text);
    } catch (_) {
      result = ScamDetector.analyze(text);
    }

    await _saveAndShow(result, text: text, source: _activeTab == 1 ? 'Link' : 'Message');
  }

  Future<void> _pickAndScanImage() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isAnalyzing = true;
      _result = null;
      _analyzingLabel = 'Running OCR & AI analysis on image...';
    });

    try {
      final scanResult = await FileScannerService.pickAndScanImage();
      if (scanResult == null) {
        setState(() => _isAnalyzing = false);
        return;
      }
      await _saveAndShow(
        scanResult.analysis,
        text: scanResult.rawContent,
        source: 'Screenshot',
        fileName: scanResult.fileName,
        errorMessage: scanResult.error,
      );
    } catch (e) {
      setState(() => _isAnalyzing = false);
      _showSnackBar('Image scan failed: $e', isError: true);
    }
  }

  Future<void> _pickAndScanFile() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isAnalyzing = true;
      _result = null;
      _analyzingLabel = 'Analyzing file content...';
    });

    try {
      final scanResult = await FileScannerService.pickAndScanFile();
      if (scanResult == null) {
        setState(() => _isAnalyzing = false);
        return;
      }
      await _saveAndShow(
        scanResult.analysis,
        text: scanResult.rawContent,
        source: 'File',
        fileName: scanResult.fileName,
        errorMessage: scanResult.error,
      );
    } catch (e) {
      setState(() => _isAnalyzing = false);
      _showSnackBar('File scan failed: $e', isError: true);
    }
  }

  Future<void> _saveAndShow(
    AnalysisResult result, {
    required String text,
    required String source,
    String? fileName,
    String? errorMessage,
  }) async {
    try {
      final record = ScanRecord.fromAnalysisResult(
        inputText: fileName != null ? 'File: $fileName\n$text' : text,
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
      if (errorMessage != null) {
        _showSnackBar(errorMessage, isError: false);
      }
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        backgroundColor: isError ? AppColors.danger : AppColors.cobalt,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isThreatResult = _result != null &&
        (_result!.classification.name.toLowerCase() == 'scam' ||
            _result!.classification.name.toLowerCase() == 'suspicious' ||
            _result!.riskScore > 40);

    return Scaffold(
      backgroundColor: isThreatResult ? AppColors.deepBackground : AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildAppBar(context),
              const SizedBox(height: 20),

              // Show Result view if scan completed
              if (_result != null && !_isAnalyzing) ...[
                _buildResultView(isThreatResult),
              ] else if (_isAnalyzing) ...[
                const SizedBox(height: 30),
                _buildAnalyzingWidget(),
              ] else ...[
                // Initial Discovery/Action view
                Reveal(
                  delay: Reveal.step(0),
                  child: Text(
                    "CHECK\nBEFORE\nYOU TRUST.",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: AppFontSizes.heroHeadline,
                      fontWeight: FontWeight.w900,
                      height: 1.02,
                      letterSpacing: -1.0,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Reveal(
                  delay: Reveal.step(1),
                  child: Text(
                    "Scan apps, links and messages before you open or install them.",
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Large floating action selection cards
                Reveal(
                  delay: Reveal.step(2),
                  child: _buildActionCards(context),
                ),
                const SizedBox(height: 24),

                // Selected Action Input Surface
                Reveal(
                  delay: Reveal.step(3),
                  child: _activeTab == 3
                      ? _buildPickerCard(
                          title: 'SCREENSHOT ANALYSIS',
                          subtitle: 'Pick a photo or screenshot to run OCR & threat check.',
                          buttonText: 'PICK IMAGE & SCAN',
                          icon: Icons.image_search_rounded,
                          onTap: _pickAndScanImage,
                        )
                      : _activeTab == 4
                          ? _buildPickerCard(
                              title: 'FILE & DOC SCAN',
                              subtitle: 'Pick any PDF, TXT, or document to detect scam patterns.',
                              buttonText: 'PICK FILE & SCAN',
                              icon: Icons.find_in_page_rounded,
                              onTap: _pickAndScanFile,
                            )
                          : _buildInputField(),
                ),
                const SizedBox(height: 20),

                // Primary Scan CTA
                if (_activeTab < 3)
                  Reveal(
                    delay: Reveal.step(4),
                    child: PremiumCTA(
                      label: "CHECK NOW →",
                      icon: Icons.shield_outlined,
                      onPressed: _analyzeText,
                    ),
                  ),
              ],
              const SizedBox(height: 90),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Threat Scanner',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        if (_result != null || _controller.text.isNotEmpty)
          GestureDetector(
            onTap: _clearAll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                'CLEAR',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.cobalt,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActionCards(BuildContext context) {
    return Column(
      children: [
        // Primary 3 Options
        Row(
          children: [
            Expanded(
              child: _buildFloatingOptionCard(
                index: 4, // APK Scan
                label: 'APK',
                sublabel: 'Android App',
                icon: Icons.android_rounded,
                isApkRoute: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFloatingOptionCard(
                index: 1, // LINK
                label: 'LINK',
                sublabel: 'URL Check',
                icon: Icons.link_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFloatingOptionCard(
                index: 0, // MESSAGE
                label: 'MESSAGE',
                sublabel: 'SMS / Text',
                icon: Icons.mark_chat_unread_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Secondary 2 Options
        Row(
          children: [
            Expanded(
              child: _buildFloatingOptionCard(
                index: 3, // Screenshot
                label: 'SCREENSHOT',
                sublabel: 'OCR Check',
                icon: Icons.image_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFloatingOptionCard(
                index: 4, // File
                label: 'DOCUMENT',
                sublabel: 'File Scan',
                icon: Icons.description_rounded,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFloatingOptionCard({
    required int index,
    required String label,
    required String sublabel,
    required IconData icon,
    bool isApkRoute = false,
  }) {
    final isSelected = !isApkRoute && _activeTab == index;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        if (isApkRoute) {
          context.go('/apk-scan');
        } else {
          setState(() {
            _activeTab = index;
            _result = null;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.cobalt.withValues(alpha: 0.18) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.cobalt : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.electricBlue : AppColors.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: AppColors.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField() {
    final hints = [
      'e.g. "URGENT: Your bank account is locked! Click bit.ly/fake-bank"',
      'e.g. "https://secure-login-verify.top/auth"',
      'Paste a voice note transcript or call details...',
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'INPUT DETAILS',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.mutedText,
                  letterSpacing: 1.0,
                ),
              ),
              GestureDetector(
                onTap: _pasteFromClipboard,
                child: Row(
                  children: [
                    const Icon(Icons.content_paste_rounded, color: AppColors.cobalt, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'PASTE',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.cobalt,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: 4,
            minLines: 3,
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: hints[_activeTab.clamp(0, 2)],
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickerCard({
    required String title,
    required String subtitle,
    required String buttonText,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.cobalt, size: 40),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),
          PremiumCTA(
            label: buttonText,
            onPressed: onTap,
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScamShieldHeroVisual(
            size: 200,
            isThreat: false,
            isSafe: true,
          ),
          const SizedBox(height: 24),
          Text(
            "WE'RE\nCHECKING IT.",
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.1,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _analyzingLabel,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ── Result View (Safe vs Dangerous Atmosphere) ────────────────────────────

  Widget _buildResultView(bool isThreat) {
    final r = _result!;
    final score = r.riskScore;
    final statusText = isThreat ? 'DANGEROUS' : (score > 0 ? 'SUSPICIOUS' : 'SAFE');

    return Column(
      children: [
        const SizedBox(height: 10),

        // AI / Heuristic Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: r.aiPowered
                ? AppColors.cobalt.withValues(alpha: 0.15)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: r.aiPowered
                  ? AppColors.cobalt.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                r.aiPowered ? Icons.auto_awesome : Icons.rule,
                size: 13,
                color: r.aiPowered ? AppColors.electricBlue : AppColors.mutedText,
              ),
              const SizedBox(width: 5),
              Text(
                r.aiPowered ? 'Gemini AI Analysis' : 'Heuristic Analysis',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: r.aiPowered ? AppColors.electricBlue : AppColors.mutedText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Central Shield & Dynamic Score
        ScamShieldHeroVisual(
          size: 200,
          isThreat: isThreat,
          isSafe: !isThreat,
        ),
        const SizedBox(height: 16),

        SecurityScore(
          score: score,
          statusLabel: statusText,
        ),
        const SizedBox(height: 20),

        // Headline & Message
        Text(
          isThreat
              ? 'This content shows signs of malicious behavior.'
              : 'This content appears safe.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isThreat ? AppColors.danger : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text(
            r.summary,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Evidence / Risk Indicators from actual analysis
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isThreat
                  ? AppColors.danger.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ANALYSIS FINDINGS',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.mutedText,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    '${r.reasons.length} signal(s)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.mutedText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (r.reasons.isEmpty) ...[
                _buildEvidenceRow('No threat signals detected in this content.', true, score: 0),
              ] else ...[
                ...r.reasons.map((reason) => _buildEvidenceRow(
                      reason.label,
                      reason.scoreContribution == 0,
                      description: reason.description,
                      score: reason.scoreContribution,
                    )),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Risk Score Breakdown (if has reasons)
        if (r.reasons.isNotEmpty && isThreat) ...
          [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bar_chart_rounded, color: AppColors.danger, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Risk Score: $score / 100  •  ${r.reasons.length} indicator(s) found',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

        // Action Buttons
        PremiumCTA(
          label: 'COPY FULL REPORT',
          isDanger: isThreat,
          icon: Icons.copy_rounded,
          onPressed: () {
            final details = r.reasons
                .map((reason) => '• ${reason.label}: ${reason.description}')
                .join('\n');
            final shareText =
                'ScamShield Security Report\n'
                'Classification: ${r.classification.name.toUpperCase()}\n'
                'Risk Score: ${r.riskScore}/100\n'
                'Analysis: ${r.aiPowered ? "Gemini AI" : "Heuristic"} Engine\n\n'
                'Summary: ${r.summary}\n\n'
                'Indicators:\n$details';
            Clipboard.setData(ClipboardData(text: shareText));
            _showSnackBar('Full security report copied to clipboard.', isError: false);
          },
        ),
        const SizedBox(height: 12),
        PremiumCTA(
          label: 'RUN NEW SCAN',
          isSecondary: true,
          onPressed: _clearAll,
        ),
      ],
    );
  }

  Widget _buildEvidenceRow(
    String text,
    bool isSafe, {
    String? description,
    int score = 0,
  }) {
    final color = isSafe ? AppColors.safeEmerald : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Icon(
              isSafe ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              color: color,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        text,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (!isSafe && score > 0) ...
                      [
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '+$score',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                  ],
                ),
                if (description != null && description.isNotEmpty) ...
                  [
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}