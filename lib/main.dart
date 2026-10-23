import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/breach_screen.dart';
import 'screens/history_screen.dart';
import 'screens/learn_screen.dart';
import 'screens/profile_screen.dart';
import 'services/backend_config.dart';
import 'services/verdict_feedback_service.dart';
import 'services/user_profile_service.dart';
import 'services/permission_service.dart';
import 'services/settings_service.dart';
import 'services/auth_service.dart';
import 'services/consent_service.dart';
import 'services/data_privacy_service.dart';
import 'services/share_intent_service.dart';
import 'services/breach_watch_service.dart';
import 'services/cloud_account_service.dart';
import 'services/cloud_sync_service.dart';
import 'services/push_notification_service.dart';
import 'services/localization_service.dart';
import 'services/simple_mode_service.dart';
import 'services/home_widget_service.dart';
import 'services/data_change_notifier.dart';
import 'screens/simple_home_screen.dart';
import 'screens/consent_screen.dart';
import 'data/repositories/scan_repository.dart';
import 'data/repositories/preferences_repository.dart';
// Conditionally import platform-specific code for web compatibility
import 'package:flutter/foundation.dart' show kIsWeb;

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize core services with error handling
    // First: every server-backed service reads this address.
    await BackendConfig.init();
    BackendConfig.warmUp(); // not awaited: wakes a sleeping host while the app starts
    await UserProfileService.init();
    await SettingsService.init();
    await LocalizationService.init();
    await SimpleModeService.init();

    final startLoggedIn = await AuthService.isLoggedIn();
    final hasConsented = await ConsentService().hasGivenCurrentConsent();

    // Only request permissions on mobile platforms
    if (!kIsWeb) {
      await PermissionService.requestAllPermissionsOnce();
    }

    // Best-effort non-blocking operations that can fail gracefully
    unawaited(
      _safeExecute(() => DataPrivacyService().cleanupStaleTempReports()),
    );
    unawaited(_safeExecute(_applyScanHistoryRetention));

    // Only initialize platform-specific services on mobile
    if (!kIsWeb) {
      unawaited(_safeExecute(PushNotificationService.init));
      unawaited(_safeExecute(VerdictFeedbackService.flushPending));
      DataChangeNotifier.version.addListener(HomeWidgetService.refreshSoon);
      unawaited(_safeExecute(HomeWidgetService.refresh));
    }

    runApp(
      ScamShieldApp(startLoggedIn: startLoggedIn, hasConsented: hasConsented),
    );
  } catch (e, stackTrace) {
    // Show an error screen if initialization fails
    runApp(
      MaterialApp(
        home: Scaffold(
          backgroundColor: AppColors.background,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.danger,
                    size: 64,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Failed to initialize ScamShield',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    e.toString(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      // Retry initialization
                      main();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    child: const Text(
                      'Retry',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    debugPrint('Initialization error: $e\nStack trace: $stackTrace');
  }
}

// Helper to safely execute async functions without crashing the app
Future<void> _safeExecute(Future<void> Function() operation) async {
  try {
    await operation();
  } catch (e) {
    debugPrint('Non-critical operation failed: $e');
  }
}

Future<void> _applyScanHistoryRetention() async {
  try {
    final prefs = await PreferencesRepository().load();
    if (prefs.autoDeleteDays <= 0) return;

    final repo = ScanRepository();
    // Loaded before deleting so an aged-out scan that was ever cross-device
    // synced can be tombstoned server-side too — an automatic local purge is
    // still a deletion, and the server has no other way to learn about it.
    final cutoff = DateTime.now().subtract(
      Duration(days: prefs.autoDeleteDays),
    );
    final expiring = (await repo.loadHistory())
        .where((r) => r.timestamp.isBefore(cutoff))
        .toList();
    await repo.deleteOlderThan(prefs.autoDeleteDays);
    unawaited(CloudSyncService.pushTombstones(expiring));
  } catch (_) {}
}

class ScamShieldApp extends StatefulWidget {
  final bool startLoggedIn;
  final bool hasConsented;

  const ScamShieldApp({
    super.key,
    this.startLoggedIn = false,
    this.hasConsented = false,
  });

  @override
  State<ScamShieldApp> createState() => _ScamShieldAppState();
}

class _ScamShieldAppState extends State<ScamShieldApp> {
  late bool _hasConsented = widget.hasConsented;

  @override
  Widget build(BuildContext context) {
    // Rebuilding the whole tree on a language change is the point: without it
    // the choice would only take effect on next launch, which reads as a
    // broken setting rather than a deliberate one.
    return ValueListenableBuilder<String>(
      valueListenable: LocalizationService.language,
      builder: (context, _, _) => ValueListenableBuilder<bool>(
        valueListenable: SimpleModeService.enabled,
        builder: (context, simple, _) => MaterialApp(
          title: 'ScamShield',
          theme: appTheme,
          scrollBehavior: const _BouncyScroll(),
          // Consent and sign-in come first in either mode — Simple Mode
          // simplifies the app, it does not skip asking permission.
          home: !_hasConsented
              ? ConsentScreen(
                  onConsented: () => setState(() => _hasConsented = true),
                )
              : !widget.startLoggedIn
              ? const LoginScreen()
              : (simple ? const SimpleHomeScreen() : const MainNavigation()),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  String _lastCopiedText = "";

  final List<Widget> _screens = [
    const HomeScreen(),
    const ScanScreen(),
    const BreachScreen(),
    const HistoryScreen(),
    const LearnScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkClipboard();
    _handleWidgetLaunch();
    ShareIntentService.init();
    ShareIntentService.pending.addListener(_onSharedContent);
    _checkWatchedBreaches();
    _syncIfSignedIn();
  }

  /// Sends the user straight to the Scan tab when they arrived by tapping the
  /// home-screen widget — the entire point of the widget being one tap.
  Future<void> _handleWidgetLaunch() async {
    final action = await HomeWidgetService.consumeLaunchAction();
    if (action == 'scan' && mounted) {
      setState(() => _selectedIndex = 1);
    }
  }

  /// Best-effort background sync. Self-rate-limits and no-ops when there is no
  /// cloud session, so the app is never blocked on it.
  Future<void> _syncIfSignedIn() async {
    await CloudAccountService.refreshSignedInState();
    if (!CloudAccountService.signedIn.value) return;
    unawaited(CloudSyncService.sync());
    // Re-points the server at this device after a fresh sign-in, and re-asserts
    // the token if a previous registration failed while offline.
    unawaited(PushNotificationService.syncTokenWithAccount());
  }

  /// Re-checks watched email addresses and surfaces anything that newly turned
  /// up in a breach. The service rate-limits itself, so calling this on every
  /// app open and resume is cheap.
  Future<void> _checkWatchedBreaches() async {
    final alerts = await BreachWatchService.checkForNewBreaches();
    if (!mounted || alerts.isEmpty) return;

    final first = alerts.first;
    final more = alerts.length - 1;
    final headline = alerts.length == 1
        ? '${first.email} appeared in ${first.newExposures} new breach(es)'
        : '${alerts.length} watched addresses appeared in new breaches';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surfaceLight,
        duration: const Duration(seconds: 8),
        content: Row(
          children: [
            const Icon(
              Icons.mark_email_unread,
              color: AppColors.warning,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                more > 0 ? '$headline (+$more more)' : headline,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'REVIEW',
          textColor: AppColors.primary,
          onPressed: () => setState(() => _selectedIndex = 2),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ShareIntentService.pending.removeListener(_onSharedContent);
    super.dispose();
  }

  void _onSharedContent() {
    // ScanScreen (kept alive in the IndexedStack below) listens to the same
    // notifier to actually consume the content; this just brings the Scan
    // tab into view so the user sees the result land.
    if (ShareIntentService.pending.value != null && mounted) {
      setState(() => _selectedIndex = 1);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // A widget tap on an already-running app arrives as a resume, not a
      // fresh start, so this has to be checked here too. The native side
      // clears the extra once read, so an ordinary resume finds nothing.
      _handleWidgetLaunch();
      _checkClipboard();
      _checkWatchedBreaches();
      _syncIfSignedIn();
    }
  }

  // Track if we've already shown the clipboard alert to prevent repeats
  bool _clipboardAlertShown = false;

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? "";
      if (text.isNotEmpty && text != _lastCopiedText && !_clipboardAlertShown) {
        if (text.contains("http://") ||
            text.contains("https://") ||
            text.toUpperCase().contains("URGENT") ||
            text.toUpperCase().contains("OTP")) {
          _lastCopiedText = text;
          _clipboardAlertShown = true;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.surfaceLight,
                duration: const Duration(seconds: 8),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 80,
                  left: 16,
                  right: 16,
                ),
                content: Row(
                  children: [
                    const Icon(
                      Icons.security,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Copied link/text detected in clipboard!",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Add explicit dismiss button
                    GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        _clipboardAlertShown = false;
                      },
                      child: const Icon(
                        Icons.close,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                action: SnackBarAction(
                  label: "SCAN NOW",
                  textColor: AppColors.primary,
                  onPressed: () {
                    setState(() {
                      _selectedIndex = 1;
                    });
                    _clipboardAlertShown = false;
                  },
                ),
                dismissDirection: DismissDirection.horizontal,
                // SnackBar uses duration and automatically resets flag when dismissed
                // This maintains the existing behavior while allowing manual dismissal
              ),
            );
          }
        }
      }
    } catch (_) {
      // Reset flag if there's an error
      _clipboardAlertShown = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sentence case labels; these were "HOME", "SCAN", "BREACH", "HISTORY",
    // "LEARN", "PROFILE", six shouted words along the bottom of every screen.
    final items = <(IconData, IconData, String)>[
      (Icons.home_outlined, Icons.home_rounded, 'nav_home'),
      (Icons.search_rounded, Icons.search_rounded, 'nav_scan'),
      (
        Icons.mark_email_unread_outlined,
        Icons.mark_email_unread_rounded,
        'nav_breach',
      ),
      (Icons.history_rounded, Icons.history_rounded, 'nav_history'),
      (Icons.school_outlined, Icons.school_rounded, 'nav_learn'),
      (Icons.person_outline_rounded, Icons.person_rounded, 'nav_profile'),
    ];
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      // Black like the screens above it, split off by a hairline: the bar
      // belongs to the app instead of sitting on it as a separate slab.
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          border: Border(top: BorderSide(color: Color(0xFF2C2C2E), width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (index) {
                if (index != _selectedIndex) {
                  HapticFeedback.selectionClick();
                }
                setState(() => _selectedIndex = index);
              },
              backgroundColor: Colors.transparent,
              elevation: 0,
              type: BottomNavigationBarType.fixed,
              selectedFontSize: 10.5,
              unselectedFontSize: 10.5,
              iconSize: 23,
              selectedItemColor: AppColors.textPrimary,
              unselectedItemColor: const Color(0xFF6E6E73),
              items: [
                for (final (icon, active, key) in items)
                  BottomNavigationBarItem(
                    icon: Icon(icon),
                    activeIcon: Icon(active),
                    label: LocalizationService.tr(key),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS-style rubber-band scrolling everywhere, instead of Android's glow.
class _BouncyScroll extends MaterialScrollBehavior {
  const _BouncyScroll();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}
