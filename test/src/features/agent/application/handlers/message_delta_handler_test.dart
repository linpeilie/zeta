import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('MessageDeltaHandler 接受当前 thread 事件', () {
    const handler = MessageDeltaHandler();
    final reduction = handler.handle(
      const AgentMessageDeltaEvent(
        messageId: 'm1',
        delta: 'x',
        role: AgentMessageRole.agent,
        sessionId: handlerTestThreadId,
        turnId: handlerTestTurnId,
      ),
      handlerTestInitialState,
      handlerTestContext(),
      handlerTestScratch(),
    );
    expect(reduction.accepted, isTrue);
  });
}
