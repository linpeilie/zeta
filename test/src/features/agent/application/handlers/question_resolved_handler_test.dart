import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('QuestionResolvedHandler 接受当前 thread 事件', () {
    const handler = QuestionResolvedHandler();
    final reduction = handler.handle(
      const AgentQuestionResolvedEvent(
        requestId: 'q1',
        threadId: handlerTestThreadId,
      ),
      handlerTestInitialState,
      handlerTestContext(),
      handlerTestScratch(),
    );
    expect(reduction.accepted, isTrue);
  });
}
