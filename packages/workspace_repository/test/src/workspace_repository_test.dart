// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:test/test.dart';
import 'package:workspace_repository/workspace_repository.dart';

void main() {
  group('WorkspaceRepository', () {
    test('can be instantiated', () {
      expect(WorkspaceRepository(), isNotNull);
    });
  });
}
