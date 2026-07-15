import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';

void main() {
  testWidgets('IdeTabs 使用 Shad Tabs 并切换选中项', (tester) async {
    await tester.pumpWidget(const _ThemeHarness(child: _TabsHarness()));

    expect(find.byType(sf.Tabs), findsOneWidget);
    expect(find.text('selected:overview'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('details-tab')));
    await tester.pump();

    expect(find.text('selected:details'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
  });

  testWidgets('IdeTab 提供禁用态和下拉方向动效', (tester) async {
    var enabledPresses = 0;
    var disabledPresses = 0;

    await tester.pumpWidget(
      _ThemeHarness(
        child: _StandaloneTabsHarness(
          onEnabledPressed: () => enabledPresses += 1,
          onDisabledPressed: () => disabledPresses += 1,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('disabled-tab')));
    await tester.tap(find.byKey(const ValueKey('enabled-tab')));
    await tester.pump();

    expect(enabledPresses, 1);
    expect(disabledPresses, 0);
    final rotation = tester.widget<AnimatedRotation>(
      find.descendant(
        of: find.byKey(const ValueKey('enabled-tab')),
        matching: find.byType(AnimatedRotation),
      ),
    );
    expect(rotation.turns, 0.5);

    await tester.pumpAndSettle();
  });
}

class _TabsHarness extends StatefulWidget {
  const _TabsHarness();

  @override
  State<_TabsHarness> createState() => _TabsHarnessState();
}

class _TabsHarnessState extends State<_TabsHarness> {
  String _value = 'overview';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IdeTabs<String>(
          value: _value,
          semanticLabel: '详情视图',
          items: const [
            IdeTabItem<String>(
              key: ValueKey('overview-tab'),
              value: 'overview',
              label: '概览',
            ),
            IdeTabItem<String>(
              key: ValueKey('details-tab'),
              value: 'details',
              label: '详情',
            ),
          ],
          onChanged: (value) {
            setState(() {
              _value = value;
            });
          },
        ),
        Text('selected:$_value'),
      ],
    );
  }
}

class _StandaloneTabsHarness extends StatefulWidget {
  const _StandaloneTabsHarness({
    required this.onEnabledPressed,
    required this.onDisabledPressed,
  });

  final VoidCallback onEnabledPressed;
  final VoidCallback onDisabledPressed;

  @override
  State<_StandaloneTabsHarness> createState() => _StandaloneTabsHarnessState();
}

class _StandaloneTabsHarnessState extends State<_StandaloneTabsHarness> {
  bool _selected = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IdeTab(
          key: const ValueKey('enabled-tab'),
          label: '模型',
          selected: _selected,
          onPressed: () {
            widget.onEnabledPressed();
            setState(() {
              _selected = true;
            });
          },
        ),
        IdeTab(
          key: const ValueKey('disabled-tab'),
          label: '不可用',
          enabled: false,
          onPressed: widget.onDisabledPressed,
        ),
      ],
    );
  }
}

class _ThemeHarness extends StatelessWidget {
  const _ThemeHarness({required this.child});

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
        theme: buildShadcnTheme(lightIdeTheme),
        darkTheme: buildShadcnTheme(darkIdeTheme),
        materialTheme: buildMaterialTheme(lightIdeTheme),
        themeMode: sf.ThemeMode.light,
        home: sf.Scaffold(child: Center(child: child)),
      ),
    );
  }
}
