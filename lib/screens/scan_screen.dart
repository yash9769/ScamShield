import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/scam_detector.dart';

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

  // Tab selection: 0 = Paste Content, 1 = Verify Link
  int _activeTab = 0;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Core Actions ──────────────────────────────────────────────────────────

  Future<void> _analyze() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _showSnackBar('Please enter some content to analyze.', isError: true);
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _result = null;
    });

    // Simulate a short processing delay for realism
    await Future.delayed(const Duration(milliseconds: 1800));

    final result = ScamDetector.analyze(text);
    if (mounted) {
      setState(() {
        _result = result;
        _isAnalyzing = false;
      });
    }
  }

  void _clearAll() {
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Threat Scanner',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          if (_result != null || _controller.text.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: const Text(
                'CLEAR',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildTabs(),
            const SizedBox(height: 20),
            _buildInputSection(),
            const SizedBox(height: 20),
            _buildAnalyzeButton(),
            if (_isAnalyzing) ...[
              const SizedBox(height: 32),
              _buildScanningAnimation(),
            ],
            if (_result != null && !_isAnalyzing) ...[
              const SizedBox(height: 32),
              _buildResultCard(),
              const SizedBox(height: 20),
              _buildReasonsSection(),
            ],
            if (_result == null && !_isAnalyzing) ...[
              const SizedBox(height: 28),
              _buildInfoCards(),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Text(
          'Paste content, a text message, or a suspicious link to verify its security through our neural analysis engine.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
      ],
    );
  }

  // ── Tab Switcher ──────────────────────────────────────────────────────────

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _buildTab('Paste Content', 0, Icons.content_paste_rounded),
          _buildTab('Verify Link', 1, Icons.link),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index, IconData icon) {
    final isActive = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeTab = index;
            _controller.clear();
            _result = null;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                  )
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive ? Colors.black : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.black : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Input Section ─────────────────────────────────────────────────────────

  Widget _buildInputSection() {
    final isLink = _activeTab == 1;
    final charCount = _controller.text.length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _focusNode.hasFocus
              ? AppColors.primary.withValues(alpha: 0.4)
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              isLink ? 'SUSPICIOUS LINK' : 'SUSPICIOUS CONTENT',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
          ),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: isLink ? 2 : 7,
            keyboardType: isLink ? TextInputType.url : TextInputType.multiline,
            style: const TextStyle(fontSize: 14, height: 1.6),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.all(16),
              hintText: isLink
                  ? 'Paste a suspicious URL or link here...'
                  : 'Paste the suspicious email, SMS, or message here...',
              border: InputBorder.none,
              hintStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(18),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isLink
                      ? '$charCount characters'
                      : '$charCount / 5000 characters',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                GestureDetector(
                  onTap: _pasteFromClipboard,
                  child: const Row(
                    children: [
                      Icon(
                        Icons.paste_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Paste from Clipboard',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Analyze Button ────────────────────────────────────────────────────────

  Widget _buildAnalyzeButton() {
    final hasContent = _controller.text.trim().isNotEmpty;
    return AnimatedOpacity(
      opacity: hasContent ? 1.0 : 0.5,
      duration: const Duration(milliseconds: 200),
      child: Container(
        width: double.infinity,
        height: 58,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.accent],
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: hasContent
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [],
        ),
        child: ElevatedButton.icon(
          onPressed: hasContent ? _analyze : null,
          icon: const Icon(Icons.radar_rounded, color: Colors.white),
          label: const Text(
            'Analyze Content',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ),
      ),
    );
  }

  // ── Scanning Animation ────────────────────────────────────────────────────

  Widget _buildScanningAnimation() {
    return Center(
      child: Column(
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: const Icon(
                Icons.radar_rounded,
                color: AppColors.primary,
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Analyzing content...',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Running local pattern analysis...',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Result Card ───────────────────────────────────────────────────────────

  Widget _buildResultCard() {
    final result = _result!;
    final Color primaryColor;
    final Color bgColor;
    final IconData statusIcon;
    final String statusLabel;
    final String statusSubtitle;

    switch (result.classification) {
      case ScamClassification.scam:
        primaryColor = AppColors.danger;
        bgColor = AppColors.danger.withValues(alpha: 0.08);
        statusIcon = Icons.warning_rounded;
        statusLabel = 'SCAM DETECTED';
        statusSubtitle = 'High confidence threat identified';
      case ScamClassification.suspicious:
        primaryColor = AppColors.warning;
        bgColor = AppColors.warning.withValues(alpha: 0.08);
        statusIcon = Icons.help_outline_rounded;
        statusLabel = 'SUSPICIOUS';
        statusSubtitle = 'Multiple warning signals found';
      case ScamClassification.safe:
        primaryColor = AppColors.success;
        bgColor = AppColors.success.withValues(alpha: 0.08);
        statusIcon = Icons.check_circle_outline_rounded;
        statusLabel = 'LOOKS SAFE';
        statusSubtitle = 'No critical threats detected';
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: Container(
        key: ValueKey(result.riskScore),
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: primaryColor.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          children: [
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, color: primaryColor, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Risk score ring
            _buildRiskScoreRing(result.riskScore, primaryColor),
            const SizedBox(height: 24),
            Text(
              statusSubtitle,
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              result.summary,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskScoreRing(int score, Color color) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 130,
          height: 130,
          child: CircularProgressIndicator(
            value: score / 100,
            strokeWidth: 10,
            backgroundColor: color.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            strokeCap: StrokeCap.round,
          ),
        ),
        Column(
          children: [
            Text(
              '$score',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const Text(
              'RISK SCORE',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Reasons Section ───────────────────────────────────────────────────────

  Widget _buildReasonsSection() {
    final result = _result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Detection Breakdown',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Why we flagged this content',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        ...result.reasons.map((reason) => _buildReasonCard(reason)),
      ],
    );
  }

  Widget _buildReasonCard(DetectionReason reason) {
    final (Color color, IconData icon) = _iconForCategory(reason.iconCategory);
    final contribution = reason.scoreContribution;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  reason.label,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              if (contribution > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '+$contribution pts',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            reason.description,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (contribution > 0) ...[
            const SizedBox(height: 12),
            _buildContributionBar(contribution, color),
          ],
        ],
      ),
    );
  }

  Widget _buildContributionBar(int contribution, Color color) {
    final fraction = (contribution / 35).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Risk Contribution',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
            ),
            Text(
              '${(fraction * 100).toInt()}%',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            backgroundColor: color.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 5,
          ),
        ),
      ],
    );
  }

  (Color, IconData) _iconForCategory(IconCategory category) {
    return switch (category) {
      IconCategory.financial => (AppColors.danger, Icons.account_balance_rounded),
      IconCategory.link => (AppColors.warning, Icons.link_rounded),
      IconCategory.urgency => (AppColors.warning, Icons.timer_rounded),
      IconCategory.suspicious => (AppColors.warning, Icons.search_rounded),
      IconCategory.manipulation => (AppColors.danger, Icons.psychology_rounded),
      IconCategory.safe => (AppColors.success, Icons.check_circle_rounded),
    };
  }

  // ── Info Cards (shown before any analysis) ────────────────────────────────

  Widget _buildInfoCards() {
    return Column(
      children: [
        _buildInfoCard(
          Icons.verified_user_outlined,
          'Privacy First',
          'All analysis runs locally on your device. We never transmit or store your sensitive content.',
          AppColors.accent,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          Icons.psychology_outlined,
          'Pattern Intelligence',
          'Our engine detects financial lures, urgency tactics, shortened links, OTP requests, and psychological manipulation.',
          AppColors.primary,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          Icons.bar_chart_rounded,
          'Explainable Results',
          'Every scan shows a detailed breakdown so you understand exactly why content was flagged.',
          AppColors.success,
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    IconData icon,
    String title,
    String description,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
