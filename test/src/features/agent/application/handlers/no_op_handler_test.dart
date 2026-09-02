import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('NoOpHandler 对 archived/unarchived/deleted 不发布 UI', () {
    final scratch = handlerTestScratch();
    final context = handlerTestContext();
    for (final event in <AgentEvent>[
      const AgentThreadArchivedEvent(threadId: handlerTestThreadId),
      const AgentThreadUnarchivedEvent(threadId: handlerTestThreadId),
      const AgentThreadDeletedEvent(threadId: handlerTestThreadId),
    ]) {
      final reduction = NoOpHandler<AgentEvent>().handle(
        event,
        handlerTestInitialState,
        context,
        scratch,
      );
      expect(reduction.accepted, isTrue);
      expect(reduction.uiUpdate, isNull);
    }
  });
}
