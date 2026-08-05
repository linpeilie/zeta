import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentPermissionSelectionSnapshot', () {
    test('migrates removed on-failure policy and preserves stable values', () {
      // Arrange
      const legacy = 'on-failure';

      // Act
      final migrated = AgentPermissionSelectionSnapshot.normalizeApprovalPolicy(
        legacy,
      );

      // Assert
      expect(migrated, 'on-request');
      expect(
        AgentPermissionSelectionSnapshot.normalizeApprovalPolicy('never'),
        'never',
      );
      expect(
        AgentPermissionSelectionSnapshot.normalizePersistedApprovalPolicy(null),
        isNull,
      );
    });

    test('trigger labels use short option names without approval subtitle', () {
      // 默认策略匹配 :workspace 内置预设 → 触发器短标签。
      const workspace = AgentPermissionSelectionSnapshot();
      expect(workspace.protocolPermissionProfileId, ':workspace');
      expect(workspace.displayLabel, 'Workspace write');
      expect(workspace.displayLabel, isNot(contains('Ask first')));

      // 显式 built-in option 同样短标签。
      final readOnly = AgentPermissionSelectionSnapshot.forProfileId(
        ':read-only',
      );
      expect(readOnly.displayLabel, 'Read only');
      expect(readOnly.displayLabel, isNot(contains('·')));

      final fullAccess = AgentPermissionSelectionSnapshot.forProfileId(
        ':danger-full-access',
      );
      expect(fullAccess.displayLabel, 'Full access');

      // 自定义 profile：selectedOptionId 回落到 profile id，触发器用短 id。
      const custom = AgentPermissionSelectionSnapshot(
        approvalPolicy: 'on-request',
        sandboxPolicy: 'workspaceWrite',
        permissionProfileId: ':team-safe',
      );
      expect(custom.matchedPresetId, isNull);
      expect(custom.protocolPermissionProfileId, ':team-safe');
      expect(custom.displayLabel, ':team-safe');
      expect(custom.displayLabel, isNot(contains('Ask first')));
    });

    test('Grok option ids use short labels and never invent Default', () {
      const ask = AgentPermissionProfileSummary(
        id: 'ask',
        allowed: true,
        description: 'Ask',
      );
      const auto = AgentPermissionProfileSummary(
        id: 'auto',
        allowed: true,
        description: 'Auto',
      );
      const always = AgentPermissionProfileSummary(
        id: 'always-approve',
        allowed: true,
        description: 'Always approve',
      );
      expect(ask.displayName, 'Ask');
      expect(auto.displayName, 'Auto');
      expect(always.displayName, 'Always approve');

      // selection 回落：Grok option 不得被默认 approval/sandbox 显示成 Workspace write。
      final autoSelection = AgentPermissionSelectionSnapshot.forOptionId(
        'auto',
      );
      expect(autoSelection.displayLabel, 'auto');
      expect(autoSelection.displayLabel, isNot('Workspace write'));
      expect(autoSelection.permissionProfileId, isNull);

      const bareAsk = AgentPermissionProfileSummary(id: 'ask', allowed: true);
      expect(bareAsk.displayName, 'ask');
      expect(bareAsk.displayName.toLowerCase(), isNot('default'));
    });

    test('forProfileId maps known built-ins and keeps custom ids', () {
      final readOnly = AgentPermissionSelectionSnapshot.forProfileId(
        ':read-only',
      );
      expect(readOnly.permissionProfileId, ':read-only');
      expect(readOnly.sandboxPolicy, 'readOnly');
      expect(readOnly.approvalPolicy, 'on-request');
      expect(readOnly.matchedPresetId, 'readOnly');

      final custom = AgentPermissionSelectionSnapshot.forProfileId(
        ':team-safe',
      );
      expect(custom.permissionProfileId, ':team-safe');
      expect(custom.sandboxPolicy, 'workspaceWrite');
      expect(custom.protocolPermissionProfileId, ':team-safe');

      // 不以 `:` 开头的自定义 Codex profile 也必须保留，不得回落 :workspace。
      final teamSafe = AgentPermissionSelectionSnapshot.forProfileId(
        'team-safe',
      );
      expect(teamSafe.permissionProfileId, 'team-safe');
      expect(teamSafe.optionId, 'team-safe');
      expect(teamSafe.protocolPermissionProfileId, 'team-safe');
      expect(teamSafe.protocolPermissionProfileId, isNot(':workspace'));
    });

    test('forOptionId leaves Grok mode out of permissionProfileId', () {
      final auto = AgentPermissionSelectionSnapshot.forOptionId('auto');
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

      final fullAccessSelection = AgentPermissionSelectionSnapshot.forProfileId(
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
