import 'package:flutter/material.dart';

enum AppThemeMode { light, sepia, dark, amoled }

/// Maps a Material color scheme brightness to the nearest paper mode.
AppThemeMode themeModeOf(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark ? AppThemeMode.dark : AppThemeMode.light;

class PaperPalette {
  final Color canvas;
  final Color surface;
  final Color surfaceHigh;
  final Color text;
  final Color textSecondary;
  final Color accent;
  final Color accentContainer;
  final Color highlightDefault;
  final Color border;

  const PaperPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceHigh,
    required this.text,
    required this.textSecondary,
    required this.accent,
    required this.accentContainer,
    required this.highlightDefault,
    required this.border,
  });

  // Research-based warm paper palettes (see README for sources).
  static const light = PaperPalette(
    canvas: Color(0xFFFFFDF8), // ivory
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF4F1E9),
    text: Color(0xFF141414), // warm charcoal
    textSecondary: Color(0xFF646059),
    accent: Color(0xFF825500), // sepia-brown seed
    accentContainer: Color(0xFFFFDCB4),
    highlightDefault: Color(0x66FFEB3B),
    border: Color(0xFFE5E5E0),
  );

  static const sepia = PaperPalette(
    canvas: Color(0xFFF8F1E3), // parchment
    surface: Color(0xFFF0E6D6), // papyrus
    surfaceHigh: Color(0xFFE6D9C3),
    text: Color(0xFF222222),
    textSecondary: Color(0xFF646059),
    accent: Color(0xFF3366CC), // ink-blue links, brand accent
    accentContainer: Color(0xFFD6E2FF),
    highlightDefault: Color(0x66FFD54F),
    border: Color(0xFFDDD3BF),
  );

  static const dark = PaperPalette(
    canvas: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    surfaceHigh: Color(0xFF2C2C2C),
    text: Color(0xFFE1E1E1),
    textSecondary: Color(0xFFB0B0B0),
    accent: Color(0xFFFFC87A), // warm, desaturated up for dark
    accentContainer: Color(0xFF4A3A20),
    highlightDefault: Color(0x80FFD54F),
    border: Color(0x1AFFFFFF), // white @ ~10%
  );

  static const amoled = PaperPalette(
    canvas: Color(0xFF000000),
    surface: Color(0xFF121212),
    surfaceHigh: Color(0xFF1E1E1E),
    text: Color(0xFFE1E1E1),
    textSecondary: Color(0xFF9E9E9E),
    accent: Color(0xFFFFC87A),
    accentContainer: Color(0xFF4A3A20),
    highlightDefault: Color(0x80FFD54F),
    border: Color(0x1AFFFFFF),
  );

  static PaperPalette of(AppThemeMode mode) => switch (mode) {
        AppThemeMode.light => light,
        AppThemeMode.sepia => sepia,
        AppThemeMode.dark => dark,
        AppThemeMode.amoled => amoled,
      };
}

class AppTheme {
  static ThemeData build(AppThemeMode mode) {
    final p = PaperPalette.of(mode);
    final brightness = (mode == AppThemeMode.dark || mode == AppThemeMode.amoled)
        ? Brightness.dark
        : Brightness.light;

    final scheme = ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: brightness,
      surface: p.surface,
    ).copyWith(
      surface: p.surface,
      onSurface: p.text,
      onSurfaceVariant: p.textSecondary,
      outline: p.border,
      primary: p.accent,
      primaryContainer: p.accentContainer,
      onPrimary: brightness == Brightness.dark ? p.canvas : Colors.white,
      onPrimaryContainer: p.text,
      secondary: p.accent,
      onSecondary: p.canvas,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: p.canvas,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.accentContainer,
        selectedIconTheme: IconThemeData(color: p.accent),
        selectedLabelTextStyle: TextStyle(
            color: p.text, fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(color: p.textSecondary, fontSize: 12),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.border, width: 1),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.accent, width: 2),
        ),
      ),
      textTheme: base.textTheme
          .apply(
            bodyColor: p.text,
            displayColor: p.text,
          )
          .copyWith(
            bodyLarge: const TextStyle(fontSize: 17, height: 1.5),
            bodyMedium: const TextStyle(fontSize: 16, height: 1.5),
          ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: p.text, fontSize: 13),
      ),
    );
  }
}
