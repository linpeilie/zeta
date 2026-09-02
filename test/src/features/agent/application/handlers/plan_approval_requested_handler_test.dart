import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('PlanApprovalRequestedHandler 接受当前 thread 事件', () {
    const handler = PlanApprovalRequestedHandler();
    final reduction = handler.handle(
      AgentPlanApprovalRequestedEvent(
        AgentPlanApprovalRequest(
          id: 'pa1',
          title: 'Plan',
          markdown: 'Do it',
          sessionId: handlerTestThreadId,
          turnId: handlerTestTurnId,
        ),
      ),
      handlerTestInitialState,
      handlerTestContext(),
      handlerTestScratch(),
    );
    expect(reduction.accepted, isTrue);
  });
}
