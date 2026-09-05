import 'package:flutter/material.dart';

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
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color cardGlow = Color(0x1A06B6D4);
}

// ── Type system ──────────────────────────────────────────────────────────────
//
// Inter, bundled locally (assets/fonts, SIL OFL) and declared as a font family
// in pubspec.yaml.
//
// Inter is the closest openly-licensed equivalent to Apple's San Francisco:
// same humanist-geometric skeleton, tall x-height and closed apertures, which
// is what gives macOS/iOS text its clean, quiet look. SF Pro itself is not an
// option here — Apple licenses it only for designing and developing on Apple
// platforms, so shipping it inside an Android APK would violate that license.
//
// This replaces the previous Orbitron/Rajdhani pairing, which was fetched over
// the network by google_fonts at runtime. Bundling the faces means text renders
// in the right typeface on first paint, offline, with no font-swap flash.
//
// Apple's type ramp gets its polish from optical sizing: large text is tracked
// tighter (negative letter-spacing) and small text slightly looser. Flutter has
// no optical-size axis here, so _tracking() approximates that ramp by size.
const String kFontFamily = 'Inter';

/// Approximates SF's optical tracking: tighter as text gets larger, marginally
/// looser for small UI labels, so headings feel set rather than typed.
double _tracking(double fontSize) {
  if (fontSize >= 34) return -1.0;
  if (fontSize >= 28) return -0.7;
  if (fontSize >= 22) return -0.45;
  if (fontSize >= 17) return -0.25;
  if (fontSize >= 15) return -0.1;
  if (fontSize >= 13) return 0.0;
  return 0.1;
}

TextStyle _style(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.textPrimary,
  double? height,
}) {
  return TextStyle(
    fontFamily: kFontFamily,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: _tracking(size),
    height: height,
  );
}

TextTheme _interTextTheme() {
  return TextTheme(
    displayLarge: _style(40, weight: FontWeight.w700, height: 1.1),
    displayMedium: _style(34, weight: FontWeight.w700, height: 1.12),
    displaySmall: _style(28, weight: FontWeight.w700, height: 1.15),
    headlineLarge: _style(26, weight: FontWeight.w700, height: 1.2),
    headlineMedium: _style(22, weight: FontWeight.w600, height: 1.25),
    headlineSmall: _style(20, weight: FontWeight.w600, height: 1.28),
    titleLarge: _style(18, weight: FontWeight.w600),
    titleMedium: _style(16, weight: FontWeight.w600),
    titleSmall: _style(14, weight: FontWeight.w600),
    bodyLarge: _style(16, height: 1.45),
    bodyMedium: _style(14, height: 1.45),
    bodySmall: _style(12, color: AppColors.textSecondary, height: 1.4),
    labelLarge: _style(14, weight: FontWeight.w600),
    labelMedium: _style(12, weight: FontWeight.w500, color: AppColors.textSecondary),
    labelSmall: _style(11, weight: FontWeight.w500, color: AppColors.textSecondary),
  );
}

final ThemeData _baseDark = ThemeData(
  brightness: Brightness.dark,
  // fontFamily on ThemeData is what catches the many hardcoded TextStyles
  // across the screens: they merge onto the inherited default style, so they
  // pick up Inter without each one naming a family.
  fontFamily: kFontFamily,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: const ColorScheme.dark(
    primary: AppColors.primary,
    secondary: AppColors.accent,
    surface: AppColors.surface,
  ),
);

ThemeData appTheme = _baseDark.copyWith(
  textTheme: _interTextTheme(),
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
    titleTextStyle: _style(19, weight: FontWeight.w600),
  ),
  bottomNavigationBarTheme: BottomNavigationBarThemeData(
    backgroundColor: AppColors.surface,
    selectedItemColor: AppColors.primary,
    unselectedItemColor: AppColors.textSecondary,
    type: BottomNavigationBarType.fixed,
    elevation: 12,
    selectedLabelStyle: _style(11, weight: FontWeight.w600),
    unselectedLabelStyle: _style(11, weight: FontWeight.w500),
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
    labelStyle: _style(14, color: AppColors.textSecondary),
    hintStyle: _style(14, color: AppColors.textSecondary),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.black,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: _style(15, weight: FontWeight.w600, color: Colors.black),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      textStyle: _style(14, weight: FontWeight.w600),
    ),
  ),
);
