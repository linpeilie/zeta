import 'package:flutter/material.dart';

import 'package:zeta/src/core/constants/app_typography.dart';

import 'app_theme.dart';
import 'ide_colors.dart';

/// IDE 设计系统排版 token。
@immutable
class IdeTextStyles {
  const IdeTextStyles({
    required this.displayLarge,
    required this.displaySmall,
    required this.titleLarge,
    required this.titleSmall,
    required this.bodyMedium,
    required this.bodySmall,
    required this.caption,
    required this.codeMedium,
    required this.codeSmall,
  });

  final TextStyle displayLarge;
  final TextStyle displaySmall;
  final TextStyle titleLarge;
  final TextStyle titleSmall;
  final TextStyle bodyMedium;
  final TextStyle bodySmall;
  final TextStyle caption;
  final TextStyle codeMedium;
  final TextStyle codeSmall;

  /// 从当前上下文解析语义排版。
  static IdeTextStyles of(BuildContext context, {String? codeFontFamily}) {
    final ideTheme = IdeThemeScope.of(context);
    return resolve(
      colors: ideTheme.colors,
      uiFontFamily: ideTheme.uiFontFamily,
      codeFontFamily: codeFontFamily == null || codeFontFamily.isEmpty
          ? ideTheme.codeFontFamily
          : codeFontFamily,
      uiFontSize: ideTheme.uiFontSize,
      codeFontSize: ideTheme.codeFontSize,
    );
  }

  /// 按照统一 token 生成语义排版集合。
  static IdeTextStyles resolve({
    required IdeColors colors,
    String? uiFontFamily,
    String codeFontFamily = bundledCodeFontFamily,
    double uiFontSize = defaultUiFontSize,
    double codeFontSize = defaultCodeFontSize,
  }) {
    final uiScale = uiFontSize / defaultUiFontSize;
    final codeScale = codeFontSize / defaultCodeFontSize;
    return IdeTextStyles(
      displayLarge: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontSize: 18 * uiScale,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
      displaySmall: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontSize: 15 * uiScale,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontSize: 13 * uiScale,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontSize: 12 * uiScale,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontSize: 12 * uiScale,
        height: 1.42,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontSize: 11 * uiScale,
        height: 1.35,
        fontWeight: FontWeight.w400,
      ),
      caption: _textStyle(
        color: colors.textTertiary,
        fontFamily: uiFontFamily,
        fontSize: 10 * uiScale,
        height: 1.3,
        fontWeight: FontWeight.w500,
      ),
      codeMedium: _textStyle(
        color: colors.textPrimary,
        fontFamily: codeFontFamily,
        fontSize: 12 * codeScale,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
      codeSmall: _textStyle(
        color: colors.textSecondary,
        fontFamily: codeFontFamily,
        fontSize: 11 * codeScale,
        height: 1.35,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

TextStyle _textStyle({
  required Color color,
  required double fontSize,
  required double height,
  required FontWeight fontWeight,
  String? fontFamily,
}) {
  return TextStyle(
    color: color,
    fontFamily: fontFamily,
    fontSize: fontSize,
    height: height,
    fontWeight: fontWeight,
  );
}
