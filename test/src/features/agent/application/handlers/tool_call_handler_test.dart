import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('ToolCallHandler 接受当前 thread 事件', () {
    const handler = ToolCallHandler();
    final reduction = handler.handle(
      const AgentToolCallEvent(
        AgentToolCall(
          id: 't1',
          title: 'Run',
          status: AgentToolStatus.completed,
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
