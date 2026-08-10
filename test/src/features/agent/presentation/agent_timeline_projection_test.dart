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
        'turn-block-h1-message-h1-msg',
        'turn-footer-h1',
        'turn-block-h2-message-h2-msg',
        'turn-footer-h2',
        'turn-block-live-message-live-msg',
        'turn-footer-live',
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
        'turn-block-live-message-live-msg',
        'live-activity-live',
        'turn-footer-live',
      ]);
    });

    test('showLiveActivity=false 时不生成 live 活动条', () {
      final live = _turn(id: 'live', status: AgentHistoryTurnStatus.running);
      final items = projectAgentTimelineViewportItems(
        standbyTurn: null,
        visibleHistoryTurns: const <AgentConversationTurnGroup>[],
        liveTurn: live,
        resolveBlocks: _blocks,
        showLiveActivity: false,
      );

      expect(items.map((item) => item.id).toList(growable: false), <String>[
        'turn-block-live-message-live-msg',
        'turn-footer-live',
      ]);
      expect(items.whereType<AgentLiveActivityViewportItem>(), isEmpty);
    });

    test('同一 turn 从 live 迁入 history 后保持 block 与 footer 身份', () {
      final turn = _turn(id: 't1', status: AgentHistoryTurnStatus.running);
      final liveItems = projectAgentTimelineViewportItems(
        standbyTurn: null,
        visibleHistoryTurns: const <AgentConversationTurnGroup>[],
        liveTurn: turn,
        resolveBlocks: _blocks,
      );
      final historyItems = projectAgentTimelineViewportItems(
        standbyTurn: null,
        visibleHistoryTurns: <AgentConversationTurnGroup>[_turn(id: 't1')],
        liveTurn: null,
        resolveBlocks: _blocks,
      );

      expect(
        liveItems
            .where((item) => item is! AgentLiveActivityViewportItem)
            .map((item) => item.id),
        historyItems.map((item) => item.id),
      );
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
        'timeline-viewport-turn-block-t1-message-t1-msg',
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
