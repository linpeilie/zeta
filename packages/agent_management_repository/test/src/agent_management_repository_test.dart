// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:test/test.dart';

void main() {
  group('AgentManagementRepository', () {
    test('can be instantiated', () {
      expect(AgentManagementRepository(), isNotNull);
    });
  });
}
