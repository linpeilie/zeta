import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('PermissionRequestedHandler 接受当前 thread 事件', () {
    const handler = PermissionRequestedHandler();
    final reduction = handler.handle(
      AgentPermissionRequestedEvent(
        AgentPermissionRequest(
          id: 'p1',
          title: 'Run',
          kind: AgentPermissionKind.commandExecution,
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
