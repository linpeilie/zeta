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
    expect(dark.userMessageSurface, isNot(light.userMessageSurface));
    expect(dark.focusRing, isNot(light.focusRing));
    expect(dark.selectedSurface, isNot(dark.accent));
    expect(light.selectedSurface, isNot(light.accent));
    expect(dark.userMessageSurface, isNot(dark.primaryMuted));
    expect(light.userMessageSurface, isNot(light.primaryMuted));
  });

  test('表面语义 getter 保持兼容映射和预期明度顺序', () {
    expect(IdeColors.dark.frameSurface, IdeColors.dark.frame);
    expect(IdeColors.dark.canvasSurface, IdeColors.dark.editor);
    expect(IdeColors.dark.paneSurface, IdeColors.dark.surface);
    expect(IdeColors.dark.controlSurface, IdeColors.dark.surfaceElevated);
    expect(IdeColors.dark.popoverSurface, IdeColors.dark.surfaceOverlay);

    expect(
      IdeColors.dark.canvasSurface.computeLuminance(),
      lessThan(IdeColors.dark.paneSurface.computeLuminance()),
    );
    expect(
      IdeColors.dark.paneSurface.computeLuminance(),
      lessThan(IdeColors.dark.controlSurface.computeLuminance()),
    );
    expect(
      IdeColors.light.canvasSurface.computeLuminance(),
      greaterThan(IdeColors.light.paneSurface.computeLuminance()),
    );
    expect(
      IdeColors.light.paneSurface.computeLuminance(),
      greaterThan(IdeColors.light.controlSurface.computeLuminance()),
    );
  });

  test('copyWith 覆盖全部新增状态字段', () {
    final copied = IdeColors.dark.copyWith(
      hoverSurface: IdeColors.light.hoverSurface,
      pressedSurface: IdeColors.light.pressedSurface,
      selectedSurface: IdeColors.light.selectedSurface,
      selectedHoverSurface: IdeColors.light.selectedHoverSurface,
      userMessageSurface: IdeColors.light.userMessageSurface,
      focusRing: IdeColors.light.focusRing,
    );

    expect(copied.hoverSurface, IdeColors.light.hoverSurface);
    expect(copied.pressedSurface, IdeColors.light.pressedSurface);
    expect(copied.selectedSurface, IdeColors.light.selectedSurface);
    expect(copied.selectedHoverSurface, IdeColors.light.selectedHoverSurface);
    expect(copied.userMessageSurface, IdeColors.light.userMessageSurface);
    expect(copied.focusRing, IdeColors.light.focusRing);
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
      midpoint.userMessageSurface,
      Color.lerp(
        IdeColors.dark.userMessageSurface,
        IdeColors.light.userMessageSurface,
        0.5,
      ),
    );
    expect(
      midpoint.focusRing,
      Color.lerp(IdeColors.dark.focusRing, IdeColors.light.focusRing, 0.5),
    );
  });

  test('主题投影消费 IdeColors 语义 Token（源自 shadcn Zinc/blue）', () {
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

  test('IdeColors 色值来自 shadcn ColorSchemes.zinc 与 Colors 色板', () {
    final darkScheme = sf.ColorSchemes.darkZinc;
    final lightScheme = sf.ColorSchemes.lightZinc;

    expect(IdeColors.dark.frame, darkScheme.background);
    expect(IdeColors.dark.textPrimary, darkScheme.foreground);
    expect(IdeColors.dark.border, darkScheme.border);
    expect(IdeColors.dark.selectedSurface, darkScheme.accent);
    expect(IdeColors.dark.accent, sf.Colors.blue[500]);
    expect(IdeColors.dark.focusRing, sf.Colors.blue[500]);
    expect(IdeColors.dark.closeHover, sf.Colors.red[500]);
    expect(IdeColors.dark.error, sf.Colors.red[400]);
    expect(IdeColors.dark.warning, sf.Colors.amber[400]);
    expect(IdeColors.dark.success, sf.Colors.green[400]);
    expect(IdeColors.dark.info, sf.Colors.sky[400]);
    expect(IdeColors.dark.surface, sf.Colors.zinc[900]);
    expect(IdeColors.dark.surfaceElevated, sf.Colors.zinc[800]);

    expect(IdeColors.light.frame, lightScheme.background);
    expect(IdeColors.light.textPrimary, lightScheme.foreground);
    expect(IdeColors.light.border, lightScheme.border);
    expect(IdeColors.light.selectedSurface, lightScheme.accent);
    expect(IdeColors.light.accent, sf.Colors.blue[600]);
    expect(IdeColors.light.focusRing, sf.Colors.blue[600]);
    expect(IdeColors.light.closeHover, sf.Colors.red[500]);
    expect(IdeColors.light.error, sf.Colors.red[500]);
    expect(IdeColors.light.warning, sf.Colors.amber[700]);
    expect(IdeColors.light.success, sf.Colors.green[600]);
    expect(IdeColors.light.info, sf.Colors.sky[600]);
    expect(IdeColors.light.surface, sf.Colors.zinc[50]);
    expect(IdeColors.light.surfaceElevated, sf.Colors.zinc[100]);
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
