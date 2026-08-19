// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:claude_code_client/claude_code_client.dart';
import 'package:test/test.dart';

void main() {
  group('ClaudeCodeClient', () {
    test('can be instantiated', () {
      expect(ClaudeCodeClient(), isNotNull);
    });
  });
}
