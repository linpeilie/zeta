import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('StatusHandler 接受当前 thread 事件', () {
    const handler = StatusHandler();
    final reduction = handler.handle(
      const AgentStatusEvent(AgentProviderStatus.idle()),
      handlerTestInitialState,
      handlerTestContext(),
      handlerTestScratch(),
    );
    expect(reduction.accepted, isTrue);
  });
}
