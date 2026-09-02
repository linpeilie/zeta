import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('TokenUsageHandler 接受当前 thread 事件', () {
    const handler = TokenUsageHandler();
    final reduction = handler.handle(
      const AgentTokenUsageEvent(
        tokenUsage: AgentTokenUsage(totalTokens: 1),
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
