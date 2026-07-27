import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';
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
      find.descendant(
        of: find.byKey(const ValueKey('workbench-navigation-inline')),
        matching: find.byType(IdeSurface),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('workbench-inspector-inline')),
        matching: find.byType(IdeSurface),
      ),
      findsNothing,
    );
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
      find.descendant(
        of: find.byKey(const ValueKey('workbench-inspector-overlay')),
        matching: find.byType(IdeSurface),
      ),
      findsNothing,
    );
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
    expect(find.byKey(const ValueKey('workbench-base')), findsOneWidget);
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

    // 基础 Row 使用稳定 key，模式变化后仍是同一个 workbench-base。
    expect(find.byKey(const ValueKey('workbench-base')), findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-inspector-overlay')), findsOne);
    expect(
      tester.getSize(find.byKey(const ValueKey('workbench-canvas'))).width,
      greaterThanOrEqualTo(IdeMetrics.mainEditorMinWidth),
    );
  });

  testWidgets('Wide ↔ Medium 切换保留 Canvas 子树 State identity', (tester) async {
    // 在同一棵树上只改变约束，验证稳定 Row key 在断点切换时不卸载 Canvas。
    await pumpIdeComponent(
      tester,
      size: const Size(1200, 500),
      child: _buildWorkbench(canvas: const _CanvasProbe()),
    );

    expect(find.byKey(const ValueKey('workbench-base')), findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-inspector-inline')), findsOne);
    expect(
      find.byKey(const ValueKey('workbench-navigation-separator')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('workbench-inspector-separator')),
      findsOne,
    );

    final wideCanvasElement = tester.element(find.byType(_CanvasProbe));
    final wideBaseElement = tester.element(
      find.byKey(const ValueKey('workbench-base')),
    );
    final wideCanvasSlotElement = tester.element(
      find.byKey(const ValueKey('workbench-canvas-slot')),
    );
    final wideCanvasKeyedElement = tester.element(
      find.byKey(const ValueKey('workbench-canvas')),
    );
    final probeState = tester.state<_CanvasProbeState>(
      find.byType(_CanvasProbe),
    );
    expect(probeState.mountCount, 1);

    // Wide → Medium：Inspector 退出 inline，但不引入 Overlay Stack 父级变化。
    await tester.binding.setSurfaceSize(const Size(900, 500));
    await tester.pump();

    expect(find.byKey(const ValueKey('workbench-base')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workbench-inspector-inline')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workbench-inspector-overlay')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('workbench-navigation-inline')), findsOne);
    expect(
      tester.element(find.byKey(const ValueKey('workbench-base'))),
      same(wideBaseElement),
    );
    expect(
      tester.element(find.byKey(const ValueKey('workbench-canvas-slot'))),
      same(wideCanvasSlotElement),
    );
    expect(
      tester.element(find.byKey(const ValueKey('workbench-canvas'))),
      same(wideCanvasKeyedElement),
    );
    expect(tester.element(find.byType(_CanvasProbe)), same(wideCanvasElement));
    expect(
      tester.state<_CanvasProbeState>(find.byType(_CanvasProbe)),
      same(probeState),
    );
    expect(probeState.mountCount, 1);

    // Medium → Wide：Inspector 重新 inline，Canvas State 仍保持。
    await tester.binding.setSurfaceSize(const Size(1200, 500));
    await tester.pump();

    expect(find.byKey(const ValueKey('workbench-inspector-inline')), findsOne);
    expect(
      find.byKey(const ValueKey('workbench-inspector-overlay')),
      findsNothing,
    );
    expect(
      tester.element(find.byKey(const ValueKey('workbench-base'))),
      same(wideBaseElement),
    );
    expect(tester.element(find.byType(_CanvasProbe)), same(wideCanvasElement));
    expect(
      tester.state<_CanvasProbeState>(find.byType(_CanvasProbe)),
      same(probeState),
    );
    expect(probeState.mountCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('中央 Canvas 列仅增加圆角，保留原背景且无边框', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(1200, 500),
      child: _buildWorkbench(),
    );

    final canvasSurface = tester.widget<IdeSurface>(
      find.descendant(
        of: find.byKey(const ValueKey('workbench-canvas')),
        matching: find.byType(IdeSurface),
      ),
    );
    expect(canvasSurface.level, IdeSurfaceLevel.canvas);
    expect(canvasSurface.borderRadius, IdeRadius.allMedium);

    final decoration =
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byKey(const ValueKey('workbench-canvas')),
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as BoxDecoration;
    expect(decoration.borderRadius, IdeRadius.allMedium);
    expect(decoration.color, IdeColors.dark.canvasSurface);
    expect(decoration.border, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('条件 slot 插入删除时各直接 child 使用稳定 key', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(1200, 500),
      child: _buildWorkbench(),
    );

    expect(find.byKey(const ValueKey('workbench-leading-rail')), findsOne);
    expect(find.byKey(const ValueKey('workbench-leading-rail-gap')), findsOne);
    expect(find.byKey(const ValueKey('workbench-navigation-inline')), findsOne);
    expect(
      find.byKey(const ValueKey('workbench-navigation-separator')),
      findsOne,
    );
    expect(find.byKey(const ValueKey('workbench-canvas-slot')), findsOne);
    expect(find.byKey(const ValueKey('workbench-canvas')), findsOne);
    expect(
      find.byKey(const ValueKey('workbench-inspector-separator')),
      findsOne,
    );
    expect(find.byKey(const ValueKey('workbench-inspector-inline')), findsOne);
    expect(find.byKey(const ValueKey('workbench-trailing-rail-gap')), findsOne);
    expect(find.byKey(const ValueKey('workbench-trailing-rail')), findsOne);
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
  Widget canvas = const ColoredBox(color: Colors.green),
  Widget navigationPane = const ColoredBox(color: Colors.orange),
  VoidCallback? onDismissOverlay,
}) {
  return IdeWorkbenchScaffold(
    leadingRailBuilder: (context, mode) => Focus(
      focusNode: triggerFocusNode,
      child: const ColoredBox(color: Colors.red),
    ),
    navigationPane: navigationPane,
    canvas: canvas,
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

/// 用于验证跨断点切换时 Canvas 子树 State 不会被卸载重建。
class _CanvasProbe extends StatefulWidget {
  const _CanvasProbe();

  @override
  State<_CanvasProbe> createState() => _CanvasProbeState();
}

class _CanvasProbeState extends State<_CanvasProbe> {
  int mountCount = 0;

  @override
  void initState() {
    super.initState();
    mountCount += 1;
  }

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Colors.green);
  }
}
