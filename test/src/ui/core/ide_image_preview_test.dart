import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_image_preview.dart';

void main() {
  testWidgets('showIdeLocalImagePreview refuses missing file without dialog', (
    tester,
  ) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      _PreviewHarness(
        child: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    await tester.pump();

    final result = await showIdeLocalImagePreview(
      hostContext,
      path: r'D:\tmp\zeta-definitely-missing-image.png',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(result, isFalse);
    expect(find.byKey(const ValueKey('ide-local-image-preview')), findsNothing);
    expect(find.textContaining('图片文件不可用'), findsOneWidget);

    // toast 默认 2s 关闭 timer，必须耗尽否则测试框架报 pending timer。
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
    'IdeLocalImageThumbnail missing path shows broken and does not open dialog',
    (tester) async {
      await tester.pumpWidget(
        _PreviewHarness(
          child: const Center(
            child: IdeLocalImageThumbnail(
              path: r'D:\tmp\zeta-missing-thumb.png',
              size: 64,
              imageKey: ValueKey('thumb-missing'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(IdeLocalImageThumbnail), findsOneWidget);
      // broken 态仍可点；点击后走 missing 路径 toast。
      await tester.tap(find.byType(IdeLocalImageThumbnail));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byKey(const ValueKey('ide-local-image-preview')),
        findsNothing,
      );
      expect(find.textContaining('图片文件不可用'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    },
  );
}

class _PreviewHarness extends StatelessWidget {
  const _PreviewHarness({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lightIdeTheme = buildIdeThemeData(
      brightness: Brightness.light,
      codeFontFamily: 'CodeFont',
    );
    final darkIdeTheme = buildIdeThemeData(
      brightness: Brightness.dark,
      codeFontFamily: 'CodeFont',
    );
    return IdeThemeScope(
      themeMode: ThemeMode.light,
      lightTheme: lightIdeTheme,
      darkTheme: darkIdeTheme,
      child: sf.ShadcnApp(
        locale: ZetaLocalization.simplifiedChinese,
        supportedLocales: ZetaLocalization.supportedLocales,
        localizationsDelegates: ZetaLocalization.delegates,
        theme: buildShadcnTheme(lightIdeTheme),
        darkTheme: buildShadcnTheme(darkIdeTheme),
        materialTheme: buildMaterialTheme(lightIdeTheme),
        themeMode: sf.ThemeMode.light,
        home: sf.Scaffold(child: child),
      ),
    );
  }
}
