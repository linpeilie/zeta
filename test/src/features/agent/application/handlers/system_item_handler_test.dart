import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('SystemItemHandler 接受当前 thread 事件', () {
    const handler = SystemItemHandler();
    final reduction = handler.handle(
      AgentSystemItemEvent(
        entry: const AgentHistoryEventEntry(
          id: 'sys',
          kind: AgentHistoryEventKind.system,
          title: 'note',
        ),
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
