// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:project_session_client/project_session_client.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectSessionClient', () {
    test('can be instantiated', () {
      expect(ProjectSessionClient(), isNotNull);
    });
  });
}
