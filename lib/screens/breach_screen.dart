import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../services/breach_service.dart';
import '../services/breach_watch_service.dart';

class BreachScreen extends StatefulWidget {
  final int initialIndex;

  const BreachScreen({super.key, this.initialIndex = 0});

  @override
  State<BreachScreen> createState() => _BreachScreenState();
}

class _BreachScreenState extends State<BreachScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<BreachInfo> _breaches = [];
  bool _isLoading = true;
  String _error = '';

  BreachStats? _stats;

  final TextEditingController _emailController = TextEditingController();
  BreachCheckResult? _emailResult;
  bool _isCheckingEmail = false;
  String _emailError = '';
  String _checkedEmail = '';
  String _checkStatus = 'idle';
  bool _isWatched = false;
  bool _togglingWatch = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 1),
    );
    _loadBreaches();
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadBreaches() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final breaches = await BreachService.getRecentBreaches(limit: 30);
      if (mounted) {
        setState(() {
          _breaches = breaches;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Failed to fetch breach feed. Check connection.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadStats() async {
    try {
      final stats = await BreachService.getBreachStats();
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
      // Stats are non-critical; the hero simply shows placeholders on failure.
    }
  }

  Future<void> _checkEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _emailError = 'Please enter a valid email address.';
        _checkStatus = 'invalid_input';
      });
      return;
    }

    setState(() {
      _isCheckingEmail = true;
      _emailError = '';
      _emailResult = null;
      _checkedEmail = email;
      _checkStatus = 'loading';
    });

    try {
      final result = await BreachService.checkEmailBreach(email);
      final watched = await BreachWatchService.isWatched(email);
      if (mounted) {
        setState(() {
          _isCheckingEmail = false;
          _emailResult = result;
          _isWatched = watched;
          _checkStatus = result.exposed ? 'success_exposed' : 'success_no_exposure';
        });
      }
    } on BreachCheckException catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingEmail = false;
          _checkStatus = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCheckingEmail = false;
          _checkStatus = 'api_error';
        });
      }
    }
  }

  String _formatCheckedAt(String? checkedAt) {
    if (checkedAt == null || checkedAt.length < 10) return 'recent';
    return checkedAt.substring(0, 10);
  }

  Future<void> _toggleWatch() async {
    final result = _emailResult;
    if (result == null || _togglingWatch) return;

    setState(() => _togglingWatch = true);

    String message;
    if (_isWatched) {
      await BreachWatchService.unwatch(_checkedEmail);
      message = 'Stopped watching $_checkedEmail.';
      if (mounted) setState(() => _isWatched = false);
    } else {
      // Seed with the count we just measured, so the existing exposures are
      // the baseline and only genuinely new ones raise an alert later.
      final added = await BreachWatchService.watch(_checkedEmail, result.breachCount);
      message = added
          ? 'Watching $_checkedEmail. We\'ll re-check when you open the app.'
          : 'You can watch up to ${BreachWatchService.maxWatched} addresses. Remove one first.';
      if (mounted) setState(() => _isWatched = added);
    }

    if (!mounted) return;
    setState(() => _togglingWatch = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceLight,
      ),
    );
  }

  Widget _buildWatchToggle() {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isWatched
              ? AppColors.primary.withValues(alpha: 0.5)
              : AppColors.surfaceLight.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isWatched ? Icons.notifications_active : Icons.notifications_none,
            color: _isWatched ? AppColors.primary : AppColors.textSecondary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isWatched ? 'Watching this address' : 'Watch this address',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isWatched
                      ? 'You\'ll be alerted if it turns up in a new breach.'
                      : 'A breach check only reflects today. Watch it and we\'ll re-check on app open.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _togglingWatch
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              : Switch(
                  value: _isWatched,
                  activeThumbColor: AppColors.primary,
                  onChanged: (_) => _toggleWatch(),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Breach Intelligence', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.mark_email_read_outlined), text: 'Email Breach Check'),
            Tab(icon: Icon(Icons.public_outlined), text: 'Recent Breaches'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEmailCheck(),
          _buildBreachList(),
        ],
      ),
    );
  }

  Widget _buildBreachList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, color: AppColors.textSecondary, size: 48),
              const SizedBox(height: 16),
              Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadBreaches,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Retry Feed', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBreaches,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _breaches.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) return _buildBreachHeader();
          return Reveal(
            delay: Reveal.step(i, stepMs: 45, baseMs: 0),
            offsetY: 16,
            child: _buildBreachCard(_breaches[i - 1]),
          );
        },
      ),
    );
  }

  Widget _buildBreachHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_breaches.length} Global Security Incidents', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  const Text('Live feed of verified security breaches and leaked databases.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreachCard(BreachInfo breach) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  'https://www.google.com/s2/favicons?domain=${breach.domain}&sz=32',
                  width: 32,
                  height: 32,
                  errorBuilder: (_, _, _) => Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.security, color: AppColors.danger, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(breach.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(breach.domain, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '${(breach.pwnCount / 1000).toStringAsFixed(0)}K LEAKED',
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(breach.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildEmailCheck() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Reveal(delay: Reveal.step(0), child: _buildScaleHero()),
          const SizedBox(height: 20),
          Reveal(
            delay: Reveal.step(1),
            child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CHECK EMAIL ADDRESS FOR BREACHES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1)),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'user@example.com',
                    prefixIcon: Icon(Icons.email_outlined, color: AppColors.primary),
                  ),
                ),
                if (_emailError.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_emailError, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isCheckingEmail ? null : _checkEmail,
                    icon: _isCheckingEmail
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.search, color: Colors.black),
                    label: Text(_isCheckingEmail ? 'CHECKING DATABASE...' : 'CHECK EMAIL BREACH STATUS', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          ),
          const SizedBox(height: 20),
          if (_checkStatus != 'idle') Reveal(child: _buildEmailResultWidget()),
          // Only offer the standing watch once a check actually succeeded —
          // there's no baseline count to seed it with otherwise.
          if (_emailResult != null &&
              (_checkStatus == 'success_exposed' || _checkStatus == 'success_no_exposure'))
            Reveal(child: _buildWatchToggle()),
          const SizedBox(height: 24),
          Reveal(delay: Reveal.step(2), child: _buildWhatToDoSection()),
        ],
      ),
    );
  }

  static const Color _purple = Color(0xFF8B5CF6);

  Widget _buildScaleHero() {
    final stats = _stats;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [AppColors.primary, AppColors.accent],
            ).createShader(bounds),
            child: const Text(
              'The Scale of the Problem',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Our data breach intelligence indexes real exposed records from real data breaches. Are you in them?',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _buildStatCard(Icons.shield_rounded, AppColors.danger, stats == null ? '—' : '${stats.totalBreaches}', 'DATA BREACHES')),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(Icons.storage_rounded, AppColors.accent, stats == null ? '—' : BreachStats.format(stats.exposedRecords), 'EXPOSED RECORDS')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard(Icons.email_rounded, _purple, stats == null ? '—' : BreachStats.format(stats.exposedEmails), 'EXPOSED EMAILS')),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(Icons.key_rounded, AppColors.success, stats == null ? '—' : BreachStats.format(stats.exposedPasswords), 'EXPOSED PASSWORDS')),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            "The question isn't if you've been breached — it's how many times.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4),
          ),
          if (stats != null && stats.latestBreachDate.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Latest breach added: ${stats.latestBreachDatePretty}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, Color color, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildWhatToDoSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 12),
          const Text('What Should You Do?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Reveal(
            delay: Reveal.step(0, baseMs: 100),
            offsetY: 14,
            child: _buildRecommendationCard(
              Icons.shield_rounded, AppColors.warning, 'HIGH PRIORITY',
              'Enable Two-Factor Authentication',
              'Add 2FA on all supported accounts using an authenticator app like Google Authenticator or Authy.',
            ),
          ),
          const SizedBox(height: 12),
          Reveal(
            delay: Reveal.step(1, baseMs: 100),
            offsetY: 14,
            child: _buildRecommendationCard(
              Icons.phone_in_talk_rounded, AppColors.primary, 'RECOMMENDED',
              'Watch for Phishing Calls & SMS',
              'Be cautious of unexpected calls or texts asking for personal information.',
            ),
          ),
          const SizedBox(height: 12),
          Reveal(
            delay: Reveal.step(2, baseMs: 100),
            offsetY: 14,
            child: _buildRecommendationCard(
              Icons.mark_email_unread_rounded, AppColors.primary, 'RECOMMENDED',
              'Beware of Scam Mail',
              'Be skeptical of unexpected correspondence requesting personal details.',
            ),
          ),
          const SizedBox(height: 12),
          Reveal(
            delay: Reveal.step(3, baseMs: 100),
            offsetY: 14,
            child: _buildRecommendationCard(
              Icons.visibility_rounded, AppColors.primary, 'RECOMMENDED',
              'Monitor Your Accounts',
              'Set up login alerts and review account activity regularly for suspicious access.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(IconData icon, Color accent, String badge, String title, String description) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(badge, style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(description, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildEmailResultWidget() {
    if (_checkStatus == 'loading') {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_checkStatus == 'invalid_input') {
      return const SizedBox.shrink(); // Handled by email field error state
    }

    if (_checkStatus == 'api_error' || _checkStatus == 'timeout' || _checkStatus == 'rate_limit') {
      String errMsg = 'The exposure database could not be reached.';
      if (_checkStatus == 'timeout') {
        errMsg = 'The connection to the exposure database timed out.';
      } else if (_checkStatus == 'rate_limit') {
        errMsg = 'Too many requests. Please try again in a few minutes.';
      }
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 36),
            const SizedBox(height: 10),
            const Text('Exposure Check Failed', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.danger, fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              '$errMsg\nYour security status has NOT been verified. Do not assume your credentials are safe.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _checkEmail,
              icon: const Icon(Icons.refresh, size: 16, color: Colors.black),
              label: const Text('RETRY CHECK', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      );
    }

    if (_checkStatus == 'success_no_exposure') {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle_outline, color: AppColors.success, size: 28),
                SizedBox(width: 10),
                Text('SAFE / NO KNOWN EXPOSURE', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'We couldn\'t find "$_checkedEmail" in the breach databases checked by ScamShield.',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            Text(
              'Last checked: ${_formatCheckedAt(_emailResult?.checkedAt)}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 8),
            const Divider(color: AppColors.success, thickness: 0.5),
            const SizedBox(height: 6),
            const Text(
              'Disclaimer: "No known exposure" indicates the email was not found in database leaks indexed by our database. This does not guarantee that your account has never been compromised in private or unindexed incidents.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontStyle: FontStyle.italic, height: 1.4),
            ),
          ],
        ),
      );
    }

    if (_checkStatus == 'success_exposed') {
      final breaches = _emailResult?.breaches ?? [];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 28),
                    const SizedBox(width: 10),
                    Text(
                      'EXPOSED IN ${breaches.length} BREACH${breaches.length > 1 ? 'ES' : ''}',
                      style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Warning! "$_checkedEmail" was found in public data leaks. Your passwords or credentials might be compromised.',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('BREACH DETAILS FOR $_checkedEmail', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1)),
          const SizedBox(height: 10),
          ...breaches.map((b) => _buildBackendBreachCard(b)),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildBackendBreachCard(BackendBreachInfo breach) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  'https://www.google.com/s2/favicons?domain=${breach.domain}&sz=32',
                  width: 32,
                  height: 32,
                  errorBuilder: (_, _, _) => Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.security, color: AppColors.danger, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(breach.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(breach.domain, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  breach.date.split('-')[0],
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Exposed Information:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: breach.dataClasses.map((dc) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(dc, style: const TextStyle(fontSize: 10, color: AppColors.textPrimary)),
            )).toList(),
          ),
        ],
      ),
    );
  }
}
