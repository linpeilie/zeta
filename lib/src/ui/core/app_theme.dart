import 'package:flutter/material.dart';

import 'ide_colors.dart';

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
const String ideFontFamily = 'JetBrainsMono';

/// 根据亮度构建 IDE 主题。
///
/// 将 [IdeColors] 浅色/深色调色板注册为 [ThemeExtension]，组件通过
/// [IdeColors.of] 在运行时取色；这样 [MaterialApp] 的 `theme`/`darkTheme`/
/// `themeMode` 三者配合即可实现跟随系统或手动切换。
ThemeData buildIdeTheme({required Brightness brightness}) {
  final colors = brightness == Brightness.dark
      ? IdeColors.dark
      : IdeColors.light;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: colors.accent,
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: ideFontFamily,
    colorScheme: colorScheme.copyWith(
      surface: colors.surface,
      primary: colors.accent,
      secondary: colors.warning,
    ),
    scaffoldBackgroundColor: colors.frame,
    visualDensity: VisualDensity.compact,
    extensions: <ThemeExtension<dynamic>>[colors],
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        fixedSize: const Size(30, 30),
        minimumSize: const Size(30, 30),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 12),
      bodySmall: TextStyle(fontSize: 11),
      titleSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

/// 旧入口，等价于 [buildIdeTheme] 的深色版本。
///
/// 保留给已有测试与过渡代码使用；新代码请直接使用 [buildIdeTheme]。
ThemeData buildCompactTheme() => buildIdeTheme(brightness: Brightness.dark);
