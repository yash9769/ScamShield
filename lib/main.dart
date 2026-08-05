import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/apk_scan_screen.dart';
import 'screens/history_screen.dart';
import 'screens/learn_screen.dart';
import 'screens/profile_screen.dart';
import 'widgets/friendly_error_widget.dart';

/// Bumped by the friendly error screen's Retry button to remount the app
/// root (keyed SplashScreen) so the whole tree rebuilds fresh.
final ValueNotifier<int> retrySignal = ValueNotifier<int>(0);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Replace Flutter's default red error screen with a friendly, actionable
  // error state so users never see a raw stack trace.
  ErrorWidget.builder = (details) => FriendlyErrorWidget(details: details);
  FriendlyErrorWidget.onRetry = () => retrySignal.value++;
  runApp(const ScamShieldApp());
}

class ScamShieldApp extends StatelessWidget {
  /// When null the app decides at runtime (via the splash screen) whether the
  /// user has an active session. Passed true/false only in tests to skip the
  /// bootstrap splash.
  final bool? loggedIn;

  const ScamShieldApp({super.key, this.loggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScamShield',
      theme: appTheme,
      debugShowCheckedModeBanner: false,
      home: ValueListenableBuilder<int>(
        valueListenable: retrySignal,
        builder: (context, count, _) => SplashScreen(
          key: ValueKey('boot-$count'),
          initialLoggedIn: loggedIn,
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

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  final GlobalKey<HistoryScreenState> _historyKey = GlobalKey<HistoryScreenState>();
  final GlobalKey<LearnScreenState> _learnKey = GlobalKey<LearnScreenState>();
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(
        key: _homeKey,
        onScanNow: () => setState(() => _selectedIndex = 1),
      ),
      const ScanScreen(), // Text/Link scanner
      const ApkScanScreen(), // APK scanner
      HistoryScreen(key: _historyKey),
      LearnScreen(key: _learnKey),
      const ProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: _ScamShieldBottomNav(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (index == 0) {
              _homeKey.currentState?.refresh();
            } else if (index == 3) {
              _historyKey.currentState?.refresh();
            } else if (index == 4) {
              _learnKey.currentState?.refresh();
            }
          });
        },
      ),
    );
  }
}

/// Custom bottom navigation with a prominent pill highlight on the active
/// tab so the current screen is always obvious.
class _ScamShieldBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _ScamShieldBottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    (icon: Icons.home_outlined, activeIcon: Icons.home, label: 'HOME'),
    (icon: Icons.qr_code_scanner_outlined, activeIcon: Icons.qr_code_scanner, label: 'SCAN'),
    (icon: Icons.android_outlined, activeIcon: Icons.android, label: 'APK SCAN'),
    (icon: Icons.history_outlined, activeIcon: Icons.history, label: 'HISTORY'),
    (icon: Icons.menu_book_outlined, activeIcon: Icons.menu_book, label: 'LEARN'),
    (icon: Icons.person_outline, activeIcon: Icons.person, label: 'PROFILE'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Row(
            children: List.generate(_items.length, (index) {
              final item = _items[index];
              final isActive = currentIndex == index;
              return Expanded(
                child: _NavItem(
                  icon: isActive ? item.activeIcon : item.icon,
                  label: item.label,
                  isActive: isActive,
                  onTap: () => onTap(index),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(
                color: isActive
                    ? AppColors.primary.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              letterSpacing: 0.4,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
