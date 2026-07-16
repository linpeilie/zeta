import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/workbench/ide_workbench_scaffold.dart';

import 'ide_component_test_harness.dart';

void main() {
  test('resolveWorkbenchLayoutMode 使用统一断点', () {
    expect(
      resolveWorkbenchLayoutMode(IdeMetrics.mediumBreakpoint - 1),
      IdeWorkbenchLayoutMode.compact,
    );
    expect(
      resolveWorkbenchLayoutMode(IdeMetrics.mediumBreakpoint),
      IdeWorkbenchLayoutMode.medium,
    );
    expect(
      resolveWorkbenchLayoutMode(IdeMetrics.wideBreakpoint - 1),
      IdeWorkbenchLayoutMode.medium,
    );
    expect(
      resolveWorkbenchLayoutMode(IdeMetrics.wideBreakpoint),
      IdeWorkbenchLayoutMode.wide,
    );
  });

  testWidgets('宽屏内联两侧 Pane，中屏只内联导航 Pane', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(1200, 500),
      child: _buildWorkbench(),
    );

    expect(find.byKey(const ValueKey('workbench-navigation-inline')), findsOne);
    expect(find.byKey(const ValueKey('workbench-inspector-inline')), findsOne);
    expect(
      tester.getSize(find.byKey(const ValueKey('workbench-canvas'))).width,
      greaterThanOrEqualTo(IdeMetrics.mainEditorMinWidth),
    );

    await pumpIdeComponent(
      tester,
      size: const Size(900, 500),
      child: _buildWorkbench(activeOverlay: IdeWorkbenchOverlay.inspector),
    );

    expect(find.byKey(const ValueKey('workbench-navigation-inline')), findsOne);
    expect(
      find.byKey(const ValueKey('workbench-inspector-inline')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('workbench-inspector-overlay')), findsOne);
    expect(
      tester.getSize(find.byKey(const ValueKey('workbench-canvas'))).width,
      greaterThanOrEqualTo(IdeMetrics.mainEditorMinWidth),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('空间不足时降级布局并保留中央 Canvas 最小宽度', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(820, 500),
      child: _buildWorkbench(),
    );

    expect(
      find.byKey(const ValueKey('workbench-navigation-inline')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workbench-base-compact')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('workbench-canvas'))).width,
      greaterThanOrEqualTo(IdeMetrics.mainEditorMinWidth),
    );

    await pumpIdeComponent(
      tester,
      size: const Size(1200, 500),
      child: _buildWorkbench(
        navigationWidth: IdeMetrics.sidePaneMaxWidth,
        inspectorWidth: IdeMetrics.sidePaneMaxWidth,
        activeOverlay: IdeWorkbenchOverlay.inspector,
      ),
    );

    expect(find.byKey(const ValueKey('workbench-base-medium')), findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-inspector-overlay')), findsOne);
    expect(
      tester.getSize(find.byKey(const ValueKey('workbench-canvas'))).width,
      greaterThanOrEqualTo(IdeMetrics.mainEditorMinWidth),
    );
  });

  testWidgets('窄屏 Overlay 限制可用宽度且只有一个活动侧', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(360, 500),
      child: _buildWorkbench(
        activeOverlay: IdeWorkbenchOverlay.navigation,
        navigationWidth: 320,
      ),
    );

    expect(
      find.byKey(const ValueKey('workbench-navigation-inline')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workbench-inspector-inline')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workbench-navigation-overlay')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('workbench-inspector-overlay')),
      findsNothing,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('workbench-navigation-overlay')))
          .width,
      272,
    );
  });

  testWidgets('Scrim 与 Esc 关闭 Overlay 并恢复触发控件焦点', (tester) async {
    final triggerFocusNode = FocusNode();
    final overlayFocusNode = FocusNode();
    addTearDown(triggerFocusNode.dispose);
    addTearDown(overlayFocusNode.dispose);
    IdeWorkbenchOverlay? activeOverlay = IdeWorkbenchOverlay.navigation;
    var dismissCount = 0;
    late StateSetter setHostState;

    await pumpIdeComponent(
      tester,
      size: const Size(700, 500),
      child: StatefulBuilder(
        builder: (context, setState) {
          setHostState = setState;
          return _buildWorkbench(
            activeOverlay: activeOverlay,
            triggerFocusNode: triggerFocusNode,
            navigationPane: Focus(
              focusNode: overlayFocusNode,
              autofocus: true,
              child: const ColoredBox(color: Colors.orange),
            ),
            onDismissOverlay: () {
              dismissCount += 1;
              setState(() {
                activeOverlay = null;
              });
            },
          );
        },
      ),
    );
    await tester.pump();
    expect(overlayFocusNode.hasFocus, isTrue);

    await tester.tap(find.byKey(const ValueKey('workbench-overlay-scrim')));
    await tester.pump();
    expect(dismissCount, 1);
    expect(
      find.byKey(const ValueKey('workbench-navigation-overlay')),
      findsNothing,
    );
    expect(triggerFocusNode.hasFocus, isTrue);

    setHostState(() {
      activeOverlay = IdeWorkbenchOverlay.navigation;
    });
    await tester.pump();
    triggerFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(dismissCount, 2);
    expect(
      find.byKey(const ValueKey('workbench-navigation-overlay')),
      findsNothing,
    );
    expect(triggerFocusNode.hasFocus, isTrue);
  });
}

Widget _buildWorkbench({
  IdeWorkbenchOverlay? activeOverlay,
  double navigationWidth = IdeMetrics.sidePaneDefaultWidth,
  double inspectorWidth = IdeMetrics.inspectorPaneWidth,
  FocusNode? triggerFocusNode,
  Widget navigationPane = const ColoredBox(color: Colors.orange),
  VoidCallback? onDismissOverlay,
}) {
  return IdeWorkbenchScaffold(
    leadingRailBuilder: (context, mode) => Focus(
      focusNode: triggerFocusNode,
      child: const ColoredBox(color: Colors.red),
    ),
    navigationPane: navigationPane,
    canvas: const ColoredBox(color: Colors.green),
    inspectorPane: const ColoredBox(color: Colors.blue),
    trailingRailBuilder: (context, mode) =>
        const ColoredBox(color: Colors.purple),
    activeOverlay: activeOverlay,
    navigationWidth: navigationWidth,
    inspectorWidth: inspectorWidth,
    onDismissOverlay: activeOverlay == null
        ? null
        : (onDismissOverlay ?? () {}),
    overlayTriggerFocusNode: triggerFocusNode,
  );
}
