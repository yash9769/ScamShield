import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color background = Color(0xFF0F172A);
  static const Color surface = Color(0xFF1E293B);
  static const Color surfaceLight = Color(0xFF334155);
  static const Color primary = Color(0xFF06B6D4); // Neon Cyan
  static const Color accent = Color(0xFF3B82F6);  // Electric Blue
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color danger = Color(0xFFEF4444);  // Crimson
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color warning = Color(0x0fffe60b); // Amber
  static const Color cardGlow = Color(0x1A06B6D4);
}

/// Accessibility-aware font sizing: ensures minimum readable size on small devices
/// while respecting user text scale preferences.
class AppFontSizes {
  /// Caption/helper text: 10px minimum for accessibility (AA standard)
  static const double caption = 11.0;
  /// Small body text: 12px default, 11px minimum
  static const double small = 12.0;
  /// Regular body text: 14px
  static const double regular = 14.0;
  /// Subtitle text: 16px
  static const double subtitle = 16.0;
  /// Heading text: 18px
  static const double heading = 18.0;
  /// Large heading: 20px+
  static const double largeHeading = 20.0;
}

// Cybersec type system:
//   Orbitron — angular, techy display face for headings and the app-bar title
//   Rajdhani — condensed, highly legible UI face for body text and controls
// Every screen uses hardcoded TextStyles (no textTheme slot lookups), so the
// Rajdhani text theme below is what actually swaps the app-wide font: its
// bodyMedium becomes the inherited DefaultTextStyle that those hardcoded
// styles merge onto without overriding the family. Orbitron is then wired into
// the heading surfaces the theme controls directly.
TextTheme _cyberTextTheme(TextTheme base) {
  final TextTheme body = GoogleFonts.rajdhaniTextTheme(base);
  TextStyle heading(TextStyle? s) =>
      GoogleFonts.orbitron(textStyle: s, fontWeight: FontWeight.w700);
  return body.copyWith(
    displayLarge: heading(body.displayLarge),
    displayMedium: heading(body.displayMedium),
    displaySmall: heading(body.displaySmall),
    headlineLarge: heading(body.headlineLarge),
    headlineMedium: heading(body.headlineMedium),
    headlineSmall: heading(body.headlineSmall),
    titleLarge: heading(body.titleLarge),
  );
}

final ThemeData _baseDark = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: const ColorScheme.dark(
    primary: AppColors.primary,
    secondary: AppColors.accent,
    surface: AppColors.surface,
  ),
);

ThemeData appTheme = _baseDark.copyWith(
  textTheme: _cyberTextTheme(_baseDark.textTheme),
  // App-wide smooth screen transitions. ZoomPageTransitionsBuilder gives a
  // premium fade-through-with-scale feel on every Navigator push, replacing the
  // default platform slide — one place, whole app.
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
    },
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: AppColors.background,
    elevation: 0,
    centerTitle: false,
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    titleTextStyle: GoogleFonts.orbitron(
      color: AppColors.textPrimary,
      fontSize: 18,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.5,
    ),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: AppColors.surface,
    selectedItemColor: AppColors.primary,
    unselectedItemColor: AppColors.textSecondary,
    type: BottomNavigationBarType.fixed,
    elevation: 12,
  ),
  cardTheme: CardThemeData(
    color: AppColors.surface,
    elevation: 4,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
    labelStyle: const TextStyle(color: AppColors.textSecondary),
    hintStyle: const TextStyle(color: AppColors.textSecondary),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.black,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: GoogleFonts.rajdhani(fontWeight: FontWeight.bold, fontSize: 16),
    ),
  ),
);
