import 'package:app_ui/app_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import '../../helpers/helpers.dart';

void main() {
  testWidgets('WindowFrame renders content without a custom title bar', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      const SizedBox(
        width: 400,
        height: 300,
        child: WindowFrame(child: Text('Content')),
      ),
    );
    expect(find.text('Content'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('window-title-bar')),
      findsNothing,
    );
  });

  testWidgets('WindowFrame delegates Windows title-bar interactions', (
    tester,
  ) async {
    var calls = 0;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpShadcnApp(
      SizedBox(
        width: 700,
        height: 300,
        child: WindowFrame(
          showCustomTitleBar: true,
          platform: WindowFramePlatform.windows,
          menuSemanticLabel: 'Application menu',
          windowsLogo: const Icon(Icons.flutter_dash),
          windowsLogoSemanticLabel: 'Zeta logo',
          dragRegionBuilder: (context, child) => KeyedSubtree(
            key: const Key('drag-region'),
            child: child,
          ),
          menus: <WindowMenu>[
            WindowMenu(
              key: const Key('menu-trigger'),
              label: 'File',
              items: <WindowMenuItem>[
                WindowMenuItem(
                  key: const Key('open-menu-item'),
                  label: 'Open',
                  onPressed: () => calls += 1,
                ),
              ],
            ),
            const WindowMenu(
              label: 'Help',
              items: <WindowMenuItem>[
                WindowMenuItem(label: 'Disabled'),
              ],
            ),
          ],
          titleBarLeadingActions: <WindowTitleBarAction>[
            WindowTitleBarAction(
              key: const Key('active-action'),
              icon: Icons.view_sidebar,
              tooltip: 'Toggle sidebar',
              semanticLabel: 'Toggle sidebar',
              active: true,
              focusNode: focusNode,
              onPressed: () => calls += 10,
            ),
          ],
          titleBarActions: <WindowTitleBarAction>[
            WindowTitleBarAction(
              key: const Key('inactive-action'),
              icon: Icons.history,
              tooltip: 'History',
              semanticLabel: 'History',
              onPressed: () => calls += 100,
            ),
            WindowTitleBarAction(
              key: const Key('disabled-action'),
              icon: Icons.search,
              tooltip: 'Search',
              semanticLabel: 'Search',
              enabled: false,
              onPressed: () => calls += 100,
            ),
          ],
          windowControls: WindowControlSet(
            minimizeLabel: 'Minimize',
            maximizeLabel: 'Maximize',
            restoreLabel: 'Restore',
            closeLabel: 'Close',
            onMinimize: () => calls += 1000,
            onToggleMaximize: () => calls += 10000,
            onClose: () => calls += 100000,
          ),
          child: const Text('Workbench'),
        ),
      ),
    );

    expect(find.byIcon(Icons.flutter_dash), findsOneWidget);
    expect(find.byKey(const Key('drag-region')), findsOneWidget);
    expect(find.byIcon(sf.LucideIcons.maximize), findsOneWidget);
    await tester.tap(find.byKey(const Key('active-action')));
    await tester.tap(find.byKey(const Key('inactive-action')));
    await tester.tap(find.byKey(const Key('disabled-action')));
    await tester.tap(_semantics('Minimize'));
    await tester.tap(_semantics('Maximize'));
    await tester.tap(_semantics('Close'));
    expect(calls, 111110);

    await tester.tap(find.byKey(const Key('menu-trigger')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 111111);
  });

  testWidgets('WindowFrame renders macOS gutter without caption controls', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      SizedBox(
        width: 400,
        height: 300,
        child: WindowFrame(
          showCustomTitleBar: true,
          platform: WindowFramePlatform.macOS,
          windowControls: WindowControlSet(
            minimizeLabel: 'Minimize',
            maximizeLabel: 'Maximize',
            restoreLabel: 'Restore',
            closeLabel: 'Close',
            onMinimize: () {},
            onToggleMaximize: () {},
            onClose: () {},
          ),
          child: const Text('macOS'),
        ),
      ),
    );
    expect(_semantics('Minimize'), findsNothing);
  });

  testWidgets('WindowFrame renders Linux restore state', (tester) async {
    await tester.pumpShadcnApp(
      SizedBox(
        width: 400,
        height: 300,
        child: WindowFrame(
          showCustomTitleBar: true,
          platform: WindowFramePlatform.linux,
          windowControls: WindowControlSet(
            maximizeLabel: 'Maximize',
            minimizeLabel: 'Minimize',
            restoreLabel: 'Restore',
            closeLabel: 'Close',
            maximized: true,
            onMinimize: () {},
            onToggleMaximize: () {},
            onClose: () {},
          ),
          child: const Text('Linux'),
        ),
      ),
    );
    expect(find.byIcon(sf.LucideIcons.minimize), findsOneWidget);
    expect(_semantics('Restore'), findsOneWidget);
  });

  for (final target in TargetPlatform.values) {
    testWidgets('WindowFrame derives appearance from $target', (tester) async {
      debugDefaultTargetPlatformOverride = target;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpShadcnApp(
        const SizedBox(
          width: 300,
          height: 200,
          child: WindowFrame(
            showCustomTitleBar: true,
            child: Text('Derived platform'),
          ),
        ),
      );
      debugDefaultTargetPlatformOverride = null;
      expect(find.text('Derived platform'), findsOneWidget);
    });
  }

  testWidgets('WindowFrame validates caller-supplied accessible copy', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      const WindowFrame(
        menus: <WindowMenu>[
          WindowMenu(label: 'File', items: <WindowMenuItem>[]),
        ],
        child: SizedBox.shrink(),
      ),
    );
    expect(tester.takeException(), isA<FlutterError>());
    expect(
      () => WindowFrame(
        windowsLogo: const Icon(Icons.flutter_dash),
        child: const SizedBox.shrink(),
      ),
      throwsAssertionError,
    );
  });
}

Finder _semantics(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );
}
