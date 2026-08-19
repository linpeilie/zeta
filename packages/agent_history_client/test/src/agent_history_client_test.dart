// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:agent_history_client/agent_history_client.dart';
import 'package:test/test.dart';

void main() {
  group('AgentHistoryClient', () {
    test('can be instantiated', () {
      expect(AgentHistoryClient(), isNotNull);
    });
  });
}
