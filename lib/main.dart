import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/breach_screen.dart';
import 'screens/history_screen.dart';
import 'screens/learn_screen.dart';
import 'screens/learning_module_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/apk_scan_screen.dart';
import 'screens/safe_vault_screen.dart';
import 'screens/sim_lock_screen.dart';
import 'services/user_profile_service.dart';
import 'services/backend_config.dart';
import 'services/permission_service.dart';
import 'services/settings_service.dart';
import 'services/auth_service.dart';
import 'services/clipboard_analyzer.dart';
import 'services/osint_service.dart';
import 'services/app_capabilities_service.dart';
import 'widgets/offline_banner.dart';
import 'widgets/scamshield_bottom_nav.dart';

/// Sentry DSN — supplied at build time via:
///   flutter build apk --dart-define=SENTRY_DSN=https://xxx@yyy.ingest.sentry.io/zzz
/// If the define is absent (local dev), Sentry is silently disabled.
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fail fast in release builds when the backend URL is missing or insecure.
  BackendConfig.validate();
  await UserProfileService.init();
  await SettingsService.init();
  final startLoggedIn = await AuthService.isLoggedIn();
  await PermissionService.requestAllPermissionsOnce();
  // Probe backend capabilities immediately at startup — do NOT await so it
  // never blocks the UI. The OfflineBanner / HomeScreen will react via
  // ValueListenable when the check completes.
  AppCapabilitiesService.init();

  if (_sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = _sentryDsn;
        // Capture 100% of errors, 5% of performance traces.
        options.tracesSampleRate = 0.05;
        // Personally-identifiable data: never send user IPs or names.
        options.sendDefaultPii = false;
        options.environment = const String.fromEnvironment(
          'SCAMSHIELD_ENV',
          defaultValue: 'production',
        );
      },
      appRunner: () => _runApp(startLoggedIn),
    );
  } else {
    _runApp(startLoggedIn);
  }
}

void _runApp(bool startLoggedIn) {
  runApp(ScamShieldApp(startLoggedIn: startLoggedIn));
}

class ScamShieldApp extends StatelessWidget {
  final bool startLoggedIn;

  const ScamShieldApp({super.key, this.startLoggedIn = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ScamShield',
      theme: appTheme,
      routerConfig: _createRouter(startLoggedIn),
      debugShowCheckedModeBanner: false,
    );
  }
}

GoRouter _createRouter(bool initialLoggedIn) {
  return GoRouter(
    initialLocation: initialLoggedIn ? '/home' : '/login',
    // Add error handling for unknown routes
    errorBuilder: (context, state) => Material(
      child: Scaffold(
        appBar: AppBar(title: const Text('Page Not Found')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'The page you are looking for does not exist.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.goNamed('home'),
                child: const Text('Go to Home'),
              ),
            ],
          ),
        ),
      ),
    ),
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainNavigation(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/scan',
                name: 'scan',
                builder: (context, state) {
                  final text = state.uri.queryParameters['text'];
                  return ScanScreen(initialText: text);
                },
              ),
              GoRoute(
                path: '/apk-scan',
                name: 'apk-scan',
                builder: (context, state) => const ApkScanScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/breach',
                name: 'breach',
                builder: (context, state) => const BreachScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                name: 'history',
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/learn',
                name: 'learn',
                builder: (context, state) => const LearnScreen(),
              ),
              GoRoute(
                path: '/learn/:moduleId',
                name: 'learning-module',
                builder: (context, state) {
                  // For now, default to first module - modules are defined in LearnScreen
                  return const LearningModuleScreen(
                    module: LearningModuleData(
                      title: 'Security Basics',
                      subtitle: 'Learn to protect yourself',
                      icon: Icons.shield,
                      keyTakeaways: ['Stay vigilant', 'Verify sources', 'Use strong passwords'],
                      fullLessonText: 'Security begins with awareness and understanding common attack vectors.',
                      quizQuestions: [],
                    ),
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: 'profile',
                builder: (context, state) => const ProfileScreen(),
              ),
              GoRoute(
                path: '/vault',
                name: 'vault',
                builder: (context, state) => const SafeVaultScreen(),
              ),
              GoRoute(
                path: '/sim-lock',
                name: 'sim-lock',
                builder: (context, state) => const SimLockScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class MainNavigation extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  
  const MainNavigation({super.key, required this.navigationShell});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with WidgetsBindingObserver {
  String _lastClipboardHash = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkClipboard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboard();
    }
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? "";
      if (text.isEmpty) return;

      final analysis = ClipboardAnalyzer.analyze(text);
      if (!analysis.isThreat) return;

      // Dedup: only alert once per distinct copied content, no matter how many
      // times the user switches back to the app.
      if (analysis.contentHash == _lastClipboardHash) return;
      _lastClipboardHash = analysis.contentHash;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.surfaceLight,
          duration: const Duration(seconds: 6),
          content: Row(
            children: [
              const Icon(Icons.warning_amber, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      analysis.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      analysis.description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: "SCAN NOW",
            textColor: AppColors.primary,
            onPressed: () => _startClipboardScan(text, analysis),
          ),
        ),
      );
    } catch (_) {}
  }

  /// Explicit user action: send the copied content to the backend scanner and
  /// enrich it with OSINT lookups. This is the only path that ever transmits
  /// clipboard contents off-device.
  void _startClipboardScan(String text, ClipboardAnalysis analysis) {
    context.go('/scan');
    ScanScreen.pendingClipboardScan.value = text;
    _enrichClipboardScan(analysis);
  }

  Future<void> _enrichClipboardScan(ClipboardAnalysis analysis) async {
    final positives = <OsintResult>[];
    try {
      if (analysis.urls.isNotEmpty) {
        final verdicts = await OsintService.checkUrlsGoogleSafeBrowsing(analysis.urls);
        positives.addAll(verdicts.where((r) => r.isMalicious));
      }
      for (final host in analysis.ipHosts) {
        final ip = Uri.tryParse(host)?.host;
        if (ip != null && RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(ip)) {
          final verdict = await OsintService.checkIpAbuseIPDB(ip);
          if (verdict.isMalicious) positives.add(verdict);
        }
      }
    } catch (_) {
      return;
    }
    if (positives.isEmpty || !mounted) return;

    final providers = positives.map((r) => r.provider).toSet().join(', ');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.gpp_bad, color: AppColors.danger, size: 26),
            SizedBox(width: 10),
            Text('Threat intelligence hit', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '${positives.length} flagged connection(s) reported by $providers. '
          'The linked host is listed on a threat-intelligence feed — do not '
          'open it or enter any details.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('GOT IT', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const navItems = [
      ScamShieldBottomNavItem(icon: Icons.shield_outlined, activeIcon: Icons.shield, label: 'HOME'),
      ScamShieldBottomNavItem(icon: Icons.center_focus_weak, activeIcon: Icons.center_focus_strong, label: 'SCAN'),
      ScamShieldBottomNavItem(icon: Icons.mark_email_unread_outlined, activeIcon: Icons.mark_email_unread, label: 'BREACH'),
      ScamShieldBottomNavItem(icon: Icons.history_outlined, activeIcon: Icons.history, label: 'HISTORY'),
      ScamShieldBottomNavItem(icon: Icons.menu_book_outlined, activeIcon: Icons.menu_book, label: 'LEARN'),
      ScamShieldBottomNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'PROFILE'),
    ];

    return Scaffold(
      extendBody: true,
      body: OfflineBanner(
        child: widget.navigationShell,
      ),
      bottomNavigationBar: ScamShieldBottomNav(
        currentIndex: widget.navigationShell.currentIndex,
        items: navItems,
        onTap: (index) {
          HapticFeedback.selectionClick();
          final routes = ['/home', '/scan', '/breach', '/history', '/learn', '/profile'];
          context.go(routes[index]);
        },
      ),
    );
  }
}