import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/core/constants/app_typography.dart';

import 'ide_colors.dart';

// 「Graphite」深色调色板常量：保留旧名以兼容历史代码与测试断言。运行时主题
// 通过 [IdeColors] 解析，深色实例 [IdeColors.dark] 直接复用这些常量值。
const Color ideFrameColor = Color(0xFF0A0A0B);
const Color ideSurfaceColor = Color(0xFF18191B);
const Color idePanelColor = Color(0xFF18191B);
const Color ideEditorColor = Color(0xFF141517);
const Color ideBorderColor = Color(0xFF2C2D31);
const Color ideMutedTextColor = Color(0xFF9EA1A7);
const Color ideAccentColor = Color(0xFF1B84FF);
const Color ideWarningColor = Color(0xFFE6B450);

@Deprecated('Use IdeSpacing.space8 instead.')
const double idePanelGap = 8;

@Deprecated('Use IdeRadius.small (or another IdeRadius tier) instead.')
const double idePanelRadius = 6;

@Deprecated('Use bundledCodeFontFamily or IdeTypography instead.')
const String ideFontFamily = bundledCodeFontFamily;

/// 运行时代码字体作用域。
///
/// 运行时 UI 不再依赖第三方主题对象传递代码字体，改为通过这个 scope 在 app 根部
/// 下发；测试也可直接复用它。
class IdeCodeFontScope extends InheritedWidget {
  const IdeCodeFontScope({
    required this.codeFontFamily,
    required super.child,
    super.key,
  });

  final String codeFontFamily;

  static IdeCodeFontScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<IdeCodeFontScope>();
  }

  static String? maybeCodeFontFamilyOf(BuildContext context) {
    return maybeOf(context)?.codeFontFamily;
  }

  @override
  bool updateShouldNotify(covariant IdeCodeFontScope oldWidget) {
    return oldWidget.codeFontFamily != codeFontFamily;
  }
}

/// 暴露 IDE 内专用排版信息，例如代码字体。
@immutable
class IdeTypography extends ThemeExtension<IdeTypography> {
  const IdeTypography({required this.codeFontFamily});

  final String codeFontFamily;

  static IdeTypography of(BuildContext context) {
    final runtimeCodeFontFamily = IdeCodeFontScope.maybeCodeFontFamilyOf(
      context,
    );
    if (runtimeCodeFontFamily != null) {
      return IdeTypography(codeFontFamily: runtimeCodeFontFamily);
    }

    final legacyTypography = Theme.of(context).extension<IdeTypography>();
    return legacyTypography ??
        const IdeTypography(codeFontFamily: bundledCodeFontFamily);
  }

  @override
  IdeTypography copyWith({String? codeFontFamily}) {
    return IdeTypography(codeFontFamily: codeFontFamily ?? this.codeFontFamily);
  }

  @override
  IdeTypography lerp(covariant ThemeExtension<IdeTypography>? other, double t) {
    if (other is! IdeTypography) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

/// 解析当前 ThemeMode 对应的物理亮度，用于旧 Material theme / extension 的兜底。
Brightness resolveBrightnessForThemeMode(ThemeMode themeMode) {
  return switch (themeMode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
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

/// 根据亮度构建 `shadcn_flutter` 根主题。
sf.ThemeData buildShadcnTheme({
  required Brightness brightness,
  String? uiFontFamily,
  required String codeFontFamily,
}) {
  final colors = _baseIdeColorsForBrightness(brightness);
  return sf.ThemeData(
    colorScheme: shadcnColorSchemeFromIdeColors(colors, brightness: brightness),
    typography: _buildShadcnTypography(
      uiFontFamily: uiFontFamily,
      codeFontFamily: codeFontFamily,
    ),
    // Graphite 的精确圆角仍由 IdeRadius 驱动，这里只给第三方组件一个中性基准。
    radius: 2 / 3,
    density: sf.Density.defaultDensity,
    scaling: 1,
  );
}

/// 为现有 Material widget / ThemeExtension 提供最小主题承载。
ThemeData buildMaterialTheme({
  required Brightness brightness,
  String? uiFontFamily,
  required String codeFontFamily,
}) {
  final colors = _baseIdeColorsForBrightness(brightness);
  final baseTheme = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: colors.frame,
    canvasColor: colors.surface,
    cardColor: colors.surface,
    dividerColor: colors.border,
    iconTheme: IconThemeData(color: colors.textSecondary),
  );
  return baseTheme.copyWith(
    textTheme: baseTheme.textTheme.apply(
      fontFamily: uiFontFamily,
      bodyColor: colors.textPrimary,
      displayColor: colors.textPrimary,
    ),
    extensions: <ThemeExtension<dynamic>>[
      colors,
      IdeTypography(codeFontFamily: codeFontFamily),
    ],
  );
}

IdeColors _baseIdeColorsForBrightness(Brightness brightness) {
  return brightness == Brightness.dark ? IdeColors.dark : IdeColors.light;
}

sf.ColorScheme shadcnColorSchemeFromIdeColors(
  IdeColors colors, {
  required Brightness brightness,
}) {
  return sf.ColorScheme(
    brightness: brightness,
    background: colors.frame,
    foreground: colors.textPrimary,
    card: colors.surface,
    cardForeground: colors.textPrimary,
    popover: colors.surfaceOverlay,
    popoverForeground: colors.textPrimary,
    primary: colors.accent,
    primaryForeground: colors.accentForeground,
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

sf.Typography _buildShadcnTypography({
  String? uiFontFamily,
  required String codeFontFamily,
}) {
  const base = sf.Typography.geist();
  return base.copyWith(
    sans: () => _overrideFontFamily(base.sans, uiFontFamily),
    mono: () => _overrideFontFamily(base.mono, codeFontFamily),
    xSmall: () => _overrideFontFamily(base.xSmall, uiFontFamily),
    small: () => _overrideFontFamily(base.small, uiFontFamily),
    base: () => _overrideFontFamily(base.base, uiFontFamily),
    large: () => _overrideFontFamily(base.large, uiFontFamily),
    xLarge: () => _overrideFontFamily(base.xLarge, uiFontFamily),
    x2Large: () => _overrideFontFamily(base.x2Large, uiFontFamily),
    x3Large: () => _overrideFontFamily(base.x3Large, uiFontFamily),
    x4Large: () => _overrideFontFamily(base.x4Large, uiFontFamily),
    x5Large: () => _overrideFontFamily(base.x5Large, uiFontFamily),
    x6Large: () => _overrideFontFamily(base.x6Large, uiFontFamily),
    x7Large: () => _overrideFontFamily(base.x7Large, uiFontFamily),
    x8Large: () => _overrideFontFamily(base.x8Large, uiFontFamily),
    x9Large: () => _overrideFontFamily(base.x9Large, uiFontFamily),
    thin: () => _overrideFontFamily(base.thin, uiFontFamily),
    light: () => _overrideFontFamily(base.light, uiFontFamily),
    extraLight: () => _overrideFontFamily(base.extraLight, uiFontFamily),
    normal: () => _overrideFontFamily(base.normal, uiFontFamily),
    medium: () => _overrideFontFamily(base.medium, uiFontFamily),
    semiBold: () => _overrideFontFamily(base.semiBold, uiFontFamily),
    bold: () => _overrideFontFamily(base.bold, uiFontFamily),
    extraBold: () => _overrideFontFamily(base.extraBold, uiFontFamily),
    black: () => _overrideFontFamily(base.black, uiFontFamily),
    italic: () => _overrideFontFamily(base.italic, uiFontFamily),
    h1: () => _overrideFontFamily(base.h1, uiFontFamily),
    h2: () => _overrideFontFamily(base.h2, uiFontFamily),
    h3: () => _overrideFontFamily(base.h3, uiFontFamily),
    h4: () => _overrideFontFamily(base.h4, uiFontFamily),
    p: () => _overrideFontFamily(base.p, uiFontFamily),
    blockQuote: () => _overrideFontFamily(base.blockQuote, uiFontFamily),
    inlineCode: () => _overrideFontFamily(base.inlineCode, codeFontFamily),
    lead: () => _overrideFontFamily(base.lead, uiFontFamily),
    textLarge: () => _overrideFontFamily(base.textLarge, uiFontFamily),
    textSmall: () => _overrideFontFamily(base.textSmall, uiFontFamily),
    textMuted: () => _overrideFontFamily(base.textMuted, uiFontFamily),
  );
}

TextStyle _overrideFontFamily(TextStyle style, String? fontFamily) {
  if (fontFamily == null || fontFamily.isEmpty) {
    return style;
  }
  return TextStyle(
    inherit: style.inherit,
    color: style.color,
    backgroundColor: style.backgroundColor,
    fontSize: style.fontSize,
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
    fontFamily: fontFamily,
    fontFamilyFallback: style.fontFamilyFallback,
    package: null,
    overflow: style.overflow,
  );
}
