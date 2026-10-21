import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../widgets/animated_radar.dart';
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
  late AnimationController _scanController;

  List<BreachInfo> _breaches = [];
  bool _isLoading = true;
  String _error = '';

  final TextEditingController _emailController = TextEditingController();
  BreachCheckResult? _emailResult;
  bool _isCheckingEmail = false;
  String _emailError = '';
  String _checkedEmail = '';
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
    // Initialize scan animation controller for animated radar
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    
    _loadBreaches();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _scanController.dispose();
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



  Future<void> _checkEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _emailError = 'Please enter a valid email address.';
      });
      return;
    }

    setState(() {
      _isCheckingEmail = true;
      _emailError = '';
      _emailResult = null;
      _checkedEmail = email;
    });

    try {
      final result = await BreachService.checkEmailBreach(email);
      final watched = await BreachWatchService.isWatched(email);
      if (mounted) {
        setState(() {
          _isCheckingEmail = false;
          _emailResult = result;
          _isWatched = watched;
        });
      }
    } on BreachCheckException catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingEmail = false;
          _emailError = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCheckingEmail = false;
          _emailError = 'Failed to check email. Please try again.';
        });
      }
    }
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
      final added = await BreachWatchService.watch(
        _checkedEmail,
        result.breachCount,
      );
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

  /// Email Breach Check section with animated radar and premium UI
  Widget _buildEmailCheckSection() {
    return Column(
      children: [
        // Hero section with animated radar
        _buildEmailCheckHero(),
        const SizedBox(height: AppSpacing.xxl),
        
        // Email input field
        _buildEmailInput(),
        const SizedBox(height: AppSpacing.lg),
        
        // Check button
        _buildCheckButton(),
        const SizedBox(height: AppSpacing.lg),
        
        // Error message if any
        if (_emailError.isNotEmpty)
          _buildErrorCard(),
        const SizedBox(height: AppSpacing.lg),
        
        // Results if we have them
        if (_emailResult != null)
          _buildBreachResultsCard(),
        const SizedBox(height: AppSpacing.lg),
        
        // Watch toggle if we have results
        if (_emailResult != null)
          _buildWatchToggle(),
      ],
    );
  }

  /// Hero section with animated radar for email check
  Widget _buildEmailCheckHero() {
    final isProtected = _emailResult?.exposed == false;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: _isCheckingEmail || (_emailResult != null && !isProtected)
              ? AppColors.warning.withValues(alpha: 0.3)
              : AppColors.accent.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _isCheckingEmail || (_emailResult != null && !isProtected)
                ? AppColors.warning.withValues(alpha: 0.2)
                : AppColors.protectedGlow,
            blurRadius: 40,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        children: [
          // Status text
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _isCheckingEmail
                      ? AppColors.primary
                      : isProtected
                          ? AppColors.success
                          : _emailResult?.exposed == true
                              ? AppColors.danger
                              : AppColors.textSecondary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isCheckingEmail
                              ? AppColors.primary
                              : isProtected
                                  ? AppColors.success
                                  : AppColors.danger)
                          .withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _isCheckingEmail
                    ? "Scanning for breaches..."
                    : _emailResult == null
                        ? "Enter your email to check"
                        : isProtected
                            ? "Your email is safe"
                            : "Exposures detected!",
                style: AppText.subheading.copyWith(
                  color: _isCheckingEmail
                      ? AppColors.primary
                      : isProtected
                          ? AppColors.success
                          : AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // Animated Radar - main visual focal point
          Center(
            child: AnimatedRadar(
              size: 200,
              isScanning: _isCheckingEmail,
              threatMarkers: _emailResult?.exposed == true
                  ? [
                      const Offset(-0.25, -0.15),
                      const Offset(0.35, 0.08),
                    ]
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Security summary
          Text(
            _isCheckingEmail
                ? "Checking global breach databases..."
                : "Real-time breach monitoring active",
            style: AppText.bodyMuted,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Email input field with premium styling
  Widget _buildEmailInput() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.surfaceLight,
          width: 1,
        ),
      ),
      child: TextField(
        controller: _emailController,
        decoration: InputDecoration(
          hintText: 'Enter your email address',
          hintStyle: AppText.secondary,
          prefixIcon: const Icon(
            Icons.email_outlined,
            color: AppColors.textSecondary,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
        ),
        style: AppText.body,
        keyboardType: TextInputType.emailAddress,
      ),
    );
  }

  /// Primary check button with animation
  Widget _buildCheckButton() {
    return GestureDetector(
      onTap: _isCheckingEmail ? null : _checkEmail,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          gradient: _isCheckingEmail
              ? null
              : AppColors.protectionGradient,
          color: _isCheckingEmail ? AppColors.surfaceLight : null,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: !_isCheckingEmail
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 25,
                    spreadRadius: 5,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isCheckingEmail
                  ? Icons.sync_rounded
                  : Icons.search_rounded,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              _isCheckingEmail ? 'Checking...' : 'Check for Breaches',
              style: AppText.subheading.copyWith(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Error message card
  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.danger.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: AppColors.danger,
            size: 24,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              _emailError,
              style: AppText.body.copyWith(
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Premium breach results card with risk visualization
  Widget _buildBreachResultsCard() {
    final result = _emailResult!;
    final isExposed = result.exposed;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isExposed
              ? AppColors.danger.withValues(alpha: 0.3)
              : AppColors.success.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isExposed
                ? AppColors.danger.withValues(alpha: 0.2)
                : AppColors.success.withValues(alpha: 0.2),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Results for $_checkedEmail',
                style: AppText.subheading,
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: isExposed
                      ? AppColors.danger.withValues(alpha: 0.15)
                      : AppColors.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  isExposed ? '${result.breachCount} breaches' : 'Protected',
                  style: AppText.caption.copyWith(
                    color: isExposed ? AppColors.danger : AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (isExposed) ...[
            Text(
              'Your email has been exposed in data breaches. We recommend changing passwords for any compromised accounts.',
              style: AppText.secondary,
            ),
            const SizedBox(height: AppSpacing.lg),
            _buildSecurityRecommendations(),
          ] else
            Text(
              'Great news! Your email hasn\'t been found in any known data breaches. Continue practicing good security habits to stay protected.',
              style: AppText.secondary,
            ),
        ],
      ),
    );
  }

  /// Security recommendations for exposed emails
  Widget _buildSecurityRecommendations() {
    final recommendations = [
      {
        'icon': Icons.lock_reset,
        'title': 'Change passwords',
        'description': 'Update passwords for any accounts linked to this email',
        'color': AppColors.warning,
      },
      {
        'icon': Icons.security,
        'title': 'Enable 2FA',
        'description': 'Add two-factor authentication to all critical accounts',
        'color': AppColors.primary,
      },
      {
        'icon': Icons.monitor_heart,
        'title': 'Monitor accounts',
        'description': 'Keep an eye on your accounts for suspicious activity',
        'color': AppColors.accent,
      },
    ];

    return Column(
      children: recommendations.map((rec) {
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: (rec['color'] as Color).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  rec['icon'] as IconData,
                  color: rec['color'] as Color,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rec['title'] as String,
                      style: AppText.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      rec['description'] as String,
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWatchToggle() {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isWatched ? 'Watching this address' : 'Watch this address',
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isWatched
                      ? 'You\'ll be alerted if it turns up in a new breach.'
                      : 'A breach check only reflects today. Watch it and we\'ll re-check on app open.',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _togglingWatch
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
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
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          AppSpacing.xxxl,
          AppSpacing.screen,
          AppSpacing.huge,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Premium Header matching home_screen design
            _buildHeader(),
            const SizedBox(height: AppSpacing.xxxl),
            
            // Custom Tab Selector (modern alternative to default TabBar)
            _buildTabSelector(),
            const SizedBox(height: AppSpacing.xxl),
            
            // Tab Content
            SizedBox(
              width: double.infinity,
              child: _tabController.index == 0 
                  ? _buildEmailCheckSection() 
                  : _buildBreachListSection(),
            ),
          ],
        ),
      ),
    );
  }

  /// Premium header matching home_screen's consistent design system
  Widget _buildHeader() {
    return Row(
      children: [
        // Logo and title
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      gradient: AppColors.protectionGradient,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    'Breach Monitor',
                    style: AppText.subheading.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Track and monitor global data breaches',
                style: AppText.secondary,
              ),
            ],
          ),
        ),
        // Status indicator
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: AppColors.surfaceLight,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Live',
                style: AppText.caption.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Modern custom tab selector with animated selection
  Widget _buildTabSelector() {
    return StatefulBuilder(
      builder: (context, setState) {
        return Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: AppColors.surfaceLight,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _tabController.animateTo(0);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    decoration: BoxDecoration(
                      gradient: _tabController.index == 0
                          ? AppColors.protectionGradient
                          : null,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      boxShadow: _tabController.index == 0
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mark_email_read_outlined,
                          color: _tabController.index == 0
                              ? Colors.white
                              : AppColors.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Email Check',
                          style: AppText.body.copyWith(
                            color: _tabController.index == 0
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontWeight: _tabController.index == 0
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _tabController.animateTo(1);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    decoration: BoxDecoration(
                      gradient: _tabController.index == 1
                          ? AppColors.protectionGradient
                          : null,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      boxShadow: _tabController.index == 1
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.public_outlined,
                          color: _tabController.index == 1
                              ? Colors.white
                              : AppColors.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Recent Breaches',
                          style: AppText.body.copyWith(
                            color: _tabController.index == 1
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontWeight: _tabController.index == 1
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreachListSection() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off,
                color: AppColors.textSecondary,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadBreaches,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text(
                  'Retry Feed',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.danger,
              size: 32,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_breaches.length} Global Security Incidents',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Live feed of verified security breaches and leaked databases.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to get severity color and text
  // Format date from breach timestamp
  String _formatBreachDate(String? date) {
    if (date == null || date.isEmpty) return 'Unknown date';
    try {
      final dateTime = DateTime.parse(date);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (_) {
      return date;
    }
  }

  Widget _buildBreachCard(BreachInfo breach) {
    final isVerified = breach.isVerified;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isVerified 
              ? AppColors.surfaceLight.withValues(alpha: 0.5)
              : AppColors.warning.withValues(alpha: 0.3),
        ),
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
                    child: const Icon(
                      Icons.security,
                      color: AppColors.danger,
                      size: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isVerified)
                          const Icon(
                            Icons.verified,
                            color: AppColors.primary,
                            size: 14,
                          ),
                        if (isVerified) const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            breach.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      breach.domain,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Breach date: ${_formatBreachDate(breach.breachDate)}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isVerified ? AppColors.danger : AppColors.warning).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isVerified ? 'Verified' : 'Unverified',
                      style: TextStyle(
                        color: isVerified ? AppColors.danger : AppColors.warning,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(breach.pwnCount / 1000).toStringAsFixed(0)}K leaked',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            breach.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (!isVerified)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Unverified report',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
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