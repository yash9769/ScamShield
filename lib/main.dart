import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/apk_scan_screen.dart';
import 'screens/history_screen.dart';
import 'screens/learn_screen.dart';
import 'screens/profile_screen.dart';
import 'services/user_profile_service.dart';
import 'services/permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserProfileService.init();
  // Request all permissions once upfront
  await PermissionService.requestAllPermissionsOnce();
  runApp(const ScamShieldApp());
}

class ScamShieldApp extends StatelessWidget {
  const ScamShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScamShield',
      theme: appTheme,
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
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

  final List<Widget> _screens = [
    const HomeScreen(),
    const ScanScreen(), // Text/Link scanner
    const ApkScanScreen(), // APK scanner
    const HistoryScreen(),
    const LearnScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed, // Needed for > 5 items
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'HOME', activeIcon: Icon(Icons.home)),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'SCAN'),
          BottomNavigationBarItem(icon: Icon(Icons.android), label: 'APK SCAN'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'HISTORY'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'LEARN'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'PROFILE', activeIcon: Icon(Icons.person)),
        ],
      ),
    );
  }
}
