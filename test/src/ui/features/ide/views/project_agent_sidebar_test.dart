import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_resize_handle.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/features/ide/views/project_agent_sidebar.dart';

import '../../../core/ide_component_test_harness.dart';

void main() {
  testWidgets('折叠态只有一个卡片、统计固定底部且不显示拖动手柄', (tester) async {
    await _pumpSidebar(
      tester,
      height: 520,
      expanded: false,
      fraction: 0.7,
      projects: const ColoredBox(
        key: ValueKey('projects-content'),
        color: Colors.blue,
      ),
      agentUsage: const SizedBox(key: ValueKey('usage-content'), height: 88),
    );

    expect(find.byType(PanelCard), findsOneWidget);
    expect(find.byType(IdeResizeHandle), findsNothing);
    expect(
      tester
          .getBottomRight(
            find.byKey(const ValueKey('project-agent-sidebar-usage')),
          )
          .dy,
      closeTo(
        tester
            .getBottomRight(find.byKey(const ValueKey('projects-panel-card')))
            .dy,
        0.01,
      ),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('project-agent-sidebar-projects')))
          .height,
      greaterThan(88),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开态按父高度与默认比例向上挤压 Projects', (tester) async {
    await _pumpSidebar(
      tester,
      height: 600,
      expanded: true,
      projects: const ColoredBox(color: Colors.blue),
      agentUsage: const ColoredBox(color: Colors.green),
    );

    final projects = find.byKey(
      const ValueKey('project-agent-sidebar-projects'),
    );
    final usage = find.byKey(const ValueKey('project-agent-sidebar-usage'));
    expect(tester.getSize(usage).height, 240);
    expect(tester.getSize(projects).height, 600 - 240 - IdeSpacing.space8);
    expect(
      tester.getTopLeft(usage).dy,
      greaterThan(tester.getTopLeft(projects).dy),
    );
    expect(find.byType(IdeResizeHandle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('折叠不改变保存比例，重新展开恢复同一高度意图', (tester) async {
    final expanded = ValueNotifier<bool>(false);
    addTearDown(expanded.dispose);
    final commits = <double>[];

    await pumpIdeComponent(
      tester,
      size: const Size(320, 600),
      child: ValueListenableBuilder<bool>(
        valueListenable: expanded,
        builder: (context, value, _) => ProjectAgentSidebar(
          projects: const ColoredBox(color: Colors.blue),
          agentUsage: const SizedBox(height: 88),
          agentUsageExpanded: value,
          agentUsageHeightFraction: 0.7,
          onAgentUsageHeightFractionChanged: commits.add,
        ),
      ),
    );

    expect(find.byType(IdeResizeHandle), findsNothing);
    expect(commits, isEmpty);

    expanded.value = true;
    await tester.pump();

    expect(find.byType(IdeResizeHandle), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('project-agent-sidebar-usage')))
          .height,
      420,
    );
    expect(commits, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('拖动只在结束时提交，并在双侧最小高度之间夹紧', (tester) async {
    final commits = <double>[];
    await _pumpSidebar(
      tester,
      height: 600,
      expanded: true,
      projects: const ColoredBox(color: Colors.blue),
      agentUsage: const ColoredBox(color: Colors.green),
      onFractionChanged: commits.add,
    );

    final handle = find.byKey(const ValueKey('agent-usage-resize-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, -1000));
    await tester.pump();
    expect(commits, isEmpty);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('project-agent-sidebar-usage')))
          .height,
      600 - IdeSpacing.space8 - IdeMetrics.projectsPaneMinHeight,
    );

    await gesture.up();
    await tester.pump();
    expect(commits, hasLength(1));
    expect(commits.single, closeTo(432 / 600, 0.0001));

    await tester.drag(handle, const Offset(0, 1000));
    await tester.pump();
    expect(commits, hasLength(2));
    expect(commits.last, closeTo(220 / 600, 0.0001));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('project-agent-sidebar-usage')))
          .height,
      IdeMetrics.agentUsageExpandedMinHeight,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('空间不足时保留 Projects 最小高度并让统计正文内部滚动', (tester) async {
    final projectsScrollController = ScrollController();
    final usageScrollController = ScrollController();
    addTearDown(projectsScrollController.dispose);
    addTearDown(usageScrollController.dispose);

    await _pumpSidebar(
      tester,
      height: 300,
      expanded: true,
      fraction: 0.8,
      projects: SingleChildScrollView(
        controller: projectsScrollController,
        child: const SizedBox(height: 500),
      ),
      agentUsage: SingleChildScrollView(
        controller: usageScrollController,
        child: const SizedBox(height: 500),
      ),
    );

    expect(
      tester
          .getSize(find.byKey(const ValueKey('project-agent-sidebar-projects')))
          .height,
      IdeMetrics.projectsPaneMinHeight,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('project-agent-sidebar-usage')))
          .height,
      300 - IdeSpacing.space8 - IdeMetrics.projectsPaneMinHeight,
    );
    expect(projectsScrollController.position.maxScrollExtent, greaterThan(0));
    expect(usageScrollController.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  for (final scenario in <({double height, double textScale, bool expanded})>[
    (height: 220, textScale: 2, expanded: true),
    (height: 280, textScale: 1.8, expanded: false),
    (height: 720, textScale: 1.4, expanded: true),
  ]) {
    testWidgets('${scenario.height}px、${scenario.textScale}x 文字下不溢出', (
      tester,
    ) async {
      await _pumpSidebar(
        tester,
        height: scenario.height,
        expanded: scenario.expanded,
        projects: _ScrollableTextRegion(
          label: 'Projects',
          textScale: scenario.textScale,
        ),
        agentUsage: _ScrollableTextRegion(
          label: 'Agent usage summary and detailed statistics',
          textScale: scenario.textScale,
        ),
      );

      expect(find.byType(PanelCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpSidebar(
  WidgetTester tester, {
  required double height,
  required bool expanded,
  required Widget projects,
  required Widget agentUsage,
  double? fraction,
  ValueChanged<double>? onFractionChanged,
}) {
  return pumpIdeComponent(
    tester,
    size: Size(320, height),
    child: ProjectAgentSidebar(
      projects: projects,
      agentUsage: agentUsage,
      agentUsageExpanded: expanded,
      agentUsageHeightFraction: fraction,
      onAgentUsageHeightFractionChanged: onFractionChanged ?? (_) {},
    ),
  );
}

class _ScrollableTextRegion extends StatelessWidget {
  const _ScrollableTextRegion({required this.label, required this.textScale});

  final String label;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(IdeSpacing.space12),
          child: Text(List<String>.filled(20, label).join('\n')),
        ),
      ),
    );
  }
}
