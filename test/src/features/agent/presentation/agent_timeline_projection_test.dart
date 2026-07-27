import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';

void main() {
  group('projectAgentTimelineViewportItems', () {
    test('按 Load older → standby → history → live 顺序投影', () {
      final items = projectAgentTimelineViewportItems(
        hasOlderTurns: true,
        standbyTurn: _turn(id: 'standby', standby: true, withEntry: true),
        visibleHistoryTurns: <AgentConversationTurnGroup>[
          _turn(id: 'h1'),
          _turn(id: 'h2'),
        ],
        liveTurn: _turn(id: 'live'),
      );

      expect(items.map((item) => item.id).toList(growable: false), <String>[
        'load-older',
        'standby-turn-standby',
        'history-turn-h1',
        'history-turn-h2',
        'live-turn-live',
      ]);
    });

    test('空 standby 与无更早历史时不生成对应 item', () {
      final items = projectAgentTimelineViewportItems(
        hasOlderTurns: false,
        standbyTurn: _turn(id: 'standby', standby: true, withEntry: false),
        visibleHistoryTurns: const <AgentConversationTurnGroup>[],
        liveTurn: null,
      );
      expect(items, isEmpty);
    });

    test('viewport key 稳定且可反查', () {
      const load = AgentLoadOlderViewportItem();
      final turn = AgentTurnViewportItem(
        turnId: 't1',
        isLive: false,
        isStandby: false,
      );
      expect(
        agentTimelineViewportItemKey(load),
        'timeline-viewport-load-older',
      );
      expect(
        agentTimelineViewportItemKey(turn),
        'timeline-viewport-history-turn-t1',
      );
    });
  });
}

AgentConversationTurnGroup _turn({
  required String id,
  bool standby = false,
  bool withEntry = true,
}) {
  return AgentConversationTurnGroup(
    id: id,
    status: AgentHistoryTurnStatus.completed,
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
