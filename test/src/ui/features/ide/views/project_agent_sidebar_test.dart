import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/features/ide/views/project_agent_sidebar.dart';

import '../../../core/ide_component_test_harness.dart';

void main() {
  testWidgets('折叠态只有一个卡片、统计固定底部且不显示拖动手柄', (tester) async {
    await _pumpSidebar(
      tester,
      height: 520,
      expanded: false,
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

  testWidgets('展开态移除分隔手柄并按统计内容自然高度布局', (tester) async {
    await _pumpSidebar(
      tester,
      height: 600,
      expanded: true,
      projects: const ColoredBox(color: Colors.blue),
      agentUsage: const SizedBox(key: ValueKey('usage-content'), height: 236),
    );

    final projects = find.byKey(
      const ValueKey('project-agent-sidebar-projects'),
    );
    final usage = find.byKey(const ValueKey('project-agent-sidebar-usage'));
    expect(tester.getSize(usage).height, 236);
    expect(tester.getSize(projects).height, 600 - 236);
    expect(
      tester.getTopLeft(usage).dy,
      closeTo(tester.getBottomLeft(projects).dy, 0.01),
    );
    expect(
      find.byKey(const ValueKey('agent-usage-resize-handle')),
      findsNothing,
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
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开态内容高度变化时同步让 Projects 伸缩', (tester) async {
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
          agentUsageExpanded: true,
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
  required bool expanded,
  required Widget projects,
  required Widget agentUsage,
}) {
  return pumpIdeComponent(
    tester,
    size: Size(320, height),
    child: ProjectAgentSidebar(
      projects: projects,
      agentUsage: agentUsage,
      agentUsageExpanded: expanded,
    ),
  );
}
