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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserProfileService.init();
  await SettingsService.init();
  final startLoggedIn = await AuthService.isLoggedIn();
  await PermissionService.requestAllPermissionsOnce();
  runApp(ScamShieldApp(startLoggedIn: startLoggedIn));
}

class ScamShieldApp extends StatelessWidget {
  final bool startLoggedIn;

  const ScamShieldApp({super.key, this.startLoggedIn = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScamShield',
      theme: appTheme,
      home: startLoggedIn ? const MainNavigation() : const LoginScreen(),
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
              color: Colors.black.withOpacity(0.4),
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
