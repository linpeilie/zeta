import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:zeta/src/core/constants/app_typography.dart';

import 'ide_colors.dart';
import 'ide_text_styles.dart';

// 深色调色板常量：保留旧名以兼容历史代码与测试断言。运行时主题通过
// [IdeColors] 扩展解析，深色实例 [IdeColors.dark] 直接复用这些常量值。
const Color ideFrameColor = Color(0xFF171717);
const Color ideSurfaceColor = Color(0xFF1F1F1F);
const Color idePanelColor = Color(0xFF242424);
const Color ideEditorColor = Color(0xFF191919);
const Color ideBorderColor = Color(0xFF343434);
const Color ideMutedTextColor = Color(0xFF9DA3A6);
const Color ideAccentColor = Color(0xFF4FB286);
const Color ideWarningColor = Color(0xFFE6B450);

const double idePanelGap = 8;
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
  return ShadThemeData(
    brightness: brightness,
    colorScheme: shadColorSchemeFromIdeColors(colors, brightness: brightness),
    radius: const BorderRadius.all(Radius.circular(idePanelRadius)),
    textTheme: IdeTextStyles.buildShadTextTheme(
      colors: colors,
      uiFontFamily: uiFontFamily,
      codeFontFamily: codeFontFamily,
    ),
    popoverTheme: ShadPopoverTheme(
      decoration: ShadDecoration(
        color: colors.surfaceOverlay,
        border: ShadBorder.all(color: colors.border, width: 1),
      ),
    ),
    primaryDialogTheme: ShadDialogTheme(
      backgroundColor: colors.surfaceOverlay,
      border: Border.all(color: colors.border),
    ),
    alertDialogTheme: ShadDialogTheme(
      backgroundColor: colors.surfaceOverlay,
      border: Border.all(color: colors.border),
    ),
    primaryToastTheme: ShadToastTheme(
      backgroundColor: colors.surfaceElevated,
      border: ShadBorder.all(color: colors.border, width: 1),
    ),
    destructiveToastTheme: ShadToastTheme(
      backgroundColor: colors.surfaceElevated,
      border: ShadBorder.all(color: colors.border, width: 1),
    ),
  );
}

IdeColors _baseIdeColorsForBrightness(Brightness brightness) {
  return brightness == Brightness.dark ? IdeColors.dark : IdeColors.light;
}
