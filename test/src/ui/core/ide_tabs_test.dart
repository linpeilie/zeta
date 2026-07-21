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

  testWidgets('IdeTabs 加载项只让文字呼吸并补充加载语义', (tester) async {
    await tester.pumpWidget(
      _ThemeHarness(
        child: IdeTabs<String>(
          value: 'codex',
          items: const <IdeTabItem<String>>[
            IdeTabItem<String>(
              key: ValueKey('loading-tab'),
              value: 'codex',
              label: 'Codex',
              loading: true,
            ),
          ],
          onChanged: (_) {},
        ),
      ),
    );

    final tab = find.byKey(const ValueKey('loading-tab'));
    expect(find.bySemanticsLabel('Codex，正在加载'), findsOneWidget);
    expect(
      find.descendant(
        of: tab,
        matching: find.byKey(const ValueKey('ide-tab-loading-label')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tab, matching: find.byType(AnimatedContainer)),
      findsWidgets,
    );

    await tester.pumpWidget(
      _ThemeHarness(
        child: IdeTabs<String>(
          value: 'codex',
          items: const <IdeTabItem<String>>[
            IdeTabItem<String>(
              key: ValueKey('loading-tab'),
              value: 'codex',
              label: 'Codex',
            ),
          ],
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Codex'), findsOneWidget);
    expect(
      find.descendant(
        of: tab,
        matching: find.byKey(const ValueKey('ide-tab-loading-label')),
      ),
      findsNothing,
    );
  });

  testWidgets('IdeTabs 在减少动态效果时静态弱化加载文字', (tester) async {
    await tester.pumpWidget(
      _ThemeHarness(
        disableAnimations: true,
        child: IdeTabs<String>(
          value: 'codex',
          items: const <IdeTabItem<String>>[
            IdeTabItem<String>(value: 'codex', label: 'Codex', loading: true),
          ],
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('ide-tab-loading-label')), findsNothing);
    final opacity = tester.widget<Opacity>(
      find.byKey(const ValueKey('ide-tab-loading-label-reduced-motion')),
    );
    expect(opacity.opacity, 0.72);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
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
  const _ThemeHarness({required this.child, this.disableAnimations = false});

  final Widget child;
  final bool disableAnimations;

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
        home: _MotionHarness(
          disableAnimations: disableAnimations,
          child: sf.Scaffold(child: Center(child: child)),
        ),
      ),
    );
  }
}

class _MotionHarness extends StatelessWidget {
  const _MotionHarness({required this.disableAnimations, required this.child});

  final bool disableAnimations;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child,
    );
  }
}
