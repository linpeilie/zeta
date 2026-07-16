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

    test('derives built-in permission profiles and readable labels', () {
      const workspace = AgentPermissionSelection();
      expect(workspace.protocolPermissionProfileId, ':workspace');
      expect(workspace.displayLabel, 'Workspace write · Ask first');

      const custom = AgentPermissionSelection(
        approvalPolicy: 'on-request',
        sandboxPolicy: 'workspaceWrite',
        permissionProfileId: ':team-safe',
      );
      expect(custom.matchedPresetId, isNull);
      expect(custom.protocolPermissionProfileId, ':team-safe');
      expect(custom.displayLabel, 'Workspace write · Ask first · :team-safe');
    });
  });
}
