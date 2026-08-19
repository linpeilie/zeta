// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:test/test.dart';

void main() {
  group('AgentConversationRepository', () {
    test('can be instantiated', () {
      expect(AgentConversationRepository(), isNotNull);
    });
  });
}
