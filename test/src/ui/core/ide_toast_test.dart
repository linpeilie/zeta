import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_ui/zeta_ui.dart';

void main() {
  testWidgets('showIdeToast renders info and error messages', (tester) async {
    await tester.pumpWidget(
      _ToastHarness(
        onReady: (context) {
          showIdeToast(
            context,
            message: 'Status updated',
            location: sf.ToastLocation.topLeft,
            showDuration: const Duration(milliseconds: 120),
          );
        },
      ),
    );
    // toast 自带关闭 timer，不能用 pumpAndSettle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Status updated'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Status updated'), findsNothing);

    await tester.pumpWidget(
      _ToastHarness(
        onReady: (context) {
          showIdeToast(
            context,
            message: 'Unable to load font',
            tone: IdeToastTone.error,
            location: sf.ToastLocation.topLeft,
            showDuration: const Duration(milliseconds: 120),
          );
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Unable to load font'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 600));
  });
}

class _ToastHarness extends StatelessWidget {
  const _ToastHarness({required this.onReady});

  final ValueChanged<BuildContext> onReady;

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
        theme: buildShadcnTheme(lightIdeTheme),
        darkTheme: buildShadcnTheme(darkIdeTheme),
        materialTheme: buildMaterialTheme(lightIdeTheme),
        themeMode: sf.ThemeMode.light,
        home: sf.Scaffold(
          child: Builder(
            builder: (context) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onReady(context);
              });
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
  }
}
