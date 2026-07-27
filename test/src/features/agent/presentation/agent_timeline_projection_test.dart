import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';

void main() {
  group('projectAgentTimelineViewportItems', () {
    test('按 standby → history → live 顺序投影', () {
      final items = projectAgentTimelineViewportItems(
        standbyTurn: _turn(id: 'standby', standby: true, withEntry: true),
        visibleHistoryTurns: <AgentConversationTurnGroup>[
          _turn(id: 'h1'),
          _turn(id: 'h2'),
        ],
        liveTurn: _turn(id: 'live'),
        resolveBlocks: _blocks,
      );

      expect(items.map((item) => item.id).toList(growable: false), <String>[
        'standby-block-standby-message-standby-msg',
        'history-block-h1-message-h1-msg',
        'history-footer-h1',
        'history-block-h2-message-h2-msg',
        'history-footer-h2',
        'live-block-live-message-live-msg',
        'live-footer-live',
      ]);
    });

    test('空 standby 时不生成对应 item', () {
      final items = projectAgentTimelineViewportItems(
        standbyTurn: _turn(id: 'standby', standby: true, withEntry: false),
        visibleHistoryTurns: const <AgentConversationTurnGroup>[],
        liveTurn: null,
        resolveBlocks: _blocks,
      );
      expect(items, isEmpty);
    });

    test('running live turn 在 block 与 footer 间生成 activity item', () {
      final live = _turn(id: 'live', status: AgentHistoryTurnStatus.running);
      final items = projectAgentTimelineViewportItems(
        standbyTurn: null,
        visibleHistoryTurns: const <AgentConversationTurnGroup>[],
        liveTurn: live,
        resolveBlocks: _blocks,
      );

      expect(items.map((item) => item.id).toList(growable: false), <String>[
        'live-block-live-message-live-msg',
        'live-activity-live',
        'live-footer-live',
      ]);
    });

    test('viewport key 稳定且包含 turn/block 身份', () {
      final turn = _turn(id: 't1');
      final block = _blocks(turn).single;
      final item = AgentBlockViewportItem(
        turn: turn,
        block: block,
        isLive: false,
      );
      expect(
        agentTimelineViewportItemKey(item),
        'timeline-viewport-history-block-t1-message-t1-msg',
      );
    });
  });
}

AgentConversationTurnGroup _turn({
  required String id,
  bool standby = false,
  bool withEntry = true,
  AgentHistoryTurnStatus status = AgentHistoryTurnStatus.completed,
}) {
  return AgentConversationTurnGroup(
    id: id,
    status: status,
    isStandby: standby,
    entries: withEntry
        ? <AgentTimelineEntry>[
            AgentMessageTimelineEntry(
              message: AgentConversationMessage(
                id: '$id-msg',
                role: AgentMessageRole.agent,
                text: 'hello $id',
              ),
            ),
          ]
        : const <AgentTimelineEntry>[],
  );
}

List<AgentTimelineRenderBlock> _blocks(AgentConversationTurnGroup turn) {
  return buildAgentTimelineRenderBlocks(turnId: turn.id, entries: turn.entries);
}
