// lib/theme.dart
//
// ScamShield's design system.
//
// ── What changed, and why ────────────────────────────────────────────────────
// The previous theme was a "tactical cyber dashboard": navy background, neon
// cyan on everything, ALL-CAPS labels with wide letter-spacing, ambient radar
// sweeps, gradient glows and a permanently pulsing primary button. It looked
// like a hacking tool.
//
// That is the wrong costume for this particular app. The people who most need
// ScamShield are the people scams actually work on — someone who just got a
// text about their bank and whose pulse is up. For them a neon console reads
// as unfamiliar and technical at exactly the moment they need something that
// feels calm, plain and trustworthy. The visual language here is now closer to
// what a bank or a health app would ship than to a security console.
//
// Four rules this system is built on:
//
//  1. **Colour means something.** Green, amber and red belong to verdicts and
//     nothing else. When every card has a cyan glow, a red "SCAM" banner is
//     just more colour. Neutrals do the structural work; one accent marks what
//     is interactive.
//  2. **Sentence case, real hierarchy.** ALL-CAPS with +1.5 tracking is harder
//     to read and shouts at people who are already anxious. Size, weight and
//     colour carry hierarchy instead.
//  3. **Stillness is a feature.** Motion happens on state change, never on a
//     loop. A screen that never settles is a screen that keeps taking your
//     attention without ever giving anything back.
//  4. **Space over ornament.** Dividers, glows and borders get removed until
//     something breaks; whitespace does the grouping.
//
// ── A note on the AppColors API ──────────────────────────────────────────────
// The token names below are unchanged from the previous theme on purpose.
// Around five hundred references across twenty-odd screens point at them, so
// re-tuning the values here restyles the entire app — including screens not
// individually rewritten — without a single call site needing to change.

import 'package:flutter/material.dart';

/// Core palette.
///
/// The background moved off navy to a true neutral charcoal: navy pushes
/// everything drawn on it slightly blue, which is what made the old accent
/// have to shout to be seen at all. On a neutral ground a much quieter accent
/// reads perfectly well.
class AppColors {
  // ── Neutrals ──────────────────────────────────────────────────────────────
  /// App background. Not pure black — pure black against an OLED panel makes
  /// the elevation steps below invisible, and haloes light text.
  static const Color background = Color(0xFF0C0E12);

  /// Raised surfaces: cards, sheets, inputs.
  static const Color surface = Color(0xFF15181F);

  /// Hairlines, borders, dividers, disabled fills. One step up from surface,
  /// deliberately close to it — a border should describe an edge, not draw a
  /// line across the screen.
  static const Color surfaceLight = Color(0xFF262B35);

  static const Color textPrimary = Color(0xFFF5F6F8);

  /// Secondary text sits at ~4.9:1 on the background — comfortably readable,
  /// while still clearly receding from primary.
  static const Color textSecondary = Color(0xFF9BA3B0);

  // ── Accent ────────────────────────────────────────────────────────────────
  /// One accent, used only for things you can act on. The old neon cyan
  /// (#06B6D4) matured into a calmer, deeper blue that still carries a hint of
  /// the original hue but stops competing with the verdict colours.
  static const Color primary = Color(0xFF5B9DFF);

  /// Used sparingly — a second interactive tone for stacked/secondary actions,
  /// not a gradient partner. (The old theme blended it into every button.)
  static const Color accent = Color(0xFF7C8CFF);

  // ── Verdict colours — reserved ────────────────────────────────────────────
  // These three are the app's most important information. They are never used
  // for decoration, section headers, icons-for-flavour or empty states.
  // Every place they appear is also labelled in words and paired with a
  // distinct icon, so the meaning survives colour blindness and greyscale.
  static const Color success = Color(0xFF3DD68C); // safe
  static const Color warning = Color(0xFFF5B849); // be careful
  static const Color danger = Color(0xFFFF6B6B);  // scam

  // `cardGlow` used to live here — the tint painted under every card to give
  // it a halo. It is gone rather than retuned: nothing referenced it outside
  // this file, and the ornament it existed for is precisely what this redesign
  // removes.
}

/// Spacing scale. Everything in the redesigned screens is a multiple of 4,
/// which is what stops a layout from looking hand-placed.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  /// Standard screen gutter.
  static const double screen = 20;
}

/// Corner radii. Three sizes plus a pill — more than that and nothing looks
/// like it belongs to the same family.
class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double pill = 999;
}

/// Motion. Short, eased, and only ever triggered by something changing.
class AppMotion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;
}

// ── Type system ──────────────────────────────────────────────────────────────
//
// Inter, bundled locally (assets/fonts, SIL OFL) and declared in pubspec.yaml.
//
// Inter is the closest openly-licensed equivalent to Apple's San Francisco:
// same humanist-geometric skeleton, tall x-height and closed apertures. SF Pro
// itself is not an option — Apple licenses it only for designing and developing
// on Apple platforms, so shipping it in an Android APK would breach that.
//
// Apple's ramp gets its polish from optical sizing: large text tracked tighter,
// small text slightly looser. Flutter has no optical-size axis, so _tracking()
// approximates it by size. Note what this function does *not* do any more —
// the old theme layered extra positive tracking on top for "tactical" labels,
// which is the letter-spacing this redesign removes.
const String kFontFamily = 'Inter';

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

/// Named entry points for the redesigned screens, so a screen asks for a role
/// ("this is a section header") rather than picking a font size by eye.
class AppText {
  /// Big numbers and verdicts. Used once per screen at most.
  static TextStyle get display => _style(32, weight: FontWeight.w700, height: 1.12);

  /// Screen titles.
  static TextStyle get title => _style(24, weight: FontWeight.w700, height: 1.2);

  /// Card and section titles.
  static TextStyle get heading => _style(19, weight: FontWeight.w600, height: 1.25);

  /// Row titles, button labels.
  static TextStyle get subheading => _style(16, weight: FontWeight.w600);

  /// Default reading size. 15px with 1.5 leading is the comfortable floor for
  /// body copy someone might read while stressed.
  static TextStyle get body => _style(15, height: 1.5);

  static TextStyle get bodyMuted =>
      _style(15, color: AppColors.textSecondary, height: 1.5);

  /// Supporting copy under a title.
  static TextStyle get secondary =>
      _style(13.5, color: AppColors.textSecondary, height: 1.45);

  /// Section labels. Sentence case, medium weight, muted — the replacement for
  /// the old ALL-CAPS +1.5-tracking headers.
  static TextStyle get label =>
      _style(13, weight: FontWeight.w600, color: AppColors.textSecondary);

  /// Timestamps, counts, meta.
  static TextStyle get caption =>
      _style(12, weight: FontWeight.w500, color: AppColors.textSecondary);
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
    bodyLarge: _style(16, height: 1.5),
    bodyMedium: _style(15, height: 1.5),
    bodySmall: _style(13, color: AppColors.textSecondary, height: 1.45),
    labelLarge: _style(15, weight: FontWeight.w600),
    labelMedium: _style(13, weight: FontWeight.w500, color: AppColors.textSecondary),
    labelSmall: _style(12, weight: FontWeight.w500, color: AppColors.textSecondary),
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
    error: AppColors.danger,
  ),
);

ThemeData appTheme = _baseDark.copyWith(
  textTheme: _interTextTheme(),
  splashFactory: InkSparkle.splashFactory,
  // Fade-through rather than the old zoom: a scale-in on every push is a lot of
  // movement for an app people open mid-panic.
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    },
  ),
  appBarTheme: AppBarTheme(
    // Matching the scaffold means the bar stops reading as a separate slab and
    // the screen starts at the content.
    backgroundColor: AppColors.background,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    elevation: 0,
    centerTitle: false,
    iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
    titleTextStyle: _style(19, weight: FontWeight.w600),
  ),
  bottomNavigationBarTheme: BottomNavigationBarThemeData(
    backgroundColor: AppColors.surface,
    selectedItemColor: AppColors.primary,
    unselectedItemColor: AppColors.textSecondary,
    type: BottomNavigationBarType.fixed,
    elevation: 0,
    selectedLabelStyle: _style(11, weight: FontWeight.w600),
    unselectedLabelStyle: _style(11, weight: FontWeight.w500),
  ),
  cardTheme: CardThemeData(
    color: AppColors.surface,
    // Flat. Depth comes from the surface step and a hairline border, not from
    // a drop shadow under every element.
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
  ),
  dividerTheme: const DividerThemeData(
    color: AppColors.surfaceLight,
    thickness: 1,
    space: 1,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: const BorderSide(color: AppColors.surfaceLight),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: const BorderSide(color: AppColors.surfaceLight),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
    labelStyle: _style(14, color: AppColors.textSecondary),
    hintStyle: _style(15, color: AppColors.textSecondary),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: const Color(0xFF08121F),
      elevation: 0,
      // 52pt: comfortably past the 48dp floor, because a mis-tap here costs
      // more than it does in most apps.
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      textStyle: _style(16, weight: FontWeight.w600),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.textPrimary,
      minimumSize: const Size.fromHeight(52),
      side: const BorderSide(color: AppColors.surfaceLight),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      textStyle: _style(16, weight: FontWeight.w600),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      textStyle: _style(15, weight: FontWeight.w600),
    ),
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: AppColors.surfaceLight,
    contentTextStyle: _style(14),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
    titleTextStyle: _style(19, weight: FontWeight.w600),
    contentTextStyle: _style(15, color: AppColors.textSecondary, height: 1.5),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: AppColors.surface,
    selectedColor: AppColors.primary,
    side: const BorderSide(color: AppColors.surfaceLight),
    labelStyle: _style(13, weight: FontWeight.w500),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
  ),
);
