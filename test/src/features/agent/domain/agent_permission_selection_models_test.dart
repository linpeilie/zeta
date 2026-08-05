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
      // selectedOptionId 回落到 protocol profile 后走内置预设 label。
      expect(workspace.displayLabel, 'Workspace write');

      const custom = AgentPermissionSelection(
        approvalPolicy: 'on-request',
        sandboxPolicy: 'workspaceWrite',
        permissionProfileId: ':team-safe',
      );
      expect(custom.matchedPresetId, isNull);
      expect(custom.protocolPermissionProfileId, ':team-safe');
      expect(custom.displayLabel, 'Workspace write · Ask first · :team-safe');
    });

    test('forProfileId maps known built-ins and keeps custom ids', () {
      final readOnly = AgentPermissionSelection.forProfileId(':read-only');
      expect(readOnly.permissionProfileId, ':read-only');
      expect(readOnly.sandboxPolicy, 'readOnly');
      expect(readOnly.approvalPolicy, 'on-request');
      expect(readOnly.matchedPresetId, 'readOnly');

      final custom = AgentPermissionSelection.forProfileId(':team-safe');
      expect(custom.permissionProfileId, ':team-safe');
      expect(custom.sandboxPolicy, 'workspaceWrite');
      expect(custom.protocolPermissionProfileId, ':team-safe');

      // 不以 `:` 开头的自定义 Codex profile 也必须保留，不得回落 :workspace。
      final teamSafe = AgentPermissionSelection.forProfileId('team-safe');
      expect(teamSafe.permissionProfileId, 'team-safe');
      expect(teamSafe.optionId, 'team-safe');
      expect(teamSafe.protocolPermissionProfileId, 'team-safe');
      expect(teamSafe.protocolPermissionProfileId, isNot(':workspace'));
    });

    test('forOptionId leaves Grok mode out of permissionProfileId', () {
      final auto = AgentPermissionSelection.forOptionId('auto');
      expect(auto.optionId, 'auto');
      expect(auto.permissionProfileId, isNull);
      // 无显式 profile 时，默认 approval/sandbox 可能匹配内置 preset；
      // forOptionId 本身不得把 auto 写入 permissionProfileId。
      expect(auto.permissionProfileId, isNot('auto'));
    });

    test('profile summary maps Codex ids to built-in preset labels', () {
      const named = AgentPermissionProfileSummary(
        id: ':workspace',
        allowed: true,
        description: 'Server description',
      );
      expect(named.displayName, 'Server description');
      expect(named.matchedPreset?.id, 'workspace');

      // Codex list 常无 description：回落到内置预设文案。
      const bareWorkspace = AgentPermissionProfileSummary(
        id: ':workspace',
        allowed: true,
      );
      expect(bareWorkspace.displayName, 'Workspace write');
      expect(bareWorkspace.displaySubtitle, 'Ask first');

      const bareReadOnly = AgentPermissionProfileSummary(
        id: ':read-only',
        allowed: true,
      );
      expect(bareReadOnly.displayName, 'Read only');
      expect(bareReadOnly.displaySubtitle, 'Ask first');
      expect(bareReadOnly.matchedPreset?.sandboxPolicy, 'readOnly');

      const bareFullAccess = AgentPermissionProfileSummary(
        id: ':danger-full-access',
        allowed: true,
      );
      expect(bareFullAccess.displayName, 'Full access');
      expect(bareFullAccess.displaySubtitle, 'Never ask');
      expect(bareFullAccess.matchedPreset?.id, 'fullAccess');
      expect(bareFullAccess.matchedPreset?.sandboxPolicy, 'dangerFullAccess');

      final fullAccessSelection = AgentPermissionSelection.forProfileId(
        ':danger-full-access',
      );
      expect(fullAccessSelection.approvalPolicy, 'never');
      expect(fullAccessSelection.sandboxPolicy, 'dangerFullAccess');
      expect(fullAccessSelection.matchedPresetId, 'fullAccess');

      const custom = AgentPermissionProfileSummary(
        id: ':team-safe',
        allowed: false,
      );
      expect(custom.displayName, 'team-safe');
      expect(custom.displaySubtitle, ':team-safe');
      expect(custom.matchedPreset, isNull);
    });
  });
}
