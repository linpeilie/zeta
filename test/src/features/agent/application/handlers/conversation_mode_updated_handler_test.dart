import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('ConversationModeUpdatedHandler 接受当前 thread 事件', () {
    const handler = ConversationModeUpdatedHandler();
    final reduction = handler.handle(
      const AgentConversationModeUpdatedEvent(
        sessionId: handlerTestThreadId,
        modeId: AgentConversationModeId.plan,
      ),
      handlerTestInitialState,
      handlerTestContext(),
      handlerTestScratch(),
    );
    expect(reduction.accepted, isTrue);
  });
}
