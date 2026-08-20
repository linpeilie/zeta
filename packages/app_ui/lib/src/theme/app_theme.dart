import 'package:app_ui/src/theme/app_colors.dart';
import 'package:app_ui/src/theme/app_effects.dart';
import 'package:app_ui/src/theme/app_metrics.dart';
import 'package:app_ui/src/theme/app_motion.dart';
import 'package:app_ui/src/theme/app_radii.dart';
import 'package:app_ui/src/theme/app_spacing.dart';
import 'package:app_ui/src/theme/app_text_styles.dart';
import 'package:app_ui/src/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Single source of truth for Zeta's Material and shadcn theme projections.
abstract final class AppTheme {
  /// Default light Material theme.
  static ThemeData get light => material(brightness: Brightness.light);

  /// Default dark Material theme.
  static ThemeData get dark => material(brightness: Brightness.dark);

  /// Default light shadcn theme.
  static sf.ThemeData get shadcnLight => shadcn(brightness: Brightness.light);

  /// Default dark shadcn theme.
  static sf.ThemeData get shadcnDark => shadcn(brightness: Brightness.dark);

  /// Builds a Material theme from the shared semantic tokens.
  static ThemeData material({
    required Brightness brightness,
    String? uiFontFamily = bundledUiFontFamily,
    List<String> uiFontFamilyFallback = const <String>[],
    String codeFontFamily = bundledCodeFontFamily,
    double uiFontSize = defaultUiFontSize,
    double codeFontSize = defaultCodeFontSize,
  }) {
    final colors = _colorsFor(brightness);
    final typography = AppTypography.resolve(
      colors: colors,
      uiFontFamily: uiFontFamily,
      uiFontFamilyFallback: uiFontFamilyFallback,
      codeFontFamily: codeFontFamily,
      uiFontSize: uiFontSize,
      codeFontSize: codeFontSize,
    );
    final baseScheme = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: brightness,
    );
    final colorScheme = baseScheme.copyWith(
      primary: colors.accent,
      onPrimary: colors.onAccent,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      error: colors.error,
      onError: Colors.white,
      outline: colors.border,
      outlineVariant: colors.borderSubtle,
    );

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.frameSurface,
      canvasColor: colors.canvasSurface,
      cardColor: colors.paneSurface,
      dividerColor: colors.border,
      focusColor: colors.focusRing,
      hoverColor: colors.hoverSurface,
      iconTheme: IconThemeData(color: colors.textSecondary),
      textTheme: _materialTextTheme(typography),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: <ThemeExtension<dynamic>>[
        colors,
        const AppSpacing(),
        const AppMetrics(),
        const AppRadii(),
        const AppEffects(),
        const AppMotion(),
        typography,
        const AppTextStyles(),
      ],
    );
  }

  /// Builds the matching shadcn theme from the same token source.
  static sf.ThemeData shadcn({
    required Brightness brightness,
    String? uiFontFamily = bundledUiFontFamily,
    List<String> uiFontFamilyFallback = const <String>[],
    String codeFontFamily = bundledCodeFontFamily,
    double uiFontSize = defaultUiFontSize,
    double codeFontSize = defaultCodeFontSize,
  }) {
    final colors = _colorsFor(brightness);
    final typography = AppTypography.resolve(
      colors: colors,
      uiFontFamily: uiFontFamily,
      uiFontFamilyFallback: uiFontFamilyFallback,
      codeFontFamily: codeFontFamily,
      uiFontSize: uiFontSize,
      codeFontSize: codeFontSize,
    );
    return sf.ThemeData(
      colorScheme: _shadcnColorScheme(brightness, colors),
      typography: _shadcnTypography(
        typography,
        uiFontFamily: uiFontFamily,
        uiFontFamilyFallback: uiFontFamilyFallback,
        codeFontFamily: codeFontFamily,
      ),
      density: const sf.Density(
        baseContainerPadding: 16,
        baseGap: 10,
        baseContentPadding: 16,
      ),
      platform: TargetPlatform.windows,
    );
  }
}

AppColors _colorsFor(Brightness brightness) {
  return brightness == Brightness.dark ? AppColors.dark : AppColors.light;
}

TextTheme _materialTextTheme(AppTypography typography) {
  return TextTheme(
    displayLarge: typography.displayLarge,
    displaySmall: typography.displaySmall,
    titleLarge: typography.titleLarge,
    titleSmall: typography.titleSmall,
    bodyMedium: typography.bodyMedium,
    bodySmall: typography.bodySmall,
    labelMedium: typography.caption,
    headlineSmall: typography.pageTitle,
  );
}

sf.ColorScheme _shadcnColorScheme(
  Brightness brightness,
  AppColors colors,
) {
  final base = brightness == Brightness.dark
      ? sf.ColorSchemes.darkZinc
      : sf.ColorSchemes.lightZinc;
  return base.copyWith(
    background: () => colors.frameSurface,
    foreground: () => colors.textPrimary,
    card: () => colors.paneSurface,
    cardForeground: () => colors.textPrimary,
    popover: () => colors.popoverSurface,
    popoverForeground: () => colors.textPrimary,
    primary: () => colors.accent,
    primaryForeground: () => colors.onAccent,
    secondary: () => colors.controlSurface,
    secondaryForeground: () => colors.textPrimary,
    muted: () => colors.controlSurface,
    mutedForeground: () => colors.textSecondary,
    accent: () => colors.selectedSurface,
    accentForeground: () => colors.textPrimary,
    destructive: () => colors.error,
    destructiveForeground: () => sf.Colors.white,
    border: () => colors.border,
    input: () => colors.borderSubtle,
    ring: () => colors.focusRing,
    chart1: () => colors.accent,
    chart2: () => colors.info,
    chart3: () => colors.warning,
    chart4: () => colors.success,
    chart5: () => colors.error,
  );
}

sf.Typography _shadcnTypography(
  AppTypography appTypography, {
  required String? uiFontFamily,
  required List<String> uiFontFamilyFallback,
  required String codeFontFamily,
}) {
  const base = sf.Typography.geist();

  TextStyle uiStyle(TextStyle style) => style.copyWith(
    fontFamily: uiFontFamily,
    fontFamilyFallback: uiFontFamilyFallback,
  );
  TextStyle codeStyle(TextStyle style) => style.copyWith(
    fontFamily: codeFontFamily,
    fontFamilyFallback: uiFontFamilyFallback,
  );
  TextStyle sized(TextStyle style, TextStyle token) => uiStyle(
    style,
  ).copyWith(fontSize: token.fontSize, height: token.height);

  return base.copyWith(
    sans: () => uiStyle(base.sans),
    mono: () => codeStyle(base.mono),
    xSmall: () => sized(base.xSmall, appTypography.caption),
    small: () => sized(base.small, appTypography.bodySmall),
    base: () => sized(base.base, appTypography.bodyMedium),
    inlineCode: () => codeStyle(base.inlineCode),
  );
}
