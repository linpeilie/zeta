import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('AgentQuestion models', () {
    test(
      'request keeps user questions independent from permission semantics',
      () {
        // Arrange & Act
        final request = AgentQuestionRequest(
          id: 'question-1',
          title: 'Choose scope',
          sessionId: 'thread-1',
          turnId: 'turn-1',
          questions: <AgentUserInputQaPair>[
            AgentUserInputQaPair(
              questionId: 'scope',
              question: 'Select scopes',
              allowMultiple: true,
              options: <String>['source', 'tests'],
            ),
          ],
        );

        // Assert
        expect(request.id, 'question-1');
        expect(request.questions.single.allowMultiple, isTrue);
        expect(request.questions.single.options, <String>['source', 'tests']);
      },
    );

    test('empty response represents protocol-level skip', () {
      // Arrange & Act
      final response = AgentQuestionResponse(requestId: 'question-1');

      // Assert
      expect(response.answers, isEmpty);
    });
  });
}
