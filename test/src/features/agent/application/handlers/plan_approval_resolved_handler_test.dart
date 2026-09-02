import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('PlanApprovalResolvedHandler 接受当前 thread 事件', () {
    const handler = PlanApprovalResolvedHandler();
    final reduction = handler.handle(
      const AgentPlanApprovalResolvedEvent(
        requestId: 'pa1',
        sessionId: handlerTestThreadId,
      ),
      handlerTestInitialState,
      handlerTestContext(),
      handlerTestScratch(),
    );
    expect(reduction.accepted, isTrue);
  });
}
