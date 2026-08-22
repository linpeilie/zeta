import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_extent_descriptor.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';

void main() {
  final factory = AgentTimelineExtentDescriptorFactory();
  const layout = AgentTimelineLayoutContext(
    crossAxisExtent: 720,
    devicePixelRatio: 1,
    textScale: 1,
    localeKey: 'zh',
  );
  const expansion = (
    isCommandGroupExpanded: _neverExpanded,
    isFileEditItemExpanded: _neverExpanded,
    isPlanMessageInteractive: _neverExpanded,
  );

  test(
    'streaming message growth does not change sibling tool layoutRevision',
    () {
      final toolEntry = AgentToolTimelineEntry(
        toolCall: const AgentToolCall(
          id: 'tool-1',
          title: 'run tests',
          kind: AgentToolKind.execute,
          status: AgentToolStatus.completed,
          content: 'ok',
        ),
      );
      final messageV1 = AgentMessageTimelineEntry(
        message: const AgentConversationMessage(
          id: 'msg-1',
          role: AgentMessageRole.agent,
          text: 'Hello',
        ),
      );
      final messageV2 = AgentMessageTimelineEntry(
        message: const AgentConversationMessage(
          id: 'msg-1',
          role: AgentMessageRole.agent,
          text: 'Hello world',
        ),
      );

      final turnV1 = AgentConversationTurnGroup(
        id: 'live',
        status: AgentHistoryTurnStatus.running,
        isStandby: false,
        entries: <AgentTimelineEntry>[toolEntry, messageV1],
        renderRevision: 10,
      );
      final turnV2 = AgentConversationTurnGroup(
        id: 'live',
        status: AgentHistoryTurnStatus.running,
        isStandby: false,
        entries: <AgentTimelineEntry>[toolEntry, messageV2],
        // 整 turn 修订号继续涨，但 sibling tool 的 layoutRevision 不得跟涨。
        renderRevision: 11,
      );

      final toolBlock = AgentTimelineEntryRenderBlock(entry: toolEntry);
      final msgBlockV1 = AgentTimelineEntryRenderBlock(entry: messageV1);
      final msgBlockV2 = AgentTimelineEntryRenderBlock(entry: messageV2);

      final toolDesc1 = factory.describe(
        AgentBlockViewportItem(turn: turnV1, block: toolBlock, isLive: true),
        expansion: expansion,
        layoutContext: layout,
      );
      final toolDesc2 = factory.describe(
        AgentBlockViewportItem(turn: turnV2, block: toolBlock, isLive: true),
        expansion: expansion,
        layoutContext: layout,
      );
      final msgDesc1 = factory.describe(
        AgentBlockViewportItem(turn: turnV1, block: msgBlockV1, isLive: true),
        expansion: expansion,
        layoutContext: layout,
      );
      final msgDesc2 = factory.describe(
        AgentBlockViewportItem(turn: turnV2, block: msgBlockV2, isLive: true),
        expansion: expansion,
        layoutContext: layout,
      );

      expect(toolDesc1.layoutRevision, toolDesc2.layoutRevision);
      expect(msgDesc1.layoutRevision, isNot(msgDesc2.layoutRevision));
    },
  );

  test('plan message toggling to interactive card changes layoutRevision', () {
    const message = AgentConversationMessage(
      id: 'plan-1',
      role: AgentMessageRole.agent,
      text: '# Plan\n\n1. Inspect\n2. Update',
      kind: AgentMessageKind.plan,
    );
    final block = AgentTimelineEntryRenderBlock(
      entry: AgentMessageTimelineEntry(message: message),
    );
    final turn = AgentConversationTurnGroup(
      id: 'turn-1',
      isStandby: false,
      entries: <AgentTimelineEntry>[
        AgentMessageTimelineEntry(message: message),
      ],
    );
    final item = AgentBlockViewportItem(
      turn: turn,
      block: block,
      isLive: false,
    );

    final collapsed = factory.describe(
      item,
      expansion: expansion,
      layoutContext: layout,
    );
    final interactive = factory.describe(
      item,
      expansion: (
        isCommandGroupExpanded: _neverExpanded,
        isFileEditItemExpanded: _neverExpanded,
        isPlanMessageInteractive: _alwaysExpanded,
      ),
      layoutContext: layout,
    );

    // 折叠卡与带底部输入的交互卡高度差异巨大，缓存测量必须失效。
    expect(collapsed.layoutRevision, isNot(interactive.layoutRevision));
    expect(interactive.estimatedExtent, greaterThan(collapsed.estimatedExtent));
  });
}

bool _neverExpanded(String _) => false;

bool _alwaysExpanded(String _) => true;
