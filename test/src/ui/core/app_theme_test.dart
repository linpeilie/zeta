import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/core/constants/app_typography.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';

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

    test('跟随应用默认时把内置 Geist 同步到三套主题投影', () {
      final ideTheme = buildIdeThemeData(
        brightness: Brightness.light,
        codeFontFamily: 'JetBrainsMono',
        platform: TargetPlatform.windows,
      );

      final shadcnTypography = buildShadcnTheme(ideTheme).typography;
      final materialTheme = buildMaterialTheme(ideTheme);
      final materialTextStyle = materialTheme.textTheme.bodyMedium;
      final ideTextStyle = IdeTextStyles.resolve(
        colors: ideTheme.colors,
        uiFontFamily: ideTheme.uiFontFamily,
        uiFontFamilyFallback: ideTheme.uiFontFamilyFallback,
      ).rowTitle;

      // 主字体是内置 Geist；中文仍然靠平台 fallback 链承接。
      expect(ideTheme.uiFontFamily, bundledUiFontFamily);
      expect(ideTheme.uiFontFamilyFallback, const <String>[
        'Microsoft YaHei UI',
        'Microsoft YaHei',
      ]);
      expect(shadcnTypography.sans.fontFamily, bundledUiFontFamily);
      expect(
        shadcnTypography.sans.fontFamilyFallback,
        ideTheme.uiFontFamilyFallback,
      );
      expect(materialTextStyle?.fontFamily, bundledUiFontFamily);
      expect(
        materialTextStyle?.fontFamilyFallback,
        ideTheme.uiFontFamilyFallback,
      );
      expect(
        materialTheme.primaryTextTheme.bodyMedium?.fontFamily,
        bundledUiFontFamily,
      );
      expect(
        materialTheme.primaryTextTheme.bodyMedium?.fontFamilyFallback,
        ideTheme.uiFontFamilyFallback,
      );
      expect(ideTextStyle.fontFamily, bundledUiFontFamily);
      expect(ideTextStyle.fontFamilyFallback, ideTheme.uiFontFamilyFallback);
    });

    test('没有稳定系统主字体的平台同样落到内置 Geist', () {
      final ideTheme = buildIdeThemeData(
        brightness: Brightness.light,
        codeFontFamily: 'JetBrainsMono',
        platform: TargetPlatform.linux,
      );

      final typography = buildShadcnTheme(ideTheme).typography;

      // Linux 没有稳定的系统 UI 字体名，过去会退成 null 交给引擎；
      // 现在统一落到内置 Geist，三平台观感一致。
      expect(ideTheme.uiFontFamily, bundledUiFontFamily);
      expect(typography.sans.fontFamily, bundledUiFontFamily);
      expect(typography.sans.fontFamilyFallback, ideTheme.uiFontFamilyFallback);
    });

    test('用户选择的 UI 字体保留为主字体并继续使用平台 fallback', () {
      final ideTheme = buildIdeThemeData(
        brightness: Brightness.dark,
        uiFontFamily: 'Segoe UI',
        codeFontFamily: 'JetBrainsMono',
        platform: TargetPlatform.windows,
      );

      final typography = buildShadcnTheme(ideTheme).typography;

      expect(ideTheme.uiFontFamily, 'Segoe UI');
      expect(typography.sans.fontFamily, 'Segoe UI');
      expect(typography.sans.fontFamilyFallback, ideTheme.uiFontFamilyFallback);
      expect(typography.mono.fontFamily, 'JetBrainsMono');
      expect(typography.mono.fontFamilyFallback, ideTheme.uiFontFamilyFallback);
    });
  });
}
