import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/core/constants/app_typography.dart';

import 'ide_colors.dart';

/// Graphite 深色主题共享的真值常量。[IdeColors.dark] 直接复用，避免在多处
/// 重复书写同一颜色字面量。
const Color ideAccentColor = Color(0xFF1B84FF);
const Color ideWarningColor = Color(0xFFE6B450);

/// Graphite 运行时主题真源。
///
/// 这层只持有项目自己的语义 token 与字体选择；第三方主题对象由它投影生成，
/// 但不再反向成为 token 来源。
@immutable
class IdeThemeData {
  const IdeThemeData({
    required this.brightness,
    required this.colors,
    this.uiFontFamily,
    required this.codeFontFamily,
    this.uiFontSize = defaultUiFontSize,
    this.codeFontSize = defaultCodeFontSize,
  });

  final Brightness brightness;
  final IdeColors colors;
  final String? uiFontFamily;
  final String codeFontFamily;
  final double uiFontSize;
  final double codeFontSize;
}

/// 在应用根部提供 Graphite light/dark token，并在运行时解析当前有效主题。
class IdeThemeScope extends InheritedWidget {
  const IdeThemeScope({
    required this.themeMode,
    required this.lightTheme,
    required this.darkTheme,
    required super.child,
    super.key,
  });

  final ThemeMode themeMode;
  final IdeThemeData lightTheme;
  final IdeThemeData darkTheme;

  static IdeThemeScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<IdeThemeScope>();
  }

  static IdeThemeData of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('IdeThemeScope is missing.'),
        ErrorDescription(
          'Graphite token access requires IdeThemeScope above this context.',
        ),
      ]);
    }
    return scope.resolveFor(context);
  }

  IdeThemeData resolveFor(BuildContext context) {
    final platformBrightness =
        MediaQuery.maybeOf(context)?.platformBrightness ??
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final resolvedBrightness = resolveBrightnessForThemeMode(
      themeMode,
      platformBrightness: platformBrightness,
    );
    return resolvedBrightness == Brightness.dark ? darkTheme : lightTheme;
  }

  @override
  bool updateShouldNotify(covariant IdeThemeScope oldWidget) {
    return themeMode != oldWidget.themeMode ||
        lightTheme != oldWidget.lightTheme ||
        darkTheme != oldWidget.darkTheme;
  }
}

/// 解析当前 ThemeMode 对应的物理亮度；`system` 分支允许显式注入平台亮度，
/// 以便 app 根与 scope 共享同一套决策。
Brightness resolveBrightnessForThemeMode(
  ThemeMode themeMode, {
  Brightness? platformBrightness,
}) {
  final fallbackBrightness =
      platformBrightness ??
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  return switch (themeMode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system => fallbackBrightness,
  };
}

/// 将 Flutter Material 的 ThemeMode 显式映射到 `shadcn_flutter`。
sf.ThemeMode resolveShadcnThemeMode(ThemeMode themeMode) {
  return switch (themeMode) {
    ThemeMode.light => sf.ThemeMode.light,
    ThemeMode.dark => sf.ThemeMode.dark,
    ThemeMode.system => sf.ThemeMode.system,
  };
}

/// 构建 Graphite light/dark 主题数据；这是项目语义 token 的唯一装配入口。
IdeThemeData buildIdeThemeData({
  required Brightness brightness,
  String? uiFontFamily,
  required String codeFontFamily,
  double uiFontSize = defaultUiFontSize,
  double codeFontSize = defaultCodeFontSize,
}) {
  return IdeThemeData(
    brightness: brightness,
    colors: _baseIdeColorsForBrightness(brightness),
    uiFontFamily: _normalizeFontFamily(uiFontFamily),
    codeFontFamily:
        _normalizeFontFamily(codeFontFamily) ?? bundledCodeFontFamily,
    uiFontSize: uiFontSize,
    codeFontSize: codeFontSize,
  );
}

/// 将项目主题投影到 `shadcn_flutter` 根主题。
sf.ThemeData buildShadcnTheme(IdeThemeData ideTheme) {
  return sf.ThemeData(
    colorScheme: _buildShadcnColorScheme(ideTheme),
    typography: _buildShadcnTypography(ideTheme),
    // Graphite 的精确圆角继续由 IdeRadius 驱动，这里只给第三方组件一个中性基准。
    radius: 2 / 3,
    density: sf.Density.defaultDensity,
    scaling: 1,
    // Desktop IDE：固定桌面 platform，避免测试默认 android 时 popover 走 sheet。
    platform: TargetPlatform.windows,
  );
}

/// 为仍在使用 Material widget 的区域提供最小主题投影。
ThemeData buildMaterialTheme(IdeThemeData ideTheme) {
  final colors = ideTheme.colors;
  final baseTheme = ThemeData(
    brightness: ideTheme.brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: colors.frame,
    canvasColor: colors.surface,
    cardColor: colors.surface,
    dividerColor: colors.border,
    iconTheme: IconThemeData(color: colors.textSecondary),
  );
  final baseTextTheme = baseTheme.textTheme.apply(
    fontFamily: ideTheme.uiFontFamily,
    bodyColor: colors.textPrimary,
    displayColor: colors.textPrimary,
  );
  final fontSizeFactor = ideTheme.uiFontSize / defaultUiFontSize;
  return baseTheme.copyWith(
    textTheme: baseTextTheme.copyWith(
      displayLarge: _scaleTextStyle(baseTextTheme.displayLarge, fontSizeFactor),
      displayMedium: _scaleTextStyle(
        baseTextTheme.displayMedium,
        fontSizeFactor,
      ),
      displaySmall: _scaleTextStyle(baseTextTheme.displaySmall, fontSizeFactor),
      headlineLarge: _scaleTextStyle(
        baseTextTheme.headlineLarge,
        fontSizeFactor,
      ),
      headlineMedium: _scaleTextStyle(
        baseTextTheme.headlineMedium,
        fontSizeFactor,
      ),
      headlineSmall: _scaleTextStyle(
        baseTextTheme.headlineSmall,
        fontSizeFactor,
      ),
      titleLarge: _scaleTextStyle(baseTextTheme.titleLarge, fontSizeFactor),
      titleMedium: _scaleTextStyle(baseTextTheme.titleMedium, fontSizeFactor),
      titleSmall: _scaleTextStyle(baseTextTheme.titleSmall, fontSizeFactor),
      bodyLarge: _scaleTextStyle(baseTextTheme.bodyLarge, fontSizeFactor),
      bodyMedium: _scaleTextStyle(baseTextTheme.bodyMedium, fontSizeFactor),
      bodySmall: _scaleTextStyle(baseTextTheme.bodySmall, fontSizeFactor),
      labelLarge: _scaleTextStyle(baseTextTheme.labelLarge, fontSizeFactor),
      labelMedium: _scaleTextStyle(baseTextTheme.labelMedium, fontSizeFactor),
      labelSmall: _scaleTextStyle(baseTextTheme.labelSmall, fontSizeFactor),
    ),
  );
}

TextStyle? _scaleTextStyle(TextStyle? style, double factor) {
  final fontSize = style?.fontSize;
  if (style == null || fontSize == null || factor == 1) {
    return style;
  }
  return style.copyWith(fontSize: fontSize * factor);
}

IdeColors _baseIdeColorsForBrightness(Brightness brightness) {
  return brightness == Brightness.dark ? IdeColors.dark : IdeColors.light;
}

sf.ColorScheme _buildShadcnColorScheme(IdeThemeData ideTheme) {
  final colors = ideTheme.colors;
  return sf.ColorScheme(
    brightness: ideTheme.brightness,
    background: colors.frame,
    foreground: colors.textPrimary,
    card: colors.surface,
    cardForeground: colors.textPrimary,
    popover: colors.surfaceOverlay,
    popoverForeground: colors.textPrimary,
    primary: colors.accent,
    // 实心 primary 上的前景，必须用 onAccent；勿复用 accentForeground
    // （浅色选中态强调色与 accent 同蓝，会导致 Primary 按钮蓝底蓝字）。
    primaryForeground: colors.onAccent,
    secondary: colors.surfaceElevated,
    secondaryForeground: colors.textPrimary,
    muted: colors.surfaceElevated,
    mutedForeground: colors.textSecondary,
    accent: colors.primaryMuted,
    accentForeground: colors.textPrimary,
    destructive: colors.error,
    destructiveForeground: Colors.white,
    border: colors.border,
    input: colors.borderSubtle,
    ring: colors.accent,
    chart1: colors.accent,
    chart2: colors.info,
    chart3: colors.warning,
    chart4: colors.success,
    chart5: colors.error,
  );
}

sf.Typography _buildShadcnTypography(IdeThemeData ideTheme) {
  const base = sf.Typography.geist();
  final uiFontFamily = ideTheme.uiFontFamily;
  final codeFontFamily = ideTheme.codeFontFamily;
  final uiFontSizeFactor = ideTheme.uiFontSize / defaultUiFontSize;
  final codeFontSizeFactor = ideTheme.codeFontSize / defaultCodeFontSize;

  TextStyle uiStyle(TextStyle style) => _overrideTextStyle(
    style,
    fontFamily: uiFontFamily,
    fontSizeFactor: uiFontSizeFactor,
  );

  TextStyle codeStyle(TextStyle style) => _overrideTextStyle(
    style,
    fontFamily: codeFontFamily,
    fontSizeFactor: codeFontSizeFactor,
  );

  return base.copyWith(
    sans: () => uiStyle(base.sans),
    mono: () => codeStyle(base.mono),
    xSmall: () => uiStyle(base.xSmall),
    small: () => uiStyle(base.small),
    base: () => uiStyle(base.base),
    large: () => uiStyle(base.large),
    xLarge: () => uiStyle(base.xLarge),
    x2Large: () => uiStyle(base.x2Large),
    x3Large: () => uiStyle(base.x3Large),
    x4Large: () => uiStyle(base.x4Large),
    x5Large: () => uiStyle(base.x5Large),
    x6Large: () => uiStyle(base.x6Large),
    x7Large: () => uiStyle(base.x7Large),
    x8Large: () => uiStyle(base.x8Large),
    x9Large: () => uiStyle(base.x9Large),
    thin: () => uiStyle(base.thin),
    light: () => uiStyle(base.light),
    extraLight: () => uiStyle(base.extraLight),
    normal: () => uiStyle(base.normal),
    medium: () => uiStyle(base.medium),
    semiBold: () => uiStyle(base.semiBold),
    bold: () => uiStyle(base.bold),
    extraBold: () => uiStyle(base.extraBold),
    black: () => uiStyle(base.black),
    italic: () => uiStyle(base.italic),
    h1: () => uiStyle(base.h1),
    h2: () => uiStyle(base.h2),
    h3: () => uiStyle(base.h3),
    h4: () => uiStyle(base.h4),
    p: () => uiStyle(base.p),
    blockQuote: () => uiStyle(base.blockQuote),
    inlineCode: () => codeStyle(base.inlineCode),
    lead: () => uiStyle(base.lead),
    textLarge: () => uiStyle(base.textLarge),
    textSmall: () => uiStyle(base.textSmall),
    textMuted: () => uiStyle(base.textMuted),
  );
}

String? _normalizeFontFamily(String? fontFamily) {
  if (fontFamily == null) {
    return null;
  }
  final trimmed = fontFamily.trim();
  return trimmed.isEmpty ? null : trimmed;
}

TextStyle _overrideTextStyle(
  TextStyle style, {
  required String? fontFamily,
  required double fontSizeFactor,
}) {
  final normalizedFontFamily = _normalizeFontFamily(fontFamily);
  if (normalizedFontFamily == null) {
    if (fontSizeFactor == 1) {
      return style;
    }
    return style.copyWith(
      fontSize: style.fontSize == null
          ? null
          : style.fontSize! * fontSizeFactor,
    );
  }
  return TextStyle(
    inherit: style.inherit,
    color: style.color,
    backgroundColor: style.backgroundColor,
    fontSize: style.fontSize == null ? null : style.fontSize! * fontSizeFactor,
    fontWeight: style.fontWeight,
    fontStyle: style.fontStyle,
    letterSpacing: style.letterSpacing,
    wordSpacing: style.wordSpacing,
    textBaseline: style.textBaseline,
    height: style.height,
    leadingDistribution: style.leadingDistribution,
    locale: style.locale,
    foreground: style.foreground,
    background: style.background,
    shadows: style.shadows,
    fontFeatures: style.fontFeatures,
    fontVariations: style.fontVariations,
    decoration: style.decoration,
    decorationColor: style.decorationColor,
    decorationStyle: style.decorationStyle,
    decorationThickness: style.decorationThickness,
    debugLabel: style.debugLabel,
    fontFamily: normalizedFontFamily,
    fontFamilyFallback: style.fontFamilyFallback,
    package: null,
    overflow: style.overflow,
  );
}
