import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('TurnStartedHandler 接受当前 thread 事件', () {
    const handler = TurnStartedHandler();
    final reduction = handler.handle(
      const AgentTurnStartedEvent(
        AgentTurn(id: handlerTestTurnId, sessionId: handlerTestThreadId),
      ),
      handlerTestInitialState,
      handlerTestContext(),
      handlerTestScratch(),
    );
    expect(reduction.accepted, isTrue);
  });
}
