import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentPermissionSelection', () {
    test('migrates removed on-failure policy and preserves stable values', () {
      // Arrange
      const legacy = 'on-failure';

      // Act
      final migrated = AgentPermissionSelection.normalizeApprovalPolicy(legacy);

      // Assert
      expect(migrated, 'on-request');
      expect(
        AgentPermissionSelection.normalizeApprovalPolicy('never'),
        'never',
      );
      expect(
        AgentPermissionSelection.normalizePersistedApprovalPolicy(null),
        isNull,
      );
    });
  });
}
