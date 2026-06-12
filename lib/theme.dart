import 'package:flutter/material.dart';

/// Design tokens from DESIGN-mongodb.md (MongoDB design system).
abstract final class Brand {
  // Brand & accent
  static const Color green = Color(0xFF00ED64);
  static const Color greenPressed = Color(0xFF008C34);
  static const Color greenDark = Color(0xFF00684A);
  static const Color greenMid = Color(0xFF00A35C);
  static const Color greenSoft = Color(0xFFC3F0D2);
  static const Color tealDeep = Color(0xFF001E2B);
  static const Color teal = Color(0xFF003D4F);

  // Category accents (used only for question-category tags)
  static const Color accentPurple = Color(0xFF7B3FF2);
  static const Color accentOrange = Color(0xFFFA6E39);
  static const Color accentPink = Color(0xFFF06BB8);
  static const Color accentBlue = Color(0xFF3D4F9F);

  // Surfaces
  static const Color canvas = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF9FBFA);
  static const Color surfaceSoft = Color(0xFFF4F7F6);
  static const Color surfaceFeature = Color(0xFFE3FCEF);
  static const Color hairline = Color(0xFFE1E5E8);
  static const Color hairlineSoft = Color(0xFFECEFF1);
  static const Color hairlineStrong = Color(0xFFC1CCD6);
  static const Color hairlineDark = Color(0xFF1C2D38);

  // Text
  static const Color ink = Color(0xFF001E2B);
  static const Color slate = Color(0xFF3D4F5B);
  static const Color steel = Color(0xFF5C6C7A);
  static const Color stone = Color(0xFF7C8C9A);
  static const Color muted = Color(0xFFA8B3BC);
  static const Color onDark = Color(0xFFFFFFFF);
  static const Color onDarkMuted = Color(0xFFA8B3BC);

  // Semantic
  static const Color warningBg = Color(0xFFFFF8E0);
  static const Color warningText = Color(0xFF946F3F);
  static const Color danger = Color(0xFFEF5350);

  static const String fontFamily = 'Euclid Circular A';
  static const List<String> fontFallback = [
    'SF Pro Text',
    'Segoe UI',
    'Roboto',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];

  // Motion (design doc recommends 150-200ms ease for transitions)
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration smooth = Duration(milliseconds: 300);
  static const Duration entrance = Duration(milliseconds: 420);
  static const Curve easing = Curves.easeOutCubic;

  // Elevation scale (levels 1-3 from the design doc)
  static const List<BoxShadow> shadow1 = [
    BoxShadow(color: Color(0x0A001E2B), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> shadow2 = [
    BoxShadow(color: Color(0x14001E2B), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> shadow3 = [
    BoxShadow(
      color: Color(0x1F001E2B),
      blurRadius: 24,
      offset: Offset(0, 12),
      spreadRadius: -4,
    ),
  ];
}

TextStyle brandText(
  double size,
  FontWeight weight,
  double height, {
  double spacing = 0,
  Color color = Brand.ink,
}) {
  return TextStyle(
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: spacing,
    color: color,
    fontFamily: Brand.fontFamily,
    fontFamilyFallback: Brand.fontFallback,
  );
}

ThemeData buildBrandTheme() {
  final textTheme = TextTheme(
    displaySmall: brandText(36, FontWeight.w500, 1.25, spacing: -0.5),
    headlineMedium: brandText(28, FontWeight.w500, 1.30, spacing: -0.5),
    headlineSmall: brandText(22, FontWeight.w500, 1.35),
    titleLarge: brandText(22, FontWeight.w500, 1.35),
    titleMedium: brandText(18, FontWeight.w600, 1.40),
    titleSmall: brandText(16, FontWeight.w500, 1.55),
    bodyLarge: brandText(16, FontWeight.w400, 1.55),
    bodyMedium: brandText(14, FontWeight.w400, 1.50),
    bodySmall: brandText(13, FontWeight.w400, 1.40, color: Brand.steel),
    labelLarge: brandText(14, FontWeight.w600, 1.30),
    labelMedium: brandText(13, FontWeight.w600, 1.40),
    labelSmall: brandText(11, FontWeight.w600, 1.40, spacing: 1),
  );

  const scheme = ColorScheme.light(
    primary: Brand.green,
    onPrimary: Brand.ink,
    secondary: Brand.greenDark,
    onSecondary: Brand.onDark,
    surface: Brand.canvas,
    onSurface: Brand.ink,
    outline: Brand.hairlineStrong,
    outlineVariant: Brand.hairline,
    error: Brand.danger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.canvas,
    fontFamily: Brand.fontFamily,
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.canvas,
      foregroundColor: Brand.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: Brand.hairline)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            textStyle: textTheme.labelLarge,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape: const StadiumBorder(),
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) return Brand.hairline;
              if (states.contains(WidgetState.pressed)) {
                return Brand.greenPressed;
              }
              return Brand.green;
            }),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? Brand.muted
                  : Brand.ink,
            ),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.ink,
        side: const BorderSide(color: Brand.hairlineStrong),
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Brand.greenDark,
        textStyle: brandText(14, FontWeight.w500, 1.50),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.canvas,
      hintStyle: brandText(15, FontWeight.w400, 1.50, color: Brand.steel),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Brand.hairlineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Brand.greenDark, width: 2),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Brand.hairlineStrong),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Brand.canvas,
      side: const BorderSide(color: Brand.hairline),
      shape: const StadiumBorder(),
      labelStyle: brandText(13, FontWeight.w500, 1.40, color: Brand.slate),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Brand.canvas,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: brandText(22, FontWeight.w500, 1.35),
      contentTextStyle: brandText(
        15,
        FontWeight.w400,
        1.55,
        color: Brand.slate,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Brand.canvas,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Brand.hairline,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Brand.greenMid,
    ),
  );
}
