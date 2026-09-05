import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('PermissionResolvedHandler 接受当前 thread 事件', () {
    const handler = PermissionResolvedHandler();
    final reduction = handler.handle(
      const AgentPermissionResolvedEvent(
        requestId: 'p1',
        threadId: handlerTestThreadId,
      ),
      handlerTestInitialState,
      handlerTestContext(),
      handlerTestScratch(),
    );
    expect(reduction.accepted, isTrue);
  });
}
