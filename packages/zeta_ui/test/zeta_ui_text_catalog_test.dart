import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_ui/zeta_ui.dart';

void main() {
  group('ZetaUiTextCatalog 注入', () {
    testWidgets('未注入时回退英文，控件仍可渲染', (tester) async {
      late ZetaUiTextCatalog resolved;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            resolved = IdeUiText.of(context);
            return const SizedBox.shrink();
          },
        ),
      );

      expect(resolved, isA<FallbackZetaUiTextCatalog>());
      expect(resolved.timelineBackToBottom, 'Back to bottom');
      expect(resolved.tabsLoadingSuffix('Codex'), 'Codex, loading');
      expect(resolved.loading, 'Loading');
      expect(resolved.windowClose, 'Close');
    });

    testWidgets('注入宿主目录后控件读到宿主文案', (tester) async {
      late ZetaUiTextCatalog resolved;
      await tester.pumpWidget(
        IdeUiTextScope(
          catalog: const _StubCatalog(),
          child: Builder(
            builder: (context) {
              resolved = IdeUiText.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved.timelineNewContent, 'stub:new-content');
      expect(resolved.tabsLoadingSuffix('Grok'), 'stub:Grok');
    });

    test('只有目录实例变化才通知子树', () {
      const stub = _StubCatalog();
      const fallback = FallbackZetaUiTextCatalog();
      const child = SizedBox.shrink();

      const same = IdeUiTextScope(catalog: stub, child: child);
      const different = IdeUiTextScope(catalog: fallback, child: child);

      expect(same.updateShouldNotify(same), isFalse);
      expect(different.updateShouldNotify(same), isTrue);
    });
  });

  group('设计系统 token', () {
    testWidgets('IdeColors / IdeTextStyles 在主题 scope 下可解析', (tester) async {
      final lightTheme = buildIdeThemeData(
        brightness: Brightness.light,
        codeFontFamily: bundledCodeFontFamily,
      );
      final darkTheme = buildIdeThemeData(
        brightness: Brightness.dark,
        codeFontFamily: bundledCodeFontFamily,
      );
      late IdeColors colors;
      late IdeTextStyles textStyles;

      await tester.pumpWidget(
        IdeThemeScope(
          themeMode: ThemeMode.dark,
          lightTheme: lightTheme,
          darkTheme: darkTheme,
          child: Builder(
            builder: (context) {
              colors = IdeColors.of(context);
              textStyles = IdeTextStyles.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(colors, darkTheme.colors);
      expect(textStyles.bodySmall.fontSize, isNotNull);
    });
  });
}

final class _StubCatalog implements ZetaUiTextCatalog {
  const _StubCatalog();

  @override
  String get commonMenu => 'stub:menu';

  @override
  String get workbenchLogoSemantics => 'stub:logo';

  @override
  String get workbenchCloseOverlay => 'stub:close-overlay';

  @override
  String get timelineScrollbar => 'stub:scrollbar';

  @override
  String get timelineScrollToEnd => 'stub:scroll-to-end';

  @override
  String get timelineNewContent => 'stub:new-content';

  @override
  String get timelineBackToBottom => 'stub:back-to-bottom';

  @override
  String tabsLoadingSuffix(String label) => 'stub:$label';

  @override
  String get loading => 'stub:loading';

  @override
  String get running => 'stub:running';

  @override
  String get windowMinimize => 'stub:minimize';

  @override
  String get windowRestore => 'stub:restore';

  @override
  String get windowMaximize => 'stub:maximize';

  @override
  String get windowClose => 'stub:close';
}
