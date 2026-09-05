import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('PlanUpdatedHandler 接受当前 thread 事件', () {
    const handler = PlanUpdatedHandler();
    final reduction = handler.handle(
      const AgentPlanUpdatedEvent(
        entries: <AgentPlanEntry>[AgentPlanEntry(content: 'Step')],
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
