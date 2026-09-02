import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('MessageUpdatedHandler 接受当前 thread 事件', () {
    const handler = MessageUpdatedHandler();
    final reduction = handler.handle(
      const AgentMessageUpdatedEvent(
        messageId: 'm1',
        text: 'done',
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
