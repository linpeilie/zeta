import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_ui/zeta_ui.dart';

void main() {
  testWidgets('打开态使用 secondary，关闭态使用 ghost，并显示展开箭头', (tester) async {
    final closedFocus = FocusNode(debugLabel: 'toolbar-select-closed');
    final openFocus = FocusNode(debugLabel: 'toolbar-select-open');
    addTearDown(closedFocus.dispose);
    addTearDown(openFocus.dispose);

    await _pump(
      tester,
      Column(
        children: [
          IdeToolbarSelectTrigger(
            buttonKey: const ValueKey('closed-trigger'),
            label: 'Workspace write',
            tooltip: 'Permission mode',
            open: false,
            focusNode: closedFocus,
            onPressed: () {},
            child: const Text('Workspace write'),
          ),
          IdeToolbarSelectTrigger(
            buttonKey: const ValueKey('open-trigger'),
            label: 'Full access',
            tooltip: 'Permission mode',
            open: true,
            focusNode: openFocus,
            onPressed: () {},
            child: const Text('Full access'),
          ),
        ],
      ),
    );

    expect(
      tester
          .widget<IdeButton>(find.byKey(const ValueKey('closed-trigger')))
          .variant,
      IdeButtonVariant.ghost,
    );
    expect(
      tester
          .widget<IdeButton>(find.byKey(const ValueKey('open-trigger')))
          .variant,
      IdeButtonVariant.secondary,
    );
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNWidgets(2));
    expect(
      tester
          .widget<IdeTooltip>(
            find.ancestor(
              of: find.byKey(const ValueKey('closed-trigger')),
              matching: find.byType(IdeTooltip),
            ),
          )
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<IdeTooltip>(
            find.ancestor(
              of: find.byKey(const ValueKey('open-trigger')),
              matching: find.byType(IdeTooltip),
            ),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets('加载态用忙碌指示器替换箭头，键盘焦点仍关掉 FocusOutline', (tester) async {
    final focusNode = FocusNode(debugLabel: 'toolbar-select-loading');
    addTearDown(focusNode.dispose);

    await _pump(
      tester,
      IdeToolbarSelectTrigger(
        buttonKey: const ValueKey('loading-trigger'),
        label: 'Mode…',
        open: false,
        isLoading: true,
        focusNode: focusNode,
        child: const Text('Mode…'),
      ),
    );

    expect(
      find.byKey(const ValueKey('ide-toolbar-select-trigger-loading')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    expect(
      tester.widget<sf.Button>(find.byType(sf.Button)).disableFocusOutline,
      isTrue,
    );

    focusNode.requestFocus();
    await tester.pump();
    expect(
      tester.widget<sf.FocusOutline>(find.byType(sf.FocusOutline)).focused,
      isFalse,
    );
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  final lightTheme = buildIdeThemeData(brightness: Brightness.light);
  final darkTheme = buildIdeThemeData(brightness: Brightness.dark);
  await tester.pumpWidget(
    IdeThemeScope(
      themeMode: ThemeMode.dark,
      lightTheme: lightTheme,
      darkTheme: darkTheme,
      child: sf.ShadcnApp(
        theme: buildShadcnTheme(lightTheme),
        darkTheme: buildShadcnTheme(darkTheme),
        themeMode: sf.ThemeMode.dark,
        home: sf.Scaffold(
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    ),
  );
}
