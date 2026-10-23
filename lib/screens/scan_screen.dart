import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../widgets/ui_kit.dart';
import '../services/osint_service.dart';
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
import 'qr_result_screen.dart';
import 'upi_verify_screen.dart';
import 'apk_scan_screen.dart';
import 'breach_screen.dart';
import 'cybercrime_screen.dart';
import 'sim_lock_screen.dart';
import '../widgets/scan_now_bottom_sheet.dart';

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

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
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
    super.dispose();
  }

  void _onSharedContent() {
    final request = ShareIntentService.pending.value;
    if (request == null) return;
    ShareIntentService.consume();

    switch (request.kind) {
      case SharedScanKind.text:
        final isLink =
            request.value.startsWith('http://') ||
            request.value.startsWith('https://');
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

  Future<void> _analyzeSharedImage(String path) =>
      _analyzeAttachment(File(path), isVoice: false, source: 'Shared Image');

  /// Audio files the server's Whisper step accepts, and the limits it enforces
  /// (MAX_AUDIO_SIZE_MB / MAX_IMAGE_SIZE_MB). Checked here so a too-large file
  /// is refused instantly instead of after a long upload.
  static const int _maxAudioBytes = 25 * 1024 * 1024;
  static const int _maxImageBytes = 10 * 1024 * 1024;

  String? _attachedName;

  /// Voice and image scans used to be a text box with a different placeholder:
  /// there was no way to attach the actual voice note or screenshot, although
  /// the analysis code behind them existed.
  Future<void> _pickVoiceNote() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    final file = picked?.files.single;
    if (file == null || file.path == null) return;
    if (file.size > _maxAudioBytes) {
      _showSnackBar(
        'That file is over 25 MB. Choose a shorter voice note.',
        isError: true,
      );
      return;
    }
    await _analyzeAttachment(File(file.path!), isVoice: true, name: file.name);
  }

  Future<void> _pickImage(ImageSource from) async {
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: from, imageQuality: 92);
    } catch (e) {
      _showSnackBar(
        from == ImageSource.camera
            ? 'Could not open the camera. Check the camera permission in Settings.'
            : 'Could not open your photos. Check the permission in Settings.',
        isError: true,
      );
      return;
    }
    if (picked == null) return;
    final size = await picked.length();
    if (size > _maxImageBytes) {
      _showSnackBar(
        'That image is over 10 MB. Choose a smaller one.',
        isError: true,
      );
      return;
    }
    await _analyzeAttachment(
      File(picked.path),
      isVoice: false,
      name: picked.name,
    );
  }

  Future<void> _pickImageFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final file = picked?.files.single;
    if (file == null || file.path == null) return;
    if (file.size > _maxImageBytes) {
      _showSnackBar(
        'That image is over 10 MB. Choose a smaller one.',
        isError: true,
      );
      return;
    }
    await _analyzeAttachment(File(file.path!), isVoice: false, name: file.name);
  }

  Future<void> _analyzeAttachment(
    File file, {
    required bool isVoice,
    String? name,
    String? source,
  }) async {
    final label = name ?? file.path.split('/').last;
    setState(() {
      _isAnalyzing = true;
      _result = null;
      _attachedName = label;
    });

    final result = isVoice
        ? await ApiService.analyzeVoice(file)
        : await ApiService.analyzeImage(file);

    // A failed upload says nothing about the file, so don't file it in
    // history as if it had been checked.
    final failed =
        result.reasons.isNotEmpty &&
        (result.reasons.first.label == 'Voice Note Scan Failed' ||
            result.reasons.first.label == 'Image Scan Failed' ||
            result.reasons.first.label == 'Analysis Unavailable');
    if (!failed) {
      try {
        final record = ScanRecord.fromAnalysisResult(
          inputText: '${isVoice ? 'Voice note' : 'Image'}: $label',
          result: result,
          source: source ?? (isVoice ? 'Voice Note' : 'Image'),
        );
        await _repo.saveScan(record);
      } catch (_) {}
      _maybeAlertFamily(result);
    }

    if (mounted) {
      setState(() {
        _result = result;
        _isAnalyzing = false;
        // An attachment has no reportable URL of its own — clear any leftover
        // community-report state from a previous text/link scan.
        _reportableUrl = null;
        _reputation = null;
        _reportSubmitted = false;
        // The transcript / OCR text isn't surfaced here, so there is nothing
        // stable to hash: feedback is offered on text and link scans only.
        _analyzedText = null;
        _feedbackGiven = null;
      });
      if (failed) {
        _showSnackBar(
          'Could not analyse the ${isVoice ? 'voice note' : 'image'}. It needs the '
          'ScamShield server: set it up in Profile > Server address.',
          isError: true,
        );
      }
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
      if (result.riskScore == 0 &&
          !result.aiPowered &&
          (result.reasons.isEmpty ||
              result.reasons.first.label == 'Analysis Unavailable')) {
        result = ScamDetector.analyze(text);
      }
    } catch (_) {
      result = ScamDetector.analyze(text);
    }

    result = await _withThreatIntel(text, result);

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

  /// The text analysis only reads the wording, so a known-malicious link with
  /// calm wording came back SAFE. Every link in the message is also checked
  /// with Google Safe Browsing and VirusTotal (through the server); a hit makes
  /// the verdict a scam whatever the wording says.
  Future<AnalysisResult> _withThreatIntel(
    String text,
    AnalysisResult result,
  ) async {
    try {
      final urls = RegExp(r'https?://[^\s]+', caseSensitive: false)
          .allMatches(text)
          .map((m) => m.group(0)!.replaceAll(RegExp(r'[).,;!?]+$'), ''))
          .toSet()
          .take(5)
          .toList();
      if (urls.isEmpty) return result;
      final checks = await OsintService.checkUrlsGoogleSafeBrowsing(urls);
      final flagged = checks.where((c) => c.isMalicious).toList();
      if (flagged.isEmpty) return result;
      final providers = flagged.map((c) => c.provider).toSet().join(' and ');
      return AnalysisResult(
        classification: ScamClassification.scam,
        riskScore: result.riskScore < 95 ? 95 : result.riskScore,
        aiPowered: result.aiPowered,
        summary:
            'A link in this message is flagged as dangerous by $providers. '
            'Do not open it.',
        reasons: [
          for (final c in flagged)
            DetectionReason(
              label: 'Flagged by ${c.provider}',
              description: c.details,
              scoreContribution: 60,
              iconCategory: IconCategory.link,
            ),
          ...result.reasons,
        ],
      );
    } catch (_) {
      return result;
    }
  }

  /// Relays a dangerous verdict to the user's family group, if they're in one.
  ///
  /// Fire-and-forget on purpose: a relative's phone being unreachable must
  /// never delay or fail the scan the user is standing there waiting for. Only
  /// the verdict and summary go out — never the message itself.
  void _maybeAlertFamily(AnalysisResult result) {
    final isDangerous =
        result.classification == ScamClassification.scam ||
        (result.classification == ScamClassification.suspicious &&
            result.riskScore >= 60);
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
    final looksLikeUrl =
        _activeTab == 1 ||
        text.startsWith('http://') ||
        text.startsWith('https://');
    if (!looksLikeUrl) return;

    final url = text;
    setState(() => _reportableUrl = url);
    CommunityReportService.checkReputation(
      type: IndicatorType.url,
      value: url,
    ).then((result) {
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
      ok
          ? 'Thanks — reported to help protect other users.'
          : 'Could not submit the report. Check your connection.',
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
    final decoded = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
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

    // Show what the code actually holds (the real address, who owns it, and
    // the tricks used to disguise bad ones) BEFORE anything is analysed or
    // opened. A verdict alone doesn't tell someone where they'd be sent.
    final action = await Navigator.of(context).push<QrAction>(
      MaterialPageRoute(builder: (_) => QrResultScreen(raw: decoded)),
    );
    if (!mounted || action != QrAction.analyze) return;

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
        title: Text(
          LocalizationService.tr('scan_title'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: false,
        actions: [
          if (_result != null || _controller.text.isNotEmpty)
            TextButton.icon(
              onPressed: _clearAll,
              icon: const Icon(
                Icons.refresh,
                color: AppColors.primary,
                size: 16,
              ),
              label: Text(
                LocalizationService.tr('scan_clear'),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
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
            if (_result != null && !_isAnalyzing)
              Reveal(child: _buildResultCard()),
            if (_result != null && !_isAnalyzing && _analyzedText != null) ...[
              const SizedBox(height: 12),
              Reveal(child: _buildFeedbackSection()),
            ],
            if (_result != null && !_isAnalyzing && _reportableUrl != null) ...[
              const SizedBox(height: 12),
              Reveal(child: _buildCommunitySection()),
            ],
            if (_result == null && !_isAnalyzing) ...[
              Reveal(delay: Reveal.step(3), child: _buildMoreScans()),
              const SizedBox(height: 20),
              Reveal(delay: Reveal.step(4), child: _buildSamplePrompts()),
            ],
          ],
        ),
      ),
    );
  }

  /// A slim segmented control.
  ///
  /// This was a 2×2 block of four full-width tabs with ALL-CAPS labels, which
  /// ate about a fifth of the screen before the user could type anything. Four
  /// short segments on one row say the same thing in a quarter of the space.
  Widget _buildTabHeader() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              0,
              'Text',
              Icons.chat_bubble_outline_rounded,
            ),
          ),
          Expanded(child: _buildTabButton(1, 'Link', Icons.link_rounded)),
          Expanded(child: _buildTabButton(2, 'Voice', Icons.mic_none_rounded)),
          Expanded(child: _buildTabButton(3, 'Image', Icons.image_outlined)),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSel = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isSel ? AppColors.surfaceLight : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSel ? AppColors.primary : AppColors.textSecondary,
              size: 18,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isSel ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The input.
  ///
  /// The ALL-CAPS "PASTE SUSPICIOUS TEXT" header above the field is gone — the
  /// placeholder already says what to do, and a label that repeats the
  /// placeholder is just noise above the thing you were going to tap anyway.
  /// Paste and Scan-QR became icon buttons on one quiet row underneath.
  Widget _buildInputField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: 6,
            minLines: 4,
            style: AppText.body,
            decoration: InputDecoration(
              hintText: _activeTab == 0
                  ? LocalizationService.tr('scan_hint')
                  : _activeTab == 1
                  ? 'Paste the link here'
                  : _activeTab == 2
                  ? 'Attach a voice note below, or paste what the caller said'
                  : 'Attach a screenshot or photo below, or paste its text',
              hintStyle: AppText.bodyMuted,
              filled: false,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: AppSpacing.sm,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
          if (_attachedName != null && (_activeTab == 2 || _activeTab == 3))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(
                    _activeTab == 2
                        ? Icons.graphic_eq_rounded
                        : Icons.image_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _attachedName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption,
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _attachedName = null),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 14),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Row(
            children: [
              _inputAction(
                Icons.content_paste_rounded,
                'Paste',
                _pasteFromClipboard,
              ),
              _inputAction(
                Icons.qr_code_scanner_rounded,
                'Scan QR',
                _scanQrCode,
              ),
              if (_activeTab == 2)
                _inputAction(
                  Icons.attach_file_rounded,
                  'Attach voice note',
                  _pickVoiceNote,
                ),
              if (_activeTab == 3) ...[
                _inputAction(
                  Icons.photo_library_outlined,
                  'Gallery',
                  () => _pickImage(ImageSource.gallery),
                ),
                _inputAction(
                  Icons.photo_camera_outlined,
                  'Camera',
                  () => _pickImage(ImageSource.camera),
                ),
                _inputAction(
                  Icons.folder_open_outlined,
                  'Files',
                  _pickImageFile,
                ),
              ],
              const Spacer(),
              if (_controller.text.isNotEmpty)
                Text(
                  '${_controller.text.trim().length}',
                  style: AppText.caption,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inputAction(IconData icon, String label, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: AppColors.primary),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// One primary action, in plain words.
  ///
  /// Was a gradient-filled "ANALYZE FOR THREATS". The gradient is gone (the
  /// theme's flat primary is enough to mark the one thing on screen you press)
  /// and so is the jargon — "check" is what a person would call this.
  Widget _buildActionButton() {
    final hasText = _controller.text.trim().isNotEmpty;
    return ElevatedButton.icon(
      onPressed: _isAnalyzing
          ? null
          : hasText
          ? _analyze
          : () => _showSnackBar(
              'Paste or type a message, link or number first, or attach a '
              'file.',
              isError: false,
            ),
      icon: const Icon(Icons.shield_outlined, size: 20),
      label: Text(LocalizationService.tr('scan_button')),
    );
  }

  /// The waiting state.
  ///
  /// Was a pulsing 48px brain icon over "Analyzing with Gemini AI…". Two
  /// problems: the animation added drama to a moment that is already tense,
  /// and the copy named a provider that may not even be the one running —
  /// analysis falls back to Groq or to the on-device engine, and says so
  /// honestly now.
  Widget _buildAnalyzingWidget() {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxl,
        horizontal: AppSpacing.lg,
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(LocalizationService.tr('scan_analyzing'), style: AppText.body),
        ],
      ),
    );
  }

  /// The verdict — the single most important thing this app ever renders.
  ///
  /// What changed: the answer now leads with what to *do*, not what was
  /// measured. The old card opened with a coloured word, a "GEMINI AI" badge
  /// and "Risk Score: 87/100" — a measurement, a vendor name, and a number
  /// nobody can act on, all above the advice. Someone reading this is often
  /// mid-decision about whether to tap a link or send money; the instruction
  /// belongs at the top and the diagnostics belong below it.
  ///
  /// The verdict's colour, icon and wording come from the shared kit
  /// (verdictStyleFor), so this card, History, Home and Simple Mode cannot
  /// describe the same result differently.
  Widget _buildResultCard() {
    final r = _result!;
    final v = verdictStyleFor(r.classification.name);

    return AppCard(
      tone: v.color,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(v.icon, color: v.color, size: 30),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  // Translated, not the enum name upcased: this is the one
                  // line the user has to understand.
                  LocalizationService.tr('verdict_${r.classification.name}'),
                  style: AppText.title.copyWith(color: v.color),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // The instruction. Plain, imperative, and above the detail.
          Text(v.advice, style: AppText.body),
          const SizedBox(height: AppSpacing.lg),
          Container(height: 1, color: AppColors.surfaceLight),
          const SizedBox(height: AppSpacing.lg),
          Text(LocalizationService.tr('scan_summary'), style: AppText.label),
          const SizedBox(height: AppSpacing.xs),
          Text(r.summary, style: AppText.secondary),
          if (r.reasons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(LocalizationService.tr('scan_factors'), style: AppText.label),
            const SizedBox(height: AppSpacing.sm),
            ...r.reasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A small dot, not a warning triangle per row. Ten
                    // triangles below a verdict the user has already read
                    // adds alarm without adding information.
                    Container(
                      margin: const EdgeInsets.only(top: 7),
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reason.label,
                            style: AppText.body.copyWith(fontSize: 14),
                          ),
                          Text(reason.description, style: AppText.secondary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // Score and provenance, kept but demoted to a footnote — useful to
          // the curious, irrelevant to the decision.
          Text(
            '${LocalizationService.tr('scan_risk_score')} ${r.riskScore}/100'
            '${r.aiPowered ? ' · AI-assisted' : ' · on-device check'}',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }

  Future<void> _submitFeedback(VerdictAgreement agreement) async {
    final text = _analyzedText;
    final result = _result;
    if (text == null || result == null || _feedbackSending) return;

    setState(() => _feedbackSending = true);
    final outcome = await VerdictFeedbackService.submit(
      text: text,
      classification: result.classification.name,
      riskScore: result.riskScore,
      agreement: agreement,
    );
    if (!mounted) return;

    setState(() {
      _feedbackSending = false;
      // Claim it only if it was actually recorded, here or on the server.
      _feedbackGiven = outcome == FeedbackOutcome.notRecorded
          ? null
          : agreement;
    });

    if (outcome == FeedbackOutcome.notRecorded) {
      _showSnackBar(
        "Couldn't record that: consent for sending feedback isn't on file.",
        isError: true,
      );
      return;
    }

    if (agreement == VerdictAgreement.missed) {
      // "It was a scam" is not just a data point. This person may have lost
      // money or be about to, so put the next step right there.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          behavior: SnackBarBehavior.floating,
          content: Text(
            outcome == FeedbackOutcome.sent
                ? 'Thanks. If you lost money or shared details, report it now.'
                : 'Saved on this device. If you lost money or shared details, report it now.',
          ),
          action: SnackBarAction(
            label: 'REPORT',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CybercrimeScreen(
                  record: ScanRecord.fromAnalysisResult(
                    inputText: text,
                    result: result,
                    source: 'Manual',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } else if (outcome == FeedbackOutcome.savedOnDevice) {
      _showSnackBar(
        'Saved on this device. It will be sent when the server is reachable.',
        isError: false,
      );
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
        border: Border.all(
          color: AppColors.surfaceLight.withValues(alpha: 0.5),
        ),
      ),
      child: _feedbackGiven != null
          ? Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: AppColors.success,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    LocalizationService.tr('feedback_thanks'),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocalizationService.tr('feedback_prompt'),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  LocalizationService.tr('feedback_privacy'),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.4,
                  ),
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
                              label: LocalizationService.tr(
                                'feedback_was_scam',
                              ),
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
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
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
        border: Border.all(
          color: AppColors.surfaceLight.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.groups_outlined,
                color: AppColors.textSecondary,
                size: 16,
              ),
              SizedBox(width: 8),
              Text(
                'Community reports',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (reputation == null)
            const Text(
              'Checking community reports...',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else if (!reputation.checked)
            const Text(
              'Could not reach the community database right now.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else if (reputation.reported)
            Text(
              'Flagged by ${reputation.reportCount} user(s) as a scam${reputation.category != null ? " (${reputation.category})" : ""}.',
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            )
          else if (reputation.reportCount > 0)
            Text(
              'Reported ${reputation.reportCount} time(s) — not yet enough reports to confirm.',
              style: const TextStyle(color: AppColors.warning, fontSize: 12),
            )
          else
            const Text(
              'No prior reports for this link.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_reportSubmitting || _reportSubmitted)
                  ? null
                  : _reportCurrentUrlAsScam,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: Icon(
                _reportSubmitted
                    ? Icons.check_circle_outline
                    : Icons.flag_outlined,
                color: AppColors.danger,
                size: 16,
              ),
              label: Text(
                _reportSubmitted
                    ? 'Reported — thank you'
                    : 'Report this link as a scam',
                style: const TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Every other kind of check the app can do, one tap from the Scan tab.
  /// They used to be spread over Home, a bottom sheet and the Breach tab, so
  /// people on this screen never found the APK scanner or the email check.
  Widget _buildMoreScans() {
    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    final scans = <(IconData, String, String, VoidCallback)>[
      (
        Icons.android_rounded,
        'App (APK)',
        'Permissions, YARA, VirusTotal',
        () => open(const ApkScanScreen()),
      ),
      (
        Icons.qr_code_scanner,
        'QR or UPI code',
        'Where it leads, who gets paid',
        _scanQrCode,
      ),
      (
        Icons.folder_open_rounded,
        'File or clipboard',
        'Documents, screenshots, copied text',
        () => ScanNowBottomSheet.show(context),
      ),
      (
        Icons.alternate_email,
        'Email leak',
        'Was my email in a breach?',
        () => open(const BreachScreen()),
      ),
      (
        Icons.phonelink_lock_outlined,
        'Device check',
        'Root status and SIM safety',
        () => open(const SimLockScreen()),
      ),
      (
        Icons.local_police_outlined,
        'Report a scam',
        'Call 1930, evidence PDF',
        () => open(const CybercrimeScreen()),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('More ways to check', style: AppText.label),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.3,
          children: [
            for (final (icon, title, subtitle, onTap) in scans)
              Pressable(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.surfaceLight.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: AppColors.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.textSecondary,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
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
        Text('Try an example', style: AppText.label),
        const SizedBox(height: 10),
        ...samples.asMap().entries.map(
          (entry) => Reveal(
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
                    border: Border.all(
                      color: AppColors.surfaceLight.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.touch_app_outlined,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
