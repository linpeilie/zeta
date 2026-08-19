// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:test/test.dart';

void main() {
  group('AgentProviderRepository', () {
    test('can be instantiated', () {
      expect(AgentProviderRepository(), isNotNull);
    });
  });
}
