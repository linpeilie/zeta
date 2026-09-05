import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('TurnFileChangesHandler 接受当前 thread 事件', () {
    const handler = TurnFileChangesHandler();
    final reduction = handler.handle(
      AgentTurnFileChangesEvent(
        sessionId: handlerTestThreadId,
        turnId: handlerTestTurnId,
        snapshot: AgentFileChangeSnapshot(
          revision: 1,
          replayability: AgentFileChangeReplayability.liveOnly,
          changes: <AgentFileChange>[],
        ),
      ),
      handlerTestInitialState,
      handlerTestContext(),
      handlerTestScratch(),
    );
    expect(reduction.accepted, isTrue);
  });
}
