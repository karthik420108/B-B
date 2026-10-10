import 'package:flutter/material.dart';

/// Material 3 themes for the Health Wallet app (light + dark)
/// Redesigned to match a minimalist, high-contrast, premium aesthetic.
class AppTheme {
  AppTheme._();

  static const Color primaryText = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF666666);
  static const Color background = Color(0xFFF7F7F7);
  static const Color cardBackground = Colors.white;

  // The gradient used for premium/primary actions (derived from inspiration)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF8B92BA), Color(0xFFC780A8)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF111111),
      brightness: brightness,
      surface: isLight ? background : const Color(0xFF111111),
      onSurface: isLight ? primaryText : Colors.white,
      primary: isLight ? primaryText : Colors.white,
      onPrimary: isLight ? Colors.white : primaryText,
      surfaceContainerLow: isLight ? cardBackground : const Color(0xFF222222),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -1.0, height: 1.2),
        headlineMedium: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.2),
        headlineSmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.2),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleMedium: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleSmall: TextStyle(fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(fontWeight: FontWeight.w500, color: secondaryText),
        bodyMedium: TextStyle(fontWeight: FontWeight.w500, color: secondaryText),
        bodySmall: TextStyle(fontWeight: FontWeight.w500, color: secondaryText),
        labelLarge: TextStyle(fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: isLight ? const BorderSide(color: Color(0xFFEAEAEA), width: 1) : BorderSide.none,
        ),
        color: scheme.surfaceContainerLow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD0D0D0), width: 1),
        ),
        filled: true,
        fillColor: isLight ? Colors.white : const Color(0xFF2A2A2A),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 56),
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 56),
          side: BorderSide(color: scheme.outline.withOpacity(0.2), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          foregroundColor: scheme.onSurface,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: scheme.onSurface,
        contentTextStyle: TextStyle(color: scheme.surface, fontWeight: FontWeight.w500),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary);
          }
          return TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: scheme.primary.withOpacity(0.5));
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(size: 26, color: scheme.primary);
          }
          return IconThemeData(size: 26, color: scheme.primary.withOpacity(0.5));
        }),
      ),
      dividerTheme: const DividerThemeData(space: 1, thickness: 1, color: Color(0xFFEAEAEA)),
    );
  }
}