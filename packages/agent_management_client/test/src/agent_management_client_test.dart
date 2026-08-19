// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:agent_management_client/agent_management_client.dart';
import 'package:test/test.dart';

void main() {
  group('AgentManagementClient', () {
    test('can be instantiated', () {
      expect(AgentManagementClient(), isNotNull);
    });
  });
}
