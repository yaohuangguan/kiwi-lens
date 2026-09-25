import 'package:flutter/material.dart';

/// Shared colors and geometry for the Ocean identity.
abstract final class TasmanColors {
  static const sky = Color(0xFF38BDF8);
  static const coastal = Color(0xFF0EA5E9);
  static const ocean = Color(0xFF0284C7);
  static const teal = Color(0xFF0891B2);
  static const deepTeal = Color(0xFF0E7490);
  static const deepOcean = Color(0xFF0C4A6E);
  static const darkOcean = Color(0xFF082F49);
  static const midnightOcean = Color(0xFF061E2C);
  static const lightBackground = Color(0xFFF3FAFC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightText = Color(0xFF123044);
  static const lightTextSecondary = Color(0xFF526979);
  static const lightBorder = Color(0xFFD4E3EA);
  static const darkSurface = Color(0xFF103D55);
  static const darkText = Color(0xFFF5FBFD);
  static const darkTextSecondary = Color(0xFFBED4DF);
  static const darkBorder = Color(0xFF31556A);
  static const success = Color(0xFF15803D);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);
}

abstract final class TasmanSpacing {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
}

abstract final class TasmanRadius {
  static const control = 10.0;
  static const button = 14.0;
  static const panel = 18.0;
  static const sheet = 24.0;
}

abstract final class TasmanTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: TasmanColors.ocean,
      brightness: brightness,
      primary: dark ? TasmanColors.sky : TasmanColors.ocean,
      onPrimary: dark ? TasmanColors.midnightOcean : Colors.white,
      surface: dark ? TasmanColors.darkOcean : TasmanColors.lightSurface,
      onSurface: dark ? TasmanColors.darkText : TasmanColors.lightText,
      error: TasmanColors.danger,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? TasmanColors.midnightOcean
          : TasmanColors.lightBackground,
      dividerColor: dark ? TasmanColors.darkBorder : TasmanColors.lightBorder,
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TasmanRadius.button),
        ),
      ),
    );
  }
}
