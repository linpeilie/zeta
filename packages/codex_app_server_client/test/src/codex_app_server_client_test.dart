// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:codex_app_server_client/codex_app_server_client.dart';
import 'package:test/test.dart';

void main() {
  group('CodexAppServerClient', () {
    test('can be instantiated', () {
      expect(CodexAppServerClient(), isNotNull);
    });
  });
}
