import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/ui/features/ide/views/project_agent_sidebar.dart';

import '../../../core/ide_component_test_harness.dart';

void main() {
  testWidgets('只有一个卡片、统计固定底部且不显示拖动手柄', (tester) async {
    await _pumpSidebar(
      tester,
      height: 520,
      projects: const ColoredBox(
        key: ValueKey('projects-content'),
        color: Colors.blue,
      ),
      agentUsage: const SizedBox(key: ValueKey('usage-content'), height: 88),
    );

    expect(find.byType(PanelCard), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-usage-resize-handle')),
      findsNothing,
    );
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

  testWidgets('统计摘要超出上限时在自身区域滚动而不挤压 Projects', (tester) async {
    await _pumpSidebar(
      tester,
      height: 300,
      projects: const ColoredBox(color: Colors.blue),
      agentUsage: const SizedBox(key: ValueKey('usage-content'), height: 400),
    );

    final projects = find.byKey(
      const ValueKey('project-agent-sidebar-projects'),
    );
    final usage = find.byKey(const ValueKey('project-agent-sidebar-usage'));
    expect(
      tester.getSize(projects).height,
      greaterThanOrEqualTo(IdeMetrics.projectsPaneMinHeight),
    );
    expect(
      tester.getSize(usage).height,
      closeTo(300 - IdeMetrics.projectsPaneMinHeight, 0.01),
    );
    expect(
      find.descendant(
        of: usage,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.vertical,
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('统计内容高度变化时同步让 Projects 伸缩', (tester) async {
    final usageHeight = ValueNotifier<double>(120);
    addTearDown(usageHeight.dispose);

    await pumpIdeComponent(
      tester,
      size: const Size(320, 600),
      child: ValueListenableBuilder<double>(
        valueListenable: usageHeight,
        builder: (context, value, _) => ProjectAgentSidebar(
          projects: const ColoredBox(color: Colors.blue),
          agentUsage: SizedBox(height: value),
        ),
      ),
    );

    expect(
      tester
          .getSize(find.byKey(const ValueKey('project-agent-sidebar-usage')))
          .height,
      120,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('project-agent-sidebar-projects')))
          .height,
      480,
    );

    usageHeight.value = 260;
    await tester.pump();
    expect(
      tester
          .getSize(find.byKey(const ValueKey('project-agent-sidebar-usage')))
          .height,
      260,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('project-agent-sidebar-projects')))
          .height,
      340,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSidebar(
  WidgetTester tester, {
  required double height,
  required Widget projects,
  required Widget agentUsage,
}) {
  return pumpIdeComponent(
    tester,
    size: Size(320, height),
    child: ProjectAgentSidebar(projects: projects, agentUsage: agentUsage),
  );
}
