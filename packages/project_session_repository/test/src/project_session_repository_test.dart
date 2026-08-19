// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:project_session_repository/project_session_repository.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectSessionRepository', () {
    test('can be instantiated', () {
      expect(ProjectSessionRepository(), isNotNull);
    });
  });
}
