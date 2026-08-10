import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';

void main() {
  test('深浅主题为全部交互状态提供独立颜色', () {
    final dark = IdeColors.dark;
    final light = IdeColors.light;

    expect(dark.hoverSurface, isNot(light.hoverSurface));
    expect(dark.pressedSurface, isNot(light.pressedSurface));
    expect(dark.selectedSurface, isNot(light.selectedSurface));
    expect(dark.selectedHoverSurface, isNot(light.selectedHoverSurface));
    expect(dark.focusRing, isNot(light.focusRing));
    expect(dark.intelligenceAccent, isNot(light.intelligenceAccent));
    expect(dark.selectedSurface, isNot(dark.accent));
    expect(light.selectedSurface, isNot(light.accent));
  });

  test('表面语义 getter 保持兼容映射', () {
    expect(IdeColors.dark.frameSurface, IdeColors.dark.frame);
    expect(IdeColors.dark.canvasSurface, IdeColors.dark.editor);
    expect(IdeColors.dark.paneSurface, IdeColors.dark.surface);
    expect(IdeColors.dark.controlSurface, IdeColors.dark.surfaceElevated);
    expect(IdeColors.dark.popoverSurface, IdeColors.dark.surfaceOverlay);
  });

  test('表面阶梯严格单调：frame 永远离内容最远', () {
    // 零阴影法则下，层级完全靠这条明度阶梯表达。任何一档塌陷成同色，
    // 对应的两层 UI 在视觉上就分不开了，所以必须是严格单调而非非降。
    void expectStrictlyIncreasing(String label, List<Color> ladder) {
      for (var i = 1; i < ladder.length; i++) {
        expect(
          ladder[i].computeLuminance(),
          greaterThan(ladder[i - 1].computeLuminance()),
          reason: '$label 第 $i 档没有比上一档更亮',
        );
      }
    }

    // 深色：由外向内逐档提亮。
    expectStrictlyIncreasing('深色表面阶梯', [
      IdeColors.dark.frameSurface,
      IdeColors.dark.canvasSurface,
      IdeColors.dark.paneSurface,
      IdeColors.dark.controlSurface,
      IdeColors.dark.popoverSurface,
    ]);

    // 浅色：同一规则、相反方向，frame 依然是离内容最远的一档。
    expectStrictlyIncreasing('浅色表面阶梯', [
      IdeColors.light.frameSurface,
      IdeColors.light.controlSurface,
      IdeColors.light.paneSurface,
      IdeColors.light.canvasSurface,
    ]);
    expect(
      IdeColors.light.popoverSurface.computeLuminance(),
      greaterThanOrEqualTo(IdeColors.light.paneSurface.computeLuminance()),
    );
  });

  test('描边与交互态使用半透明叠加，保证 hover 只提亮不改色', () {
    for (final entry in <String, IdeColors>{
      '深色': IdeColors.dark,
      '浅色': IdeColors.light,
    }.entries) {
      final colors = entry.value;
      for (final field in <String, Color>{
        'border': colors.border,
        'borderSubtle': colors.borderSubtle,
        'hoverSurface': colors.hoverSurface,
        'pressedSurface': colors.pressedSurface,
        'selectedSurface': colors.selectedSurface,
        'selectedHoverSurface': colors.selectedHoverSurface,
      }.entries) {
        expect(
          field.value.a,
          lessThan(1.0),
          reason: '${entry.key} ${field.key} 必须是半透明叠加色，不能是不透明色',
        );
      }
      // hover 是「提亮 5%」，pressed / selected 更重，层级不能反过来。
      expect(colors.hoverSurface.a, lessThan(colors.pressedSurface.a));
      expect(colors.selectedSurface.a, lessThan(colors.selectedHoverSurface.a));
    }
  });

  test('前景色在深浅主题下都满足 WCAG AA（正文 4.5:1）', () {
    double contrast(Color foreground, Color background) {
      final a = foreground.computeLuminance();
      final b = background.computeLuminance();
      final lighter = a > b ? a : b;
      final darker = a > b ? b : a;
      return (lighter + 0.05) / (darker + 0.05);
    }

    for (final entry in <String, IdeColors>{
      '深色': IdeColors.dark,
      '浅色': IdeColors.light,
    }.entries) {
      final colors = entry.value;
      for (final surface in <String, Color>{
        'canvas': colors.canvasSurface,
        'pane': colors.paneSurface,
        'control': colors.controlSurface,
        'popover': colors.popoverSurface,
      }.entries) {
        for (final text in <String, Color>{
          'textPrimary': colors.textPrimary,
          'textSecondary': colors.textSecondary,
          // 时间戳等 10px 辅助信息用的就是这一档，最容易踩线，必须一起守。
          'textTertiary': colors.textTertiary,
        }.entries) {
          expect(
            contrast(text.value, surface.value),
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} ${text.key} 落在 ${surface.key} 上不满足 WCAG AA',
          );
        }
      }
    }
  });

  test('copyWith 覆盖全部新增状态字段', () {
    final copied = IdeColors.dark.copyWith(
      hoverSurface: IdeColors.light.hoverSurface,
      pressedSurface: IdeColors.light.pressedSurface,
      selectedSurface: IdeColors.light.selectedSurface,
      selectedHoverSurface: IdeColors.light.selectedHoverSurface,
      focusRing: IdeColors.light.focusRing,
      intelligenceAccent: IdeColors.light.intelligenceAccent,
    );

    expect(copied.hoverSurface, IdeColors.light.hoverSurface);
    expect(copied.pressedSurface, IdeColors.light.pressedSurface);
    expect(copied.selectedSurface, IdeColors.light.selectedSurface);
    expect(copied.selectedHoverSurface, IdeColors.light.selectedHoverSurface);
    expect(copied.focusRing, IdeColors.light.focusRing);
    expect(copied.intelligenceAccent, IdeColors.light.intelligenceAccent);
  });

  test('lerp 插值全部新增状态字段', () {
    final midpoint = IdeColors.dark.lerp(IdeColors.light, 0.5);

    expect(
      midpoint.hoverSurface,
      Color.lerp(
        IdeColors.dark.hoverSurface,
        IdeColors.light.hoverSurface,
        0.5,
      ),
    );
    expect(
      midpoint.pressedSurface,
      Color.lerp(
        IdeColors.dark.pressedSurface,
        IdeColors.light.pressedSurface,
        0.5,
      ),
    );
    expect(
      midpoint.selectedSurface,
      Color.lerp(
        IdeColors.dark.selectedSurface,
        IdeColors.light.selectedSurface,
        0.5,
      ),
    );
    expect(
      midpoint.selectedHoverSurface,
      Color.lerp(
        IdeColors.dark.selectedHoverSurface,
        IdeColors.light.selectedHoverSurface,
        0.5,
      ),
    );
    expect(
      midpoint.focusRing,
      Color.lerp(IdeColors.dark.focusRing, IdeColors.light.focusRing, 0.5),
    );
    expect(
      midpoint.intelligenceAccent,
      Color.lerp(
        IdeColors.dark.intelligenceAccent,
        IdeColors.light.intelligenceAccent,
        0.5,
      ),
    );
  });

  test('主题投影消费 IdeColors 语义 Token（源自 neutral/Zinc/blue）', () {
    final ideTheme = buildIdeThemeData(
      brightness: Brightness.dark,
      codeFontFamily: 'monospace',
    );
    final shadcn = buildShadcnTheme(ideTheme).colorScheme;
    final material = buildMaterialTheme(ideTheme);

    expect(shadcn.background, ideTheme.colors.frameSurface);
    expect(shadcn.card, ideTheme.colors.paneSurface);
    expect(shadcn.popover, ideTheme.colors.popoverSurface);
    expect(shadcn.secondary, ideTheme.colors.controlSurface);
    expect(shadcn.accent, ideTheme.colors.selectedSurface);
    expect(shadcn.ring, ideTheme.colors.focusRing);
    expect(shadcn.primary, ideTheme.colors.accent);
    expect(material.scaffoldBackgroundColor, ideTheme.colors.frameSurface);
    expect(material.canvasColor, ideTheme.colors.canvasSurface);
    expect(material.cardColor, ideTheme.colors.paneSurface);
    expect(material.focusColor, ideTheme.colors.focusRing);
    expect(material.hoverColor, ideTheme.colors.hoverSurface);
  });

  test('深色底色收敛到 neutral 单色系，不混用 zinc', () {
    expect(IdeColors.dark.frame, sf.Colors.neutral[950]);
    expect(IdeColors.dark.surface, sf.Colors.neutral[900]);
    expect(IdeColors.dark.panel, sf.Colors.neutral[900]);
    expect(IdeColors.dark.surfaceOverlay, sf.Colors.neutral[800]);
    expect(IdeColors.dark.textPrimary, sf.Colors.neutral[50]);
    expect(IdeColors.dark.textSecondary, sf.Colors.neutral[400]);
    // canvas / control 是两档之间的插值，只断言落在正确区间。
    expect(
      IdeColors.dark.editor.computeLuminance(),
      inInclusiveRange(
        sf.Colors.neutral[950].computeLuminance(),
        sf.Colors.neutral[900].computeLuminance(),
      ),
    );
    expect(
      IdeColors.dark.surfaceElevated.computeLuminance(),
      inInclusiveRange(
        sf.Colors.neutral[900].computeLuminance(),
        sf.Colors.neutral[800].computeLuminance(),
      ),
    );
    // 三级前景不能退回 neutral.500：那一档在新炭黑底上不满足 AA。
    expect(
      IdeColors.dark.textTertiary.computeLuminance(),
      greaterThan(sf.Colors.neutral[500].computeLuminance()),
    );
  });

  test('点缀色降饱和后仍保持蓝色相，且深浅分档', () {
    for (final entry in <String, (IdeColors, sf.ColorShades)>{
      '深色': (IdeColors.dark, sf.Colors.blue),
      '浅色': (IdeColors.light, sf.Colors.blue),
    }.entries) {
      final colors = entry.value.$1;
      // focusRing 与 accent 同源，避免出现两种「主色」。
      expect(colors.focusRing, colors.accent);
      final hsl = HSLColor.fromColor(colors.accent);
      expect(
        hsl.hue,
        inInclusiveRange(200, 240),
        reason: '${entry.key} accent 必须仍是蓝色相',
      );
      expect(
        hsl.saturation,
        lessThan(0.8),
        reason: '${entry.key} accent 饱和度过高，会破坏单色底的克制感',
      );
    }
    expect(IdeColors.dark.accent, isNot(IdeColors.light.accent));
  });

  test('状态色与智能强调色保持各自语义色板', () {
    expect(IdeColors.dark.closeHover, sf.Colors.red[500]);
    expect(IdeColors.dark.error, sf.Colors.red[400]);
    expect(IdeColors.dark.warning, sf.Colors.amber[400]);
    expect(IdeColors.dark.success, sf.Colors.green[400]);
    expect(IdeColors.dark.info, sf.Colors.sky[400]);
    expect(IdeColors.dark.intelligenceAccent, sf.Colors.violet[400]);
    expect(IdeColors.light.closeHover, sf.Colors.red[500]);
    expect(IdeColors.light.error, sf.Colors.red[500]);
    expect(IdeColors.light.warning, sf.Colors.amber[700]);
    expect(IdeColors.light.success, sf.Colors.green[600]);
    expect(IdeColors.light.info, sf.Colors.sky[600]);
    expect(IdeColors.light.intelligenceAccent, sf.Colors.violet[500]);
  });

  test('浅色底色镜像同一套规则', () {
    expect(IdeColors.light.frame, sf.Colors.zinc[200]);
    expect(IdeColors.light.editor, sf.Colors.white);
    expect(IdeColors.light.surface, sf.Colors.neutral[50]);
    expect(IdeColors.light.surfaceElevated, sf.Colors.zinc[100]);
    expect(IdeColors.light.surfaceOverlay, sf.Colors.white);
    expect(IdeColors.light.textPrimary, sf.Colors.zinc[950]);
  });

  testWidgets('IdeThemeScope 在深浅模式提供对应状态 Token', (tester) async {
    Future<IdeColors> resolve(ThemeMode themeMode) async {
      late IdeColors resolved;
      await tester.pumpWidget(
        IdeThemeScope(
          themeMode: themeMode,
          lightTheme: buildIdeThemeData(
            brightness: Brightness.light,
            codeFontFamily: 'monospace',
          ),
          darkTheme: buildIdeThemeData(
            brightness: Brightness.dark,
            codeFontFamily: 'monospace',
          ),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                resolved = IdeColors.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return resolved;
    }

    expect(await resolve(ThemeMode.dark), same(IdeColors.dark));
    expect(await resolve(ThemeMode.light), same(IdeColors.light));
  });
}
