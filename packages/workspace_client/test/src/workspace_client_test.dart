// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:test/test.dart';
import 'package:workspace_client/workspace_client.dart';

void main() {
  group('WorkspaceClient', () {
    test('can be instantiated', () {
      expect(WorkspaceClient(), isNotNull);
    });
  });
}
