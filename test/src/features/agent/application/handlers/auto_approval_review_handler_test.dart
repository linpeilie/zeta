import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('AutoApprovalReviewHandler 接受当前 thread 事件', () {
    const handler = AutoApprovalReviewHandler();
    final reduction = handler.handle(
      const AgentAutoApprovalReviewEvent(
        threadId: handlerTestThreadId,
        turnId: handlerTestTurnId,
        reviewId: 'r1',
        status: 'denied',
      ),
      handlerTestInitialState,
      handlerTestContext(),
      handlerTestScratch(),
    );
    expect(reduction.accepted, isTrue);
  });
}
