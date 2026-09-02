import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'handler_test_harness.dart';

void main() {
  test('QuestionRequestedHandler 接受当前 thread 事件', () {
    const handler = QuestionRequestedHandler();
    final reduction = handler.handle(
      AgentQuestionRequestedEvent(
        AgentQuestionRequest(
          id: 'q1',
          title: 'Q',
          questions: const <AgentUserInputQaPair>[
            AgentUserInputQaPair(questionId: 'q', question: '?'),
          ],
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
