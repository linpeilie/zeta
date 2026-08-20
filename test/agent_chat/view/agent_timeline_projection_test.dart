import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/agent_chat/agent_chat.dart';

void main() {
  group('projectTimelineItems', () {
    test('returns the visible history window', () {
      const history = AgentConversationHistoryState(
        visibleTurns: <AgentConversationTurnGroup>[
          AgentConversationTurnGroup(id: 'turn-1'),
          AgentConversationTurnGroup(id: 'turn-2'),
        ],
      );
      expect(projectTimelineItems(history), history.visibleTurns);
    });
  });
}
