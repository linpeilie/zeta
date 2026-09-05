import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('ModelReroutedHandler 接受当前 thread 事件', () {
    const handler = ModelReroutedHandler();
    final reduction = handler.handle(
      const AgentModelReroutedEvent(
        threadId: handlerTestThreadId,
        turnId: handlerTestTurnId,
        fromModel: 'a',
        toModel: 'b',
        reason: 'policy',
      ),
      handlerTestInitialState,
      handlerTestContext(),
      handlerTestScratch(),
    );
    expect(reduction.accepted, isTrue);
  });
}
