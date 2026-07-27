import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/workbench/ide_retained_page_view.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('切换页面保留已访问页 State，且未访问页保持惰性', (tester) async {
    var selectedId = 'a';
    late StateSetter setHostState;
    final builtIds = <String>[];

    await pumpIdeComponent(
      tester,
      size: const Size(400, 300),
      child: StatefulBuilder(
        builder: (context, setState) {
          setHostState = setState;
          return IdeRetainedPageView(
            selectedId: selectedId,
            pages: [
              for (final id in <String>['a', 'b', 'c'])
                IdeRetainedPage(
                  id: id,
                  child: _ProbePage(
                    key: ValueKey<String>('probe-state-$id'),
                    id: id,
                    onBuilt: () => builtIds.add(id),
                  ),
                ),
            ],
          );
        },
      ),
    );

    expect(find.text('probe-a'), findsOneWidget);
    expect(find.text('probe-b'), findsNothing);
    expect(find.text('probe-c'), findsNothing);
    expect(builtIds, <String>['a']);
    final stateA = tester.state<_ProbePageState>(
      find.byKey(const ValueKey('probe-state-a')),
    );
    expect(stateA.mountCount, 1);

    setHostState(() => selectedId = 'b');
    await tester.pump();
    await tester.pump();

    expect(find.text('probe-b'), findsOneWidget);
    expect(builtIds, <String>['a', 'b']);
    expect(find.text('probe-c'), findsNothing);

    setHostState(() => selectedId = 'a');
    await tester.pump();
    await tester.pump();

    expect(find.text('probe-a'), findsOneWidget);
    expect(
      tester.state<_ProbePageState>(
        find.byKey(const ValueKey('probe-state-a')),
      ),
      same(stateA),
    );
    expect(stateA.mountCount, 1);
    // c 从未选中，保持惰性。
    expect(builtIds, isNot(contains('c')));
  });

  testWidgets('列表头部插入后 State 不串位', (tester) async {
    var selectedId = 'b';
    var pageIds = <String>['b', 'c'];
    late StateSetter setHostState;

    await pumpIdeComponent(
      tester,
      size: const Size(400, 300),
      child: StatefulBuilder(
        builder: (context, setState) {
          setHostState = setState;
          return IdeRetainedPageView(
            selectedId: selectedId,
            pages: [
              for (final id in pageIds)
                IdeRetainedPage(
                  id: id,
                  child: _ProbePage(
                    key: ValueKey<String>('probe-state-$id'),
                    id: id,
                  ),
                ),
            ],
          );
        },
      ),
    );

    final stateB = tester.state<_ProbePageState>(
      find.byKey(const ValueKey('probe-state-b')),
    );
    stateB.note = 'b-note';

    setHostState(() {
      pageIds = <String>['a', 'b', 'c'];
      selectedId = 'b';
    });
    await tester.pump();
    await tester.pump();

    expect(find.text('probe-b'), findsOneWidget);
    final stateBAfter = tester.state<_ProbePageState>(
      find.byKey(const ValueKey('probe-state-b')),
    );
    expect(stateBAfter, same(stateB));
    expect(stateBAfter.note, 'b-note');
    expect(stateBAfter.mountCount, 1);
  });

  testWidgets('离屏 keep-alive 页在父约束变化时不重新 layout', (tester) async {
    var selectedId = 'a';
    late StateSetter setHostState;

    await pumpIdeComponent(
      tester,
      size: const Size(400, 300),
      child: StatefulBuilder(
        builder: (context, setState) {
          setHostState = setState;
          return IdeRetainedPageView(
            selectedId: selectedId,
            pages: [
              IdeRetainedPage(
                id: 'a',
                child: _LayoutCountingPage(
                  key: const ValueKey('layout-count-a'),
                  label: 'a',
                ),
              ),
              IdeRetainedPage(
                id: 'b',
                child: _LayoutCountingPage(
                  key: const ValueKey('layout-count-b'),
                  label: 'b',
                ),
              ),
            ],
          );
        },
      ),
    );

    // 先访问 B，使其进入 keep-alive，再回到 A。
    setHostState(() => selectedId = 'b');
    await tester.pump();
    await tester.pump();
    final stateB = tester.state<_LayoutCountingPageState>(
      find.byKey(const ValueKey('layout-count-b')),
    );
    final layoutsOnBWhenActive = stateB.layoutCount;
    expect(layoutsOnBWhenActive, greaterThan(0));

    setHostState(() => selectedId = 'a');
    await tester.pump();
    await tester.pump();

    final layoutsOnBWhenHidden = stateB.layoutCount;
    final buildsOnBWhenHidden = stateB.buildCount;

    for (var width = 400; width >= 320; width -= 8) {
      await tester.binding.setSurfaceSize(Size(width.toDouble(), 300));
      await tester.pump();
    }

    // 离屏 keep-alive 页不应随父宽度持续 layout。
    expect(stateB.layoutCount, layoutsOnBWhenHidden);
    expect(stateB.buildCount, buildsOnBWhenHidden);
    expect(find.text('count-a'), findsOneWidget);
  });
}

class _ProbePage extends StatefulWidget {
  const _ProbePage({required this.id, this.onBuilt, super.key});

  final String id;
  final VoidCallback? onBuilt;

  @override
  State<_ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<_ProbePage> {
  int mountCount = 0;
  String note = '';

  @override
  void initState() {
    super.initState();
    mountCount += 1;
    widget.onBuilt?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.blue,
      child: Center(child: Text('probe-${widget.id}')),
    );
  }
}

class _LayoutCountingPage extends StatefulWidget {
  const _LayoutCountingPage({required this.label, super.key});

  final String label;

  @override
  State<_LayoutCountingPage> createState() => _LayoutCountingPageState();
}

class _LayoutCountingPageState extends State<_LayoutCountingPage> {
  int buildCount = 0;
  int layoutCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount += 1;
    return _LayoutCounter(
      onLayout: () => layoutCount += 1,
      child: Center(child: Text('count-${widget.label}')),
    );
  }
}

class _LayoutCounter extends SingleChildRenderObjectWidget {
  const _LayoutCounter({required this.onLayout, required super.child});

  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLayoutCounter(onLayout: onLayout);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderLayoutCounter renderObject,
  ) {
    renderObject.onLayout = onLayout;
  }
}

class _RenderLayoutCounter extends RenderProxyBox {
  _RenderLayoutCounter({required this.onLayout});

  VoidCallback onLayout;

  @override
  void performLayout() {
    onLayout();
    super.performLayout();
  }
}
