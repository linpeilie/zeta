// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:grok_acp_client/grok_acp_client.dart';
import 'package:test/test.dart';

void main() {
  group('GrokAcpClient', () {
    test('can be instantiated', () {
      expect(GrokAcpClient(), isNotNull);
    });
  });
}
