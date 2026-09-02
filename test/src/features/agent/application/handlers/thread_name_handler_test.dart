import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('ThreadNameHandler 接受当前 thread 事件', () {
    const handler = ThreadNameHandler();
    final reduction = handler.handle(
      const AgentThreadNameUpdatedEvent(
        threadId: handlerTestThreadId,
        threadName: 'Renamed',
      ),
      handlerTestInitialState,
      handlerTestContext(),
      handlerTestScratch(),
    );
    expect(reduction.accepted, isTrue);
  });
}
