import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/user_profile_service.dart';
import '../services/permission_service.dart';
import '../services/auth_service.dart';
import '../data/education/progress_service.dart';
import 'login_screen.dart';
import '../main.dart' show MainNavigation;

/// Branded splash screen shown immediately at launch so the user never sees
/// a blank screen while the app performs its one-time async bootstrap.
class SplashScreen extends StatefulWidget {
  /// When non-null the app skips the bootstrap and goes straight to the
  /// matching shell (used only by tests to enter the app quickly).
  final bool? initialLoggedIn;

  const SplashScreen({super.key, this.initialLoggedIn});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseController;
  bool _ready = false;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLoggedIn != null) {
      _loggedIn = widget.initialLoggedIn!;
      _ready = true;
    } else {
      _pulseController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..repeat(reverse: true);
      _bootstrap();
    }
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Each bootstrap step is guarded so a failure never leaves the user on a
    // blank or error screen — the app still proceeds to the login/home flow.
    try {
      await UserProfileService.init();
    } catch (_) {}
    try {
      await PermissionService.requestAllPermissionsOnce();
    } catch (_) {}
    try {
      await ProgressService().updateStreak();
    } catch (_) {}
    var loggedIn = false;
    try {
      loggedIn = await AuthService.isLoggedIn();
    } catch (_) {}
    if (!mounted) return;
    _pulseController?.stop();
    setState(() {
      _loggedIn = loggedIn;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return _loggedIn ? const MainNavigation() : const LoginScreen();
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _pulseAnimation(),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.xxl),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        blurRadius: 40,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/icon.png',
                    height: 96,
                    width: 96,
                    errorBuilder: (c, e, s) => const Icon(
                      Icons.shield,
                      size: 96,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'ScamShield',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Securing your digital ecosystem',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: AppSpacing.xl),
              const SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  minHeight: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Animation<double> _pulseAnimation() {
    final begin = 0.96;
    final end = 1.04;
    return Tween<double>(begin: begin, end: end).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInOut),
    );
  }
}
