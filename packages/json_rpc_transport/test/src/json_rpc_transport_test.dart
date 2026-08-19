// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:json_rpc_transport/json_rpc_transport.dart';
import 'package:test/test.dart';

void main() {
  group('JsonRpcTransport', () {
    test('can be instantiated', () {
      expect(JsonRpcTransport(), isNotNull);
    });
  });
}
