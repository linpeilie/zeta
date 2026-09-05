import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';

import 'handler_test_harness.dart';

void main() {
  test('SessionStartedHandler 接受当前 thread 事件', () {
    const handler = SessionStartedHandler();
    final reduction = handler.handle(
      const AgentSessionStartedEvent(
        AgentSession(
          id: handlerTestThreadId,
          providerId: defaultAgentProviderId,
        ),
      ),
      handlerTestInitialState,
      handlerTestContext(),
      handlerTestScratch(),
    );
    expect(reduction.accepted, isTrue);
  });
}
