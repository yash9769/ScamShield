import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF0B1015);
  static const Color surface = Color(0xFF1A212A);
  static const Color primary = Color(0xFF00D1FF);
  static const Color accent = Color(0xFF007BFF);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.grey;
  static const Color danger = Color(0xFFFF4D4D);
  static const Color success = Color(0xFF00E676);
  static const Color warning = Color(0xFFFFB74D);
}

ThemeData appTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: const ColorScheme.dark(
    primary: AppColors.primary,
    secondary: AppColors.accent,
    surface: AppColors.surface,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.background,
    elevation: 0,
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: AppColors.background,
    selectedItemColor: AppColors.primary,
    unselectedItemColor: AppColors.textSecondary,
    type: BottomNavigationBarType.fixed,
  ),
  cardTheme: CardThemeData(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
);
