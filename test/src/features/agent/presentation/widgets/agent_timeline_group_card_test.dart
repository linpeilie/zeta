import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/presentation/widgets/agent_timeline_group_card.dart';
import 'package:zeta_ui/zeta_ui.dart';

import '../../../../ui/core/ide_component_test_harness.dart';

void main() {
  testWidgets('命令组生成稳定 key 并由调用方拥有展开状态', (tester) async {
    var expanded = false;
    await pumpIdeComponent(
      tester,
      child: StatefulBuilder(
        builder: (context, setState) => AgentTimelineGroupCard(
          kind: AgentTimelineGroupKind.command,
          groupId: 'command-a',
          expanded: expanded,
          onToggle: () => setState(() => expanded = !expanded),
          titleSpan: const TextSpan(text: '1 次执行'),
          leadingIcon: Icons.segment_rounded,
          semanticLabel: '命令组',
          body: const Text('命令详情'),
        ),
      ),
    );

    const headerKey = ValueKey<String>('agent-command-group-header-command-a');
    const bodyKey = ValueKey<String>('agent-command-group-body-command-a');
    const summaryKey = ValueKey<String>(
      'agent-command-group-summary-command-a',
    );
    expect(find.byKey(headerKey), findsOneWidget);
    expect(find.byKey(summaryKey), findsOneWidget);
    expect(find.byKey(bodyKey), findsNothing);

    await tester.tap(find.byKey(headerKey));
    await tester.pumpAndSettle();

    expect(expanded, isTrue);
    expect(find.byKey(bodyKey), findsOneWidget);
    expect(find.text('命令详情'), findsOneWidget);
  });

  testWidgets('文件编辑组保留既有 key 与统一正文间距', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const AgentTimelineGroupCard(
        kind: AgentTimelineGroupKind.fileEdit,
        groupId: 'edit-a',
        expanded: true,
        onToggle: _noop,
        titleSpan: TextSpan(
          children: <InlineSpan>[
            TextSpan(text: '2 个文件'),
            TextSpan(text: '  +3 −1'),
          ],
        ),
        leadingIcon: Icons.edit_note_rounded,
        semanticLabel: '文件编辑组',
        body: Text('文件详情'),
      ),
    );

    const headerKey = ValueKey<String>('agent-file-edit-group-header-edit-a');
    const bodyKey = ValueKey<String>('agent-file-edit-group-body-edit-a');
    const summaryKey = ValueKey<String>('agent-file-edit-group-summary-edit-a');
    expect(find.byKey(headerKey), findsOneWidget);
    expect(find.byKey(summaryKey), findsOneWidget);
    final bodyPadding = tester.widget<Padding>(find.byKey(bodyKey));
    expect(
      bodyPadding.padding,
      const EdgeInsets.only(top: IdeSpacing.space8, left: IdeSpacing.space20),
    );
    expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
  });
}

void _noop() {}
