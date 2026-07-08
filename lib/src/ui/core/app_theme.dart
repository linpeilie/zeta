import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:zeta/src/core/constants/app_typography.dart';

import 'ide_colors.dart';
import 'ide_effects.dart';
import 'ide_text_styles.dart';

// 「Graphite」深色调色板常量：保留旧名以兼容历史代码与测试断言。运行时主题
// 通过 [IdeColors] 扩展解析，深色实例 [IdeColors.dark] 直接复用这些常量值。
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
/// 运行时 UI 不再依赖 Material ThemeExtension 传递代码字体，改为通过这个
/// scope 在 app 根部下发；测试也可直接复用它。
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

/// 根据亮度构建 shadcn 主题。
ShadThemeData buildShadTheme({
  required Brightness brightness,
  String? uiFontFamily,
  required String codeFontFamily,
}) {
  final colors = _baseIdeColorsForBrightness(brightness);
  final isDark = brightness == Brightness.dark;
  // ghost 按钮 / option 行的 hover 背景与 PaneInteractiveSurface 保持一致。
  final hoverBackground = colors.border.withValues(alpha: isDark ? 0.18 : 0.3);
  return ShadThemeData(
    brightness: brightness,
    colorScheme: shadColorSchemeFromIdeColors(colors, brightness: brightness),
    radius: IdeRadius.allMedium,
    textTheme: IdeTextStyles.buildShadTextTheme(
      colors: colors,
      uiFontFamily: uiFontFamily,
      codeFontFamily: codeFontFamily,
    ),
    ghostButtonTheme: ShadButtonTheme(
      foregroundColor: colors.textSecondary,
      hoverForegroundColor: colors.textPrimary,
      hoverBackgroundColor: hoverBackground,
      pressedBackgroundColor: colors.border.withValues(
        alpha: isDark ? 0.28 : 0.4,
      ),
      pressedForegroundColor: colors.textPrimary,
    ),
    optionTheme: ShadOptionTheme(
      radius: IdeRadius.allSmall,
      hoveredBackgroundColor: hoverBackground,
      selectedBackgroundColor: colors.primaryMuted,
    ),
    popoverTheme: ShadPopoverTheme(
      decoration: ShadDecoration(
        color: colors.surfaceOverlay,
        border: ShadBorder.all(
          color: colors.border,
          width: 1,
          radius: IdeRadius.allLarge,
        ),
        shadows: IdeEffects.overlayShadow(brightness),
      ),
    ),
    primaryDialogTheme: ShadDialogTheme(
      backgroundColor: colors.surfaceOverlay,
      border: Border.all(color: colors.border),
      radius: IdeRadius.allLarge,
      shadows: IdeEffects.overlayShadow(brightness),
    ),
    alertDialogTheme: ShadDialogTheme(
      backgroundColor: colors.surfaceOverlay,
      border: Border.all(color: colors.border),
      radius: IdeRadius.allLarge,
      shadows: IdeEffects.overlayShadow(brightness),
    ),
    primaryToastTheme: ShadToastTheme(
      backgroundColor: colors.surfaceElevated,
      border: ShadBorder.all(color: colors.border, width: 1),
      radius: IdeRadius.allMedium,
      shadows: IdeEffects.overlayShadow(brightness),
    ),
    destructiveToastTheme: ShadToastTheme(
      backgroundColor: colors.surfaceElevated,
      border: ShadBorder.all(color: colors.border, width: 1),
      radius: IdeRadius.allMedium,
      shadows: IdeEffects.overlayShadow(brightness),
    ),
  );
}

IdeColors _baseIdeColorsForBrightness(Brightness brightness) {
  return brightness == Brightness.dark ? IdeColors.dark : IdeColors.light;
}
