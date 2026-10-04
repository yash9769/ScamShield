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
import 'services/sms_screening_service.dart';
import 'services/call_screening_service.dart';
import 'services/push_notification_service.dart';
import 'screens/consent_screen.dart';
import 'data/repositories/scan_repository.dart';
import 'data/repositories/preferences_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserProfileService.init();
  await SettingsService.init();
  final startLoggedIn = await AuthService.isLoggedIn();
  final hasConsented = await ConsentService().hasGivenCurrentConsent();
  await PermissionService.requestAllPermissionsOnce();
  // Best-effort, non-blocking: remove stale generated-report files from the
  // OS temp directory (retention control — see DataPrivacyService).
  unawaited(DataPrivacyService().cleanupStaleTempReports());
  // Apply the user's configured scan-history retention period, if any
  // (Settings > Privacy & Data > Data Retention). No-ops when unset (0).
  unawaited(_applyScanHistoryRetention());
  // Re-attaches the live SMS listener and drains anything queued while the
  // app wasn't running — a no-op unless the user has explicitly turned this
  // on in Profile > Real-Time SMS Protection.
  unawaited(SmsScreeningService.initIfEnabled());
  // Same shape: no-op unless the user granted the call-screening role, and it
  // turns itself off cleanly if that role was since taken away. Also refreshes
  // the native side's known-bad number list from local scan history.
  unawaited(CallScreeningService.initIfEnabled());
  // Push notifications for family alerts. Fails soft and silently on any build
  // without a Firebase config, which is why it is safe to call unconditionally.
  unawaited(PushNotificationService.init());
  runApp(ScamShieldApp(startLoggedIn: startLoggedIn, hasConsented: hasConsented));
}

Future<void> _applyScanHistoryRetention() async {
  try {
    final prefs = await PreferencesRepository().load();
    if (prefs.autoDeleteDays > 0) {
      await ScanRepository().deleteOlderThan(prefs.autoDeleteDays);
    }
  } catch (_) {}
}

class ScamShieldApp extends StatefulWidget {
  final bool startLoggedIn;
  final bool hasConsented;

  const ScamShieldApp({super.key, this.startLoggedIn = false, this.hasConsented = false});

  @override
  State<ScamShieldApp> createState() => _ScamShieldAppState();
}

class _ScamShieldAppState extends State<ScamShieldApp> {
  late bool _hasConsented = widget.hasConsented;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScamShield',
      theme: appTheme,
      home: !_hasConsented
          ? ConsentScreen(onConsented: () => setState(() => _hasConsented = true))
          : (widget.startLoggedIn ? const MainNavigation() : const LoginScreen()),
      debugShowCheckedModeBanner: false,
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
    ShareIntentService.init();
    ShareIntentService.pending.addListener(_onSharedContent);
    _checkWatchedBreaches();
    _syncIfSignedIn();
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
            const Icon(Icons.mark_email_unread, color: AppColors.warning, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                more > 0 ? '$headline (+$more more)' : headline,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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
      _checkClipboard();
      _checkWatchedBreaches();
      _syncIfSignedIn();
    }
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? "";
      if (text.isNotEmpty && text != _lastCopiedText) {
        if (text.contains("http://") || text.contains("https://") || text.toUpperCase().contains("URGENT") || text.toUpperCase().contains("OTP")) {
          _lastCopiedText = text;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.surfaceLight,
                duration: const Duration(seconds: 4),
                content: Row(
                  children: [
                    const Icon(Icons.security, color: AppColors.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Copied link/text detected in clipboard!",
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
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
                  },
                ),
              ),
            );
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              backgroundColor: Colors.transparent,
              elevation: 0,
              type: BottomNavigationBarType.fixed,
              selectedFontSize: 11,
              unselectedFontSize: 10,
              selectedItemColor: AppColors.primary,
              unselectedItemColor: AppColors.textSecondary,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.shield_outlined),
                  activeIcon: Icon(Icons.shield, color: AppColors.primary),
                  label: 'HOME',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.qr_code_scanner),
                  activeIcon: Icon(Icons.center_focus_strong, color: AppColors.primary),
                  label: 'SCAN',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.mark_email_unread_outlined),
                  activeIcon: Icon(Icons.mark_email_unread, color: AppColors.primary),
                  label: 'BREACH',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.history_outlined),
                  activeIcon: Icon(Icons.history, color: AppColors.primary),
                  label: 'HISTORY',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.menu_book_outlined),
                  activeIcon: Icon(Icons.menu_book, color: AppColors.primary),
                  label: 'LEARN',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person, color: AppColors.primary),
                  label: 'PROFILE',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
