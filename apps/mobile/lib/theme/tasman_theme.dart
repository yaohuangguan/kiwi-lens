import 'package:flutter/material.dart';

/// Shared colors and geometry for the Ocean identity.
abstract final class TasmanColors {
  static const sky = Color(0xFFB9E1FF);
  static const coastal = Color(0xFF3B82F6);
  static const ocean = Color(0xFF0077B6);
  static const teal = Color(0xFF00A6A6);
  static const deepTeal = Color(0xFF0E7490);
  static const deepOcean = Color(0xFF0C4A6E);
  static const darkOcean = Color(0xFF082F49);
  static const midnightOcean = Color(0xFF032B45);
  static const lightBackground = Color(0xFFF5FAFD);
  static const mist = Color(0xFFEAF6FC);
  static const ice = Color(0xFFDDF1FB);
  static const horizon = Color(0xFF65C7E8);
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
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: dark
            ? TasmanColors.darkOcean
            : TasmanColors.lightBackground,
        foregroundColor: dark ? TasmanColors.darkText : TasmanColors.deepOcean,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? TasmanColors.darkSurface : TasmanColors.lightSurface,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: dark ? TasmanColors.darkBorder : TasmanColors.lightBorder,
          ),
          borderRadius: BorderRadius.circular(TasmanRadius.panel),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark
            ? TasmanColors.darkSurface
            : TasmanColors.lightSurface,
        selectedColor: dark ? TasmanColors.deepTeal : TasmanColors.ice,
        side: BorderSide(
          color: dark ? TasmanColors.darkBorder : TasmanColors.lightBorder,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        labelStyle: TextStyle(
          color: dark ? TasmanColors.darkText : TasmanColors.deepOcean,
          fontWeight: FontWeight.w700,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return dark
                ? TasmanColors.darkTextSecondary.withValues(alpha: .45)
                : TasmanColors.lightTextSecondary.withValues(alpha: .45);
          }
          if (states.contains(WidgetState.selected)) {
            return dark ? TasmanColors.midnightOcean : Colors.white;
          }
          return dark ? TasmanColors.darkTextSecondary : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return dark
                ? TasmanColors.darkBorder.withValues(alpha: .45)
                : TasmanColors.lightBorder.withValues(alpha: .55);
          }
          if (states.contains(WidgetState.selected)) {
            return dark ? TasmanColors.sky : TasmanColors.ocean;
          }
          return dark ? TasmanColors.darkSurface : TasmanColors.lightBorder;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return dark ? TasmanColors.darkBorder : TasmanColors.lightBorder;
        }),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: dark
            ? TasmanColors.darkOcean
            : TasmanColors.lightSurface,
        indicatorColor: dark ? TasmanColors.deepTeal : TasmanColors.ice,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: dark ? TasmanColors.darkText : TasmanColors.deepOcean,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? TasmanColors.darkSurface : TasmanColors.lightSurface,
        hintStyle: TextStyle(
          color: dark
              ? TasmanColors.darkTextSecondary
              : TasmanColors.lightTextSecondary,
        ),
        labelStyle: TextStyle(
          color: dark
              ? TasmanColors.darkTextSecondary
              : TasmanColors.lightTextSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TasmanRadius.button),
          borderSide: BorderSide(
            color: dark ? TasmanColors.darkBorder : TasmanColors.lightBorder,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TasmanRadius.button),
          borderSide: BorderSide(
            color: dark ? TasmanColors.darkBorder : TasmanColors.lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TasmanRadius.button),
          borderSide: BorderSide(
            color: dark ? TasmanColors.sky : TasmanColors.ocean,
            width: 1.6,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark
            ? TasmanColors.darkOcean
            : TasmanColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TasmanRadius.sheet),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark
            ? TasmanColors.darkOcean
            : TasmanColors.lightSurface,
        modalBackgroundColor: dark
            ? TasmanColors.darkOcean
            : TasmanColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dividerTheme: DividerThemeData(
        color: dark ? TasmanColors.darkBorder : TasmanColors.lightBorder,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: dark ? TasmanColors.sky : TasmanColors.deepOcean,
        textColor: dark ? TasmanColors.darkText : TasmanColors.lightText,
      ),
    );
  }
}
