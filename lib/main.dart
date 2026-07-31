import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/home_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/history_screen.dart';
import 'screens/learn_screen.dart';
import 'screens/profile_screen.dart';

void main() {
  runApp(const ScamShieldApp());
}

class ScamShieldApp extends StatelessWidget {
  const ScamShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScamShield',
      theme: appTheme,
      home: const MainNavigation(),
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
    const ScanScreen(),
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
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'HOME', activeIcon: Icon(Icons.home)),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'SCAN'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'HISTORY'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'LEARN'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'PROFILE', activeIcon: Icon(Icons.person)),
        ],
      ),
    );
  }
}
