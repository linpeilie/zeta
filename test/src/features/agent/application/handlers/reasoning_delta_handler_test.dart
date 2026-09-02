import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('ReasoningDeltaHandler 接受当前 thread 事件', () {
    const handler = ReasoningDeltaHandler();
    final reduction = handler.handle(
      const AgentReasoningDeltaEvent(
        itemId: 'r1',
        kind: AgentReasoningDeltaKind.summaryText,
        delta: 'x',
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
