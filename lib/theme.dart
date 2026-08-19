import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Core Cobalt Shield Tokens
  static const Color background = Color(0xFF0B1020);
  static const Color deepBackground = Color(0xFF080D1C);
  static const Color surface = Color(0xFF111A2D);
  static const Color elevatedSurface = Color(0xFF17213A);
  static const Color surfaceLight = Color(0xFF17213A);

  static const Color primary = Color(0xFF315CF6); // Cobalt Blue
  static const Color cobalt = Color(0xFF315CF6);
  static const Color electricBlue = Color(0xFF4F7CFF);
  static const Color accent = Color(0xFF4F7CFF);
  static const Color softViolet = Color(0xFF7C6CFF);
  static const Color aiViolet = Color(0xFF8B7CFF);

  static const Color safeEmerald = Color(0xFF35D07F);
  static const Color success = Color(0xFF35D07F);
  static const Color safeMint = Color(0xFF8BE7B5);

  static const Color warning = Color(0xFFF5B84B);
  static const Color danger = Color(0xFFFF5C67);

  static const Color textPrimary = Color(0xFFF7F5F0);
  static const Color textSecondary = Color(0xFFA7B0C0);
  static const Color mutedText = Color(0xFF68748A);

  static const Color border = Color(0xFF24304A);
  static const Color cardGlow = Color(0x26315CF6);
}

/// Accessibility-aware font sizing for editorial typography hierarchy
class AppFontSizes {
  static const double caption = 11.0;
  static const double small = 12.0;
  static const double regular = 14.0;
  static const double subtitle = 16.0;
  static const double heading = 20.0;
  static const double largeHeading = 28.0;
  static const double heroHeadline = 38.0;
}

TextTheme _cobaltTextTheme(TextTheme base) {
  final TextTheme body = GoogleFonts.plusJakartaSansTextTheme(base);
  TextStyle editorialHeading(TextStyle? s) => GoogleFonts.plusJakartaSans(
        textStyle: s,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: AppColors.textPrimary,
      );

  return body.copyWith(
    displayLarge: editorialHeading(body.displayLarge?.copyWith(fontSize: 40, height: 1.05)),
    displayMedium: editorialHeading(body.displayMedium?.copyWith(fontSize: 32, height: 1.1)),
    displaySmall: editorialHeading(body.displaySmall?.copyWith(fontSize: 26, height: 1.15)),
    headlineLarge: editorialHeading(body.headlineLarge?.copyWith(fontSize: 24)),
    headlineMedium: editorialHeading(body.headlineMedium?.copyWith(fontSize: 20)),
    headlineSmall: editorialHeading(body.headlineSmall?.copyWith(fontSize: 18)),
    titleLarge: editorialHeading(body.titleLarge?.copyWith(fontSize: 16)),
    bodyLarge: body.bodyLarge?.copyWith(color: AppColors.textPrimary, fontSize: 15, height: 1.4),
    bodyMedium: body.bodyMedium?.copyWith(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
    bodySmall: body.bodySmall?.copyWith(color: AppColors.mutedText, fontSize: 11),
  );
}

final ThemeData _baseDark = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: const ColorScheme.dark(
    primary: AppColors.primary,
    secondary: AppColors.electricBlue,
    surface: AppColors.surface,
  ),
);

DataColumn dataColumnPlaceholder = const DataColumn(label: Text(''));

ThemeData appTheme = _baseDark.copyWith(
  textTheme: _cobaltTextTheme(_baseDark.textTheme),
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
    },
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    centerTitle: false,
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    titleTextStyle: GoogleFonts.plusJakartaSans(
      color: AppColors.textPrimary,
      fontSize: 20,
      fontWeight: FontWeight.bold,
      letterSpacing: -0.3,
    ),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: AppColors.surface,
    selectedItemColor: AppColors.primary,
    unselectedItemColor: AppColors.mutedText,
    type: BottomNavigationBarType.fixed,
    elevation: 0,
  ),
  cardTheme: CardThemeData(
    color: AppColors.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: AppColors.border, width: 1),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.border, width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.border, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
    labelStyle: const TextStyle(color: AppColors.textSecondary),
    hintStyle: const TextStyle(color: AppColors.mutedText),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15),
    ),
  ),
);

