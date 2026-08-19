// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:agent_config_client/agent_config_client.dart';
import 'package:test/test.dart';

void main() {
  group('AgentConfigClient', () {
    test('can be instantiated', () {
      expect(AgentConfigClient(), isNotNull);
    });
  });
}
