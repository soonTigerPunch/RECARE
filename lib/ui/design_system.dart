import 'package:flutter/material.dart';

abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class Corners {
  static const double field = 12;
  static const double button = 12;
  static const double dialog = 16;
}

abstract final class RecareTheme {
  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF141A23)
        : const Color(0xFFF8F9FB);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF526984),
          brightness: brightness,
        ).copyWith(
          primary: isDark ? const Color(0xFFB2C4DE) : const Color(0xFF526984),
          onPrimary: isDark ? const Color(0xFF22354D) : Colors.white,
          primaryContainer: isDark
              ? const Color(0xFF30425A)
              : const Color(0xFFE9EEF4),
          onPrimaryContainer: isDark
              ? const Color(0xFFDFE9F7)
              : const Color(0xFF3E536C),
          secondary: isDark ? const Color(0xFFB2CBB5) : const Color(0xFF526D58),
          onSecondary: isDark ? const Color(0xFF243A2A) : Colors.white,
          secondaryContainer: isDark
              ? const Color(0xFF314936)
              : const Color(0xFFEBF0EA),
          onSecondaryContainer: isDark
              ? const Color(0xFFE0EFE0)
              : const Color(0xFF33483A),
          surface: isDark ? const Color(0xFF1C2430) : Colors.white,
          onSurface: isDark ? const Color(0xFFE4E9F0) : const Color(0xFF202C3A),
          onSurfaceVariant: isDark
              ? const Color(0xFFA5B0BF)
              : const Color(0xFF647184),
          surfaceDim: isDark
              ? const Color(0xFF141A23)
              : const Color(0xFFF0F2F5),
          surfaceBright: isDark ? const Color(0xFF35404E) : Colors.white,
          surfaceContainerLowest: isDark
              ? const Color(0xFF111720)
              : Colors.white,
          surfaceContainerLow: isDark
              ? const Color(0xFF1C2430)
              : const Color(0xFFF6F8FA),
          surfaceContainer: isDark
              ? const Color(0xFF222D3A)
              : const Color(0xFFF1F4F7),
          surfaceContainerHigh: isDark
              ? const Color(0xFF2B3848)
              : const Color(0xFFEDF1F5),
          surfaceContainerHighest: isDark
              ? const Color(0xFF354252)
              : const Color(0xFFE7ECF2),
          outline: isDark ? const Color(0xFF7F8C9B) : const Color(0xFF8A95A3),
          outlineVariant: isDark
              ? const Color(0xFF364353)
              : const Color(0xFFDFE4EA),
          error: isDark ? const Color(0xFFF1B2A9) : const Color(0xFFA2453C),
          onError: isDark ? const Color(0xFF5E221B) : Colors.white,
          errorContainer: isDark
              ? const Color(0xFF67352E)
              : const Color(0xFFFCEAE7),
          onErrorContainer: isDark
              ? const Color(0xFFFFDAD4)
              : const Color(0xFF72352D),
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
    );
    final text = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: -0.7,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: -0.5,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.35,
        letterSpacing: -0.3,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.35,
        letterSpacing: -0.3,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.35,
        letterSpacing: -0.3,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: -0.2,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: -0.1,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.5,
        letterSpacing: 0,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.5,
        letterSpacing: 0,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.5,
        letterSpacing: 0,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.4,
        letterSpacing: 0,
      ),
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Corners.button),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(Corners.field),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarThemeData(
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: Space.xl,
        titleTextStyle: text.titleLarge,
        toolbarHeight: 64,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.lg,
        ),
        border: inputBorder(scheme.outlineVariant),
        enabledBorder: inputBorder(scheme.outlineVariant),
        disabledBorder: inputBorder(scheme.outlineVariant),
        focusedBorder: inputBorder(scheme.primary, 1.5),
        errorBorder: inputBorder(scheme.error),
        focusedErrorBorder: inputBorder(scheme.error, 1.5),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: text.bodyMedium?.copyWith(color: scheme.primary),
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        helperStyle: text.bodySmall,
        helperMaxLines: 3,
        errorStyle: text.bodySmall?.copyWith(color: scheme.error),
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: Space.md,
          ),
          elevation: 0,
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: Space.md,
          ),
          side: BorderSide(color: scheme.outlineVariant),
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.primaryContainer,
        disabledColor: scheme.surfaceContainer,
        labelStyle: text.bodyMedium,
        secondaryLabelStyle: text.bodyMedium?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corners.button),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.xs,
          vertical: Space.sm,
        ),
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corners.button),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corners.field),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corners.dialog),
        ),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: Space.xl,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.onSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.surface),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corners.field),
        ),
      ),
    );
  }
}
