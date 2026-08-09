import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/core/constants/app_typography.dart';

import 'ide_colors.dart';

/// IDE 运行时主题真源。
///
/// 语义色来自 [IdeColors]（由 `shadcn_flutter` Zinc / blue 色板映射）；
/// 本层持有语义 token 与字体选择，再投影为 Material / shadcn 主题。
///
/// 装配入口：[buildIdeThemeData]（`MainApp` / 外观设置变更时重建 light/dark）。
/// 消费入口：`IdeThemeScope.of` → `IdeColors.of` / `IdeTextStyles.of`，
/// 以及 [buildShadcnTheme] / [buildMaterialTheme] 投影。
@immutable
class IdeThemeData {
  const IdeThemeData({
    required this.brightness,
    required this.colors,
    this.uiFontFamily,
    this.uiFontFamilyFallback = const <String>[],
    required this.codeFontFamily,
    this.uiFontSize = defaultUiFontSize,
    this.codeFontSize = defaultCodeFontSize,
  });

  /// 物理亮度（light/dark），与 [IdeColors.light] / [IdeColors.dark] 对应。
  final Brightness brightness;

  /// 当前亮度下的语义调色板。
  ///
  /// 生效位置：全应用 `IdeColors.of(context)`；并投影到 Material/shadcn。
  final IdeColors colors;

  /// 已解析的 UI 主字体族；`null` 表示由平台字体引擎选择默认字体。
  ///
  /// 生效位置：`IdeTextStyles` 非代码样式；Material / shadcn 的 sans 字体投影。
  /// 来源：外观设置 `AppearanceSettings.uiFontFamily`；系统默认选项会映射为
  /// 当前平台稳定公开的 UI 字体。
  final String? uiFontFamily;

  /// 当前平台的 UI 备用字体族，主要承接主字体缺失的中日韩字符。
  ///
  /// 生效位置：`IdeTextStyles`、Material 与 shadcn 的所有文本样式。
  /// 系统默认字体不再继承 GeistSans，而是由平台默认字体配合此列表解析。
  final List<String> uiFontFamilyFallback;

  /// 代码字体族（默认 [bundledCodeFontFamily]）。
  ///
  /// 生效位置：`IdeTextStyles` 的 code* 样式；shadcn mono / inlineCode。
  /// 来源：外观设置 `AppearanceSettings.codeFontFamily`。
  final String codeFontFamily;

  /// UI 基准字号（逻辑 px），驱动界面排版整体缩放。
  ///
  /// 生效位置：`IdeTextStyles` UI 字号；Material/shadcn UI 字号 factor。
  /// 来源：外观设置 `uiFontSize`（设置页滑块，范围见 `minUiFontSize` 等）。
  final double uiFontSize;

  /// 代码基准字号（逻辑 px），驱动代码排版缩放。
  ///
  /// 生效位置：`IdeTextStyles` code* 字号；shadcn mono 字号 factor。
  final double codeFontSize;
}

/// 在应用根部提供 Graphite light/dark token，并在运行时解析当前有效主题。
///
/// 生效位置：`MainApp` 根部包裹；子树通过 [of] / [maybeOf] 读取。
/// [themeMode] 来自外观设置，决定 system/light/dark 如何映射到 light/dark 主题。
class IdeThemeScope extends InheritedWidget {
  const IdeThemeScope({
    required this.themeMode,
    required this.lightTheme,
    required this.darkTheme,
    required super.child,
    super.key,
  });

  /// 用户选择的主题模式（含 system）。
  final ThemeMode themeMode;

  /// 浅色 Graphite 主题数据。
  final IdeThemeData lightTheme;

  /// 深色 Graphite 主题数据。
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

/// 返回当前平台用于承接中日韩字符的系统 UI 字体顺序。
///
/// 首选字体仍由系统或用户设置决定；列表仅在首选字体缺少字符时生效。
List<String> resolvePlatformUiFontFamilyFallback(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.windows => const <String>[
      'Microsoft YaHei UI',
      'Microsoft YaHei',
    ],
    TargetPlatform.macOS ||
    TargetPlatform.iOS => const <String>['PingFang SC', 'Hiragino Sans GB'],
    TargetPlatform.linux => const <String>[
      'Noto Sans CJK SC',
      'Noto Sans SC',
      'WenQuanYi Micro Hei',
    ],
    TargetPlatform.android || TargetPlatform.fuchsia => const <String>[
      'Noto Sans CJK SC',
      'Noto Sans SC',
    ],
  };
}

/// 返回平台稳定公开的系统 UI 主字体；没有稳定名称的平台交给引擎解析。
String? resolvePlatformUiFontFamily(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.windows => 'Segoe UI',
    TargetPlatform.macOS || TargetPlatform.iOS => '.AppleSystemUIFont',
    TargetPlatform.linux ||
    TargetPlatform.android ||
    TargetPlatform.fuchsia => null,
  };
}

/// 构建 Graphite light/dark 主题数据；这是项目语义 token 的唯一装配入口。
///
/// 生效位置：`MainApp` 根据 `AppearanceSettings` 分别构建 light/dark 实例，
/// 再交给 [IdeThemeScope]。颜色始终来自 [IdeColors.light]/[IdeColors.dark]，
/// 字体与字号来自参数（用户可改）。
IdeThemeData buildIdeThemeData({
  required Brightness brightness,
  String? uiFontFamily,
  required String codeFontFamily,
  double uiFontSize = defaultUiFontSize,
  double codeFontSize = defaultCodeFontSize,
  TargetPlatform? platform,
}) {
  final resolvedPlatform = platform ?? defaultTargetPlatform;
  // 「跟随应用默认」解析到内置 Geist，而不是平台系统字体：这样老用户持久化的
  // systemDefault 无需迁移即可获得新默认字体，显式选了系统字体的用户不受影响。
  final resolvedUiFontFamily =
      _normalizeFontFamily(uiFontFamily) ?? bundledUiFontFamily;
  return IdeThemeData(
    brightness: brightness,
    colors: _baseIdeColorsForBrightness(brightness),
    uiFontFamily: resolvedUiFontFamily,
    uiFontFamilyFallback: resolvePlatformUiFontFamilyFallback(resolvedPlatform),
    codeFontFamily:
        _normalizeFontFamily(codeFontFamily) ?? bundledCodeFontFamily,
    uiFontSize: uiFontSize,
    codeFontSize: codeFontSize,
  );
}

/// 将项目主题投影到 `shadcn_flutter` 根主题。
///
/// 生效位置：`MainApp` 中 `sf.Theme`；影响 shadcn 按钮、输入、Popover、
/// Toast 等第三方组件的颜色与字体。精确圆角仍由 [IdeRadius] 驱动。
sf.ThemeData buildShadcnTheme(IdeThemeData ideTheme) {
  return sf.ThemeData(
    colorScheme: _buildShadcnColorScheme(ideTheme),
    typography: _buildShadcnTypography(ideTheme),
    // IDE 精确圆角继续由 IdeRadius 驱动，这里只给第三方组件一个中性基准。
    radius: 2 / 3,
    density: sf.Density.defaultDensity,
    scaling: 1,
    // Desktop IDE：固定桌面 platform，避免测试默认 android 时 popover 走 sheet。
    platform: TargetPlatform.windows,
  );
}

/// 为仍在使用 Material widget 的区域提供最小主题投影。
///
/// 生效位置：`MainApp` 中 `sf.ShadcnApp` 的 `materialTheme:`（应用没有
/// `MaterialApp`）；覆盖 shadcn 内部与少量残留 Material widget 的背景、
/// 图标色、分隔线、hover/focus 等默认样式。
ThemeData buildMaterialTheme(IdeThemeData ideTheme) {
  final colors = ideTheme.colors;
  final baseTheme = ThemeData(
    brightness: ideTheme.brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: colors.frameSurface,
    canvasColor: colors.canvasSurface,
    cardColor: colors.paneSurface,
    dividerColor: colors.border,
    focusColor: colors.focusRing,
    hoverColor: colors.hoverSurface,
    iconTheme: IconThemeData(color: colors.textSecondary),
  );
  final baseTextTheme = baseTheme.textTheme.apply(
    bodyColor: colors.textPrimary,
    displayColor: colors.textPrimary,
  );
  final fontSizeFactor = ideTheme.uiFontSize / defaultUiFontSize;

  TextStyle? uiStyle(TextStyle? style) {
    if (style == null) {
      return null;
    }
    return _overrideTextStyle(
      style,
      fontFamily: ideTheme.uiFontFamily,
      fontFamilyFallback: ideTheme.uiFontFamilyFallback,
      fontSizeFactor: fontSizeFactor,
    );
  }

  TextTheme uiTextTheme(TextTheme textTheme) {
    return textTheme.copyWith(
      displayLarge: uiStyle(textTheme.displayLarge),
      displayMedium: uiStyle(textTheme.displayMedium),
      displaySmall: uiStyle(textTheme.displaySmall),
      headlineLarge: uiStyle(textTheme.headlineLarge),
      headlineMedium: uiStyle(textTheme.headlineMedium),
      headlineSmall: uiStyle(textTheme.headlineSmall),
      titleLarge: uiStyle(textTheme.titleLarge),
      titleMedium: uiStyle(textTheme.titleMedium),
      titleSmall: uiStyle(textTheme.titleSmall),
      bodyLarge: uiStyle(textTheme.bodyLarge),
      bodyMedium: uiStyle(textTheme.bodyMedium),
      bodySmall: uiStyle(textTheme.bodySmall),
      labelLarge: uiStyle(textTheme.labelLarge),
      labelMedium: uiStyle(textTheme.labelMedium),
      labelSmall: uiStyle(textTheme.labelSmall),
    );
  }

  return baseTheme.copyWith(
    textTheme: uiTextTheme(baseTextTheme),
    primaryTextTheme: uiTextTheme(baseTheme.primaryTextTheme),
  );
}

IdeColors _baseIdeColorsForBrightness(Brightness brightness) {
  return brightness == Brightness.dark ? IdeColors.dark : IdeColors.light;
}

/// 以官方 Zinc + blue 方案为基线，再用 IDE 语义表面覆盖分层字段。
///
/// 这样 shadcn 控件与 [IdeColors] 共用同一套 zinc / blue / status 色源，
/// 同时保留 IDE 需要的 canvas / pane / popover 层级。
sf.ColorScheme _buildShadcnColorScheme(IdeThemeData ideTheme) {
  final colors = ideTheme.colors;
  final base = ideTheme.brightness == Brightness.dark
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
    // 实心 primary 上的前景，必须用 onAccent；勿复用 accentForeground
    // （浅色选中态强调色与 accent 同蓝，会导致 Primary 按钮蓝底蓝字）。
    primaryForeground: () => colors.onAccent,
    secondary: () => colors.controlSurface,
    secondaryForeground: () => colors.textPrimary,
    muted: () => colors.controlSurface,
    mutedForeground: () => colors.textSecondary,
    // shadcn 的 accent 在 Zeta 中表达普通选中，而不是品牌蓝。
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

sf.Typography _buildShadcnTypography(IdeThemeData ideTheme) {
  const base = sf.Typography.geist();
  final uiFontFamily = ideTheme.uiFontFamily;
  final codeFontFamily = ideTheme.codeFontFamily;
  final uiFontSizeFactor = ideTheme.uiFontSize / defaultUiFontSize;
  final codeFontSizeFactor = ideTheme.codeFontSize / defaultCodeFontSize;

  TextStyle uiStyle(TextStyle style) => _overrideTextStyle(
    style,
    fontFamily: uiFontFamily,
    fontFamilyFallback: ideTheme.uiFontFamilyFallback,
    fontSizeFactor: uiFontSizeFactor,
  );

  TextStyle codeStyle(TextStyle style) => _overrideTextStyle(
    style,
    fontFamily: codeFontFamily,
    fontFamilyFallback: ideTheme.uiFontFamilyFallback,
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
  required List<String> fontFamilyFallback,
  required double fontSizeFactor,
}) {
  final normalizedFontFamily = _normalizeFontFamily(fontFamily);
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
    fontFamilyFallback: fontFamilyFallback,
    package: null,
    overflow: style.overflow,
  );
}
