import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_ui/zeta_ui.dart';

void main() {
  group('平台 UI 字体栈', () {
    test('为桌面平台解析系统 UI 主字体', () {
      expect(resolvePlatformUiFontFamily(TargetPlatform.windows), 'Segoe UI');
      expect(
        resolvePlatformUiFontFamily(TargetPlatform.macOS),
        '.AppleSystemUIFont',
      );
      expect(resolvePlatformUiFontFamily(TargetPlatform.linux), isNull);
    });

    test('为桌面平台解析系统等宽字体', () {
      expect(resolvePlatformCodeFontFamily(TargetPlatform.windows), 'Consolas');
      expect(resolvePlatformCodeFontFamily(TargetPlatform.macOS), 'Menlo');
      expect(resolvePlatformCodeFontFamily(TargetPlatform.linux), isNull);
    });

    test('为桌面平台提供稳定的中文备用字体顺序', () {
      expect(
        resolvePlatformUiFontFamilyFallback(TargetPlatform.windows),
        const <String>['Microsoft YaHei UI', 'Microsoft YaHei'],
      );
      expect(
        resolvePlatformUiFontFamilyFallback(TargetPlatform.macOS),
        const <String>['PingFang SC', 'Hiragino Sans GB'],
      );
      expect(
        resolvePlatformUiFontFamilyFallback(TargetPlatform.linux),
        const <String>[
          'Noto Sans CJK SC',
          'Noto Sans SC',
          'WenQuanYi Micro Hei',
        ],
      );
    });

    test('跟随系统默认时把平台字体同步到三套主题投影', () {
      final ideTheme = buildIdeThemeData(
        brightness: Brightness.light,
        platform: TargetPlatform.windows,
      );

      final shadcnTypography = buildShadcnTheme(ideTheme).typography;
      final materialTheme = buildMaterialTheme(ideTheme);
      final materialTextStyle = materialTheme.textTheme.bodyMedium;
      final ideTextStyle = IdeTextStyles.resolve(
        colors: ideTheme.colors,
        uiFontFamily: ideTheme.uiFontFamily,
        uiFontFamilyFallback: ideTheme.uiFontFamilyFallback,
        codeFontFamily: ideTheme.codeFontFamily,
      ).rowTitle;

      expect(ideTheme.uiFontFamily, 'Segoe UI');
      expect(ideTheme.codeFontFamily, 'Consolas');
      expect(ideTheme.uiFontFamilyFallback, const <String>[
        'Microsoft YaHei UI',
        'Microsoft YaHei',
      ]);
      expect(shadcnTypography.sans.fontFamily, 'Segoe UI');
      expect(
        shadcnTypography.sans.fontFamilyFallback,
        ideTheme.uiFontFamilyFallback,
      );
      expect(shadcnTypography.mono.fontFamily, 'Consolas');
      expect(materialTextStyle?.fontFamily, 'Segoe UI');
      expect(
        materialTextStyle?.fontFamilyFallback,
        ideTheme.uiFontFamilyFallback,
      );
      expect(materialTheme.primaryTextTheme.bodyMedium?.fontFamily, 'Segoe UI');
      expect(
        materialTheme.primaryTextTheme.bodyMedium?.fontFamilyFallback,
        ideTheme.uiFontFamilyFallback,
      );
      expect(ideTextStyle.fontFamily, 'Segoe UI');
      expect(ideTextStyle.fontFamilyFallback, ideTheme.uiFontFamilyFallback);
    });

    test('没有稳定系统主字体的平台把主字体交给引擎解析', () {
      final ideTheme = buildIdeThemeData(
        brightness: Brightness.light,
        platform: TargetPlatform.linux,
      );

      final typography = buildShadcnTheme(ideTheme).typography;

      expect(ideTheme.uiFontFamily, isNull);
      expect(ideTheme.codeFontFamily, isNull);
      expect(typography.sans.fontFamily, isNull);
      expect(typography.mono.fontFamily, isNull);
      expect(typography.sans.fontFamilyFallback, ideTheme.uiFontFamilyFallback);
    });

    test('用户选择的 UI 字体保留为主字体并继续使用平台 fallback', () {
      final ideTheme = buildIdeThemeData(
        brightness: Brightness.dark,
        uiFontFamily: 'Segoe UI',
        codeFontFamily: 'Cascadia Mono',
        platform: TargetPlatform.windows,
      );

      final typography = buildShadcnTheme(ideTheme).typography;

      expect(ideTheme.uiFontFamily, 'Segoe UI');
      expect(typography.sans.fontFamily, 'Segoe UI');
      expect(typography.sans.fontFamilyFallback, ideTheme.uiFontFamilyFallback);
      expect(typography.mono.fontFamily, 'Cascadia Mono');
      expect(typography.mono.fontFamilyFallback, ideTheme.uiFontFamilyFallback);
    });
  });
}
