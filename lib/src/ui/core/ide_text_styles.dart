import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:zeta/src/core/constants/app_typography.dart';

import 'ide_colors.dart';

abstract final class _IdeTextStyleCustomKeys {
  static const displayLarge = 'displayLarge';
  static const displaySmall = 'displaySmall';
  static const titleLarge = 'titleLarge';
  static const titleSmall = 'titleSmall';
  static const bodyMedium = 'bodyMedium';
  static const bodySmall = 'bodySmall';
  static const caption = 'caption';
  static const codeMedium = 'codeMedium';
  static const codeSmall = 'codeSmall';
}

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
  static IdeTextStyles of(
    BuildContext context, {
    String codeFontFamily = bundledCodeFontFamily,
  }) {
    final shadTheme = ShadTheme.maybeOf(context, listen: false);
    if (shadTheme != null) {
      return fromShadTheme(shadTheme, codeFontFamily: codeFontFamily);
    }

    final materialTheme = Theme.of(context);
    return resolve(
      colors: IdeColors.of(context),
      uiFontFamily: materialTheme.textTheme.bodyMedium?.fontFamily,
      codeFontFamily: codeFontFamily,
    );
  }

  /// 按照统一 token 生成语义排版集合。
  static IdeTextStyles resolve({
    required IdeColors colors,
    String? uiFontFamily,
    String codeFontFamily = bundledCodeFontFamily,
  }) {
    return IdeTextStyles(
      displayLarge: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
      displaySmall: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontSize: 12,
        height: 1.42,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontSize: 11,
        height: 1.35,
        fontWeight: FontWeight.w400,
      ),
      caption: _textStyle(
        color: colors.textTertiary,
        fontFamily: uiFontFamily,
        fontSize: 10,
        height: 1.3,
        fontWeight: FontWeight.w500,
      ),
      codeMedium: _textStyle(
        color: colors.textPrimary,
        fontFamily: codeFontFamily,
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
      codeSmall: _textStyle(
        color: colors.textSecondary,
        fontFamily: codeFontFamily,
        fontSize: 11,
        height: 1.35,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  /// 从 [ShadThemeData] 中恢复 IDE 语义排版。
  static IdeTextStyles fromShadTheme(
    ShadThemeData theme, {
    String codeFontFamily = bundledCodeFontFamily,
  }) {
    final fallback = resolve(
      colors: ideColorsFromShadTheme(theme),
      uiFontFamily: theme.textTheme.family,
      codeFontFamily: codeFontFamily,
    );
    final custom = theme.textTheme.custom;
    return IdeTextStyles(
      displayLarge:
          custom[_IdeTextStyleCustomKeys.displayLarge] ?? fallback.displayLarge,
      displaySmall:
          custom[_IdeTextStyleCustomKeys.displaySmall] ?? fallback.displaySmall,
      titleLarge:
          custom[_IdeTextStyleCustomKeys.titleLarge] ?? fallback.titleLarge,
      titleSmall:
          custom[_IdeTextStyleCustomKeys.titleSmall] ?? fallback.titleSmall,
      bodyMedium:
          custom[_IdeTextStyleCustomKeys.bodyMedium] ?? fallback.bodyMedium,
      bodySmall:
          custom[_IdeTextStyleCustomKeys.bodySmall] ?? fallback.bodySmall,
      caption: custom[_IdeTextStyleCustomKeys.caption] ?? fallback.caption,
      codeMedium:
          custom[_IdeTextStyleCustomKeys.codeMedium] ?? fallback.codeMedium,
      codeSmall:
          custom[_IdeTextStyleCustomKeys.codeSmall] ?? fallback.codeSmall,
    );
  }

  /// 构建可直接注入 [ShadThemeData] 的排版主题。
  static ShadTextTheme buildShadTextTheme({
    required IdeColors colors,
    String? uiFontFamily,
    String codeFontFamily = bundledCodeFontFamily,
  }) {
    final styles = resolve(
      colors: colors,
      uiFontFamily: uiFontFamily,
      codeFontFamily: codeFontFamily,
    );
    return ShadTextTheme(
      family: uiFontFamily,
      h4: styles.titleSmall,
      p: styles.bodyMedium,
      small: styles.bodySmall,
      muted: styles.bodySmall.copyWith(color: colors.textSecondary),
      custom: <String, TextStyle>{
        _IdeTextStyleCustomKeys.displayLarge: styles.displayLarge,
        _IdeTextStyleCustomKeys.displaySmall: styles.displaySmall,
        _IdeTextStyleCustomKeys.titleLarge: styles.titleLarge,
        _IdeTextStyleCustomKeys.titleSmall: styles.titleSmall,
        _IdeTextStyleCustomKeys.bodyMedium: styles.bodyMedium,
        _IdeTextStyleCustomKeys.bodySmall: styles.bodySmall,
        _IdeTextStyleCustomKeys.caption: styles.caption,
        _IdeTextStyleCustomKeys.codeMedium: styles.codeMedium,
        _IdeTextStyleCustomKeys.codeSmall: styles.codeSmall,
      },
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
