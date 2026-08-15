import 'package:flutter/material.dart';

/// Restrained clinical design tokens for an evidence-based learning product.
abstract final class Brand {
  // Brand & accent
  static const Color green = Color(0xFF5CC8BE);
  static const Color greenPressed = Color(0xFF0B676A);
  static const Color greenDark = Color(0xFF0B6F73);
  static const Color greenMid = Color(0xFF168C89);
  static const Color greenSoft = Color(0xFFDDF4F1);
  static const Color tealDeep = Color(0xFF102A43);
  static const Color teal = Color(0xFF1D6075);

  // Muted category accents used for curriculum-oriented topic tags.
  static const Color accentPurple = Color(0xFF665F9E);
  static const Color accentOrange = Color(0xFFB56D32);
  static const Color accentPink = Color(0xFF9C5F78);
  static const Color accentBlue = Color(0xFF356F9E);

  // Surfaces
  static const Color canvas = Color(0xFFFBFCFE);
  static const Color surface = Color(0xFFF4F7FA);
  static const Color surfaceSoft = Color(0xFFEDF2F6);
  static const Color surfaceFeature = Color(0xFFE8F5F4);
  static const Color hairline = Color(0xFFDDE5EC);
  static const Color hairlineSoft = Color(0xFFE9EFF4);
  static const Color hairlineStrong = Color(0xFFB9C7D3);
  static const Color hairlineDark = Color(0xFF29445C);

  // Text
  static const Color ink = Color(0xFF102A43);
  static const Color slate = Color(0xFF334E68);
  static const Color steel = Color(0xFF5D7285);
  static const Color stone = Color(0xFF788B9B);
  static const Color muted = Color(0xFFA5B3BF);
  static const Color onDark = Color(0xFFFFFFFF);
  static const Color onDarkMuted = Color(0xFFB9CAD8);

  // Semantic
  static const Color warningBg = Color(0xFFFFF6E6);
  static const Color warningText = Color(0xFF795329);
  static const Color danger = Color(0xFFB84444);

  static const String fontFamily = 'SF Pro Text';
  static const List<String> fontFallback = [
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
    BoxShadow(color: Color(0x0A102A43), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> shadow2 = [
    BoxShadow(color: Color(0x14102A43), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> shadow3 = [
    BoxShadow(
      color: Color(0x1F102A43),
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
    primary: Brand.greenDark,
    onPrimary: Brand.onDark,
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
      fillColor: Brand.surface,
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
