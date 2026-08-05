import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_permission_selection_controller.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

import '../../../testing/ide_test_harness.dart';

void main() {
  group('AgentConversationPermissionSelectionController', () {
    test('seeds optionId from config without provider kind branch', () {
      final controller = AgentConversationPermissionSelectionController(
        persistSelection: (_) async {},
      );
      controller.seedFromConfig(
        AgentProviderConfig.defaultGrok.copyWith(
          selectedPermissionOptionId: 'auto',
        ),
      );

      expect(controller.selectedProfileId, 'auto');
      expect(controller.selection.optionId, 'auto');
    });

    test(
      'selectProfile uses forOptionId when profile selection unsupported',
      () async {
        AgentPermissionSelection? persisted;
        final controller = AgentConversationPermissionSelectionController(
          persistSelection: (selection) async {
            persisted = selection;
          },
        );
        final provider = _GrokLikeProvider();
        controller.seedFromConfig(AgentProviderConfig.defaultGrok);
        controller.bindProvider(provider);

        await controller.selectProfile(
          const AgentPermissionProfileSummary(
            id: 'always-approve',
            allowed: true,
            description: 'Always approve',
          ),
        );

        expect(persisted?.optionId, 'always-approve');
        expect(persisted?.permissionProfileId, isNull);
        expect(provider.lastSelection?.optionId, 'always-approve');
      },
    );

    test(
      'refreshProfiles always goes through listPermissionProfiles',
      () async {
        final provider = _GrokLikeProvider();
        final controller = AgentConversationPermissionSelectionController(
          persistSelection: (_) async {},
        );
        controller.bindProvider(provider);
        await controller.refreshProfiles();

        expect(provider.listCalls, 1);
        expect(controller.profiles.map((p) => p.id), contains('ask'));
      },
    );

    test(
      'selectProfile expands Codex profile when profile selection supported',
      () async {
        AgentPermissionSelection? persisted;
        final controller = AgentConversationPermissionSelectionController(
          persistSelection: (selection) async {
            persisted = selection;
          },
        );
        final provider = _CodexLikeProvider();
        controller.seedFromConfig(AgentProviderConfig.defaultCodex);
        controller.bindProvider(provider);

        await controller.selectProfile(
          const AgentPermissionProfileSummary(
            id: ':workspace',
            allowed: true,
            description: 'Workspace write',
          ),
        );

        expect(persisted?.optionId, ':workspace');
        expect(persisted?.permissionProfileId, ':workspace');
        expect(persisted?.sandboxPolicy, 'workspaceWrite');
      },
    );

    test(
      'seeds custom Codex profile team-safe without startsWith or preset guess',
      () {
        final controller = AgentConversationPermissionSelectionController(
          persistSelection: (_) async {},
        );
        controller.seedFromConfig(
          AgentProviderConfig.defaultCodex.copyWith(
            selectedPermissionOptionId: 'team-safe',
            selectedPermissionProfileId: 'team-safe',
            selectedApprovalPolicy: 'on-request',
            selectedSandboxPolicy: 'workspaceWrite',
          ),
        );

        expect(controller.selectedProfileId, 'team-safe');
        expect(controller.selection.optionId, 'team-safe');
        expect(controller.selection.permissionProfileId, 'team-safe');
        expect(controller.selection.protocolPermissionProfileId, 'team-safe');
        expect(
          controller.selection.protocolPermissionProfileId,
          isNot(':workspace'),
        );
      },
    );

    test(
      'bind Codex keeps custom team-safe profile instead of inventing :workspace',
      () {
        final controller = AgentConversationPermissionSelectionController(
          persistSelection: (_) async {},
        );
        final provider = _CodexLikeProvider();
        controller.seedFromConfig(
          AgentProviderConfig.defaultCodex.copyWith(
            selectedPermissionOptionId: 'team-safe',
            selectedPermissionProfileId: 'team-safe',
            selectedApprovalPolicy: 'on-request',
            selectedSandboxPolicy: 'workspaceWrite',
          ),
        );
        controller.bindProvider(provider);

        expect(controller.selection.permissionProfileId, 'team-safe');
        expect(controller.selection.optionId, 'team-safe');
        expect(controller.selection.protocolPermissionProfileId, 'team-safe');
        expect(provider.lastSelection?.permissionProfileId, 'team-safe');
        expect(
          provider.lastSelection?.protocolPermissionProfileId,
          isNot(':workspace'),
        );
      },
    );

    test('Grok auto option is not written into permissionProfileId', () {
      final controller = AgentConversationPermissionSelectionController(
        persistSelection: (_) async {},
      );
      final provider = _GrokLikeProvider();
      controller.seedFromConfig(
        AgentProviderConfig.defaultGrok.copyWith(
          selectedPermissionOptionId: 'auto',
        ),
      );
      controller.bindProvider(provider);

      expect(controller.selection.optionId, 'auto');
      expect(controller.selection.permissionProfileId, isNull);
      expect(provider.lastSelection?.optionId, 'auto');
      expect(provider.lastSelection?.permissionProfileId, isNull);
    });

    test(
      'selectProfile for Grok auto keeps permissionProfileId null',
      () async {
        AgentPermissionSelection? persisted;
        final controller = AgentConversationPermissionSelectionController(
          persistSelection: (selection) async {
            persisted = selection;
          },
        );
        final provider = _GrokLikeProvider();
        controller.seedFromConfig(AgentProviderConfig.defaultGrok);
        controller.bindProvider(provider);

        await controller.selectProfile(
          const AgentPermissionProfileSummary(
            id: 'auto',
            allowed: true,
            description: 'Auto',
          ),
        );

        expect(persisted?.optionId, 'auto');
        expect(persisted?.permissionProfileId, isNull);
        expect(provider.lastSelection?.permissionProfileId, isNull);
      },
    );

    test('built-in Codex :read-only still expands via selectProfile', () async {
      AgentPermissionSelection? persisted;
      final controller = AgentConversationPermissionSelectionController(
        persistSelection: (selection) async {
          persisted = selection;
        },
      );
      final provider = _CodexLikeProvider();
      controller.seedFromConfig(AgentProviderConfig.defaultCodex);
      controller.bindProvider(provider);

      await controller.selectProfile(
        const AgentPermissionProfileSummary(
          id: ':read-only',
          allowed: true,
          description: 'Read only',
        ),
      );

      expect(persisted?.optionId, ':read-only');
      expect(persisted?.permissionProfileId, ':read-only');
      expect(persisted?.sandboxPolicy, 'readOnly');
      expect(persisted?.approvalPolicy, 'on-request');
    });

    test('persist and re-seed round-trips custom team-safe profile', () async {
      AgentPermissionSelection? persisted;
      final controller = AgentConversationPermissionSelectionController(
        persistSelection: (selection) async {
          persisted = selection;
        },
      );
      final provider = _CodexLikeProvider();
      controller.seedFromConfig(AgentProviderConfig.defaultCodex);
      controller.bindProvider(provider);

      await controller.selectProfile(
        const AgentPermissionProfileSummary(
          id: 'team-safe',
          allowed: true,
          description: 'Team safe',
        ),
      );

      expect(persisted?.permissionProfileId, 'team-safe');
      expect(persisted?.optionId, 'team-safe');

      // 模拟全局配置持久化与解码后的 seed。
      final savedConfig = AgentProviderConfig.defaultCodex.copyWith(
        selectedApprovalPolicy: persisted!.approvalPolicy,
        selectedSandboxPolicy: persisted!.sandboxPolicy,
        selectedPermissionProfileId: persisted!.permissionProfileId,
        selectedPermissionOptionId: persisted!.selectedOptionId,
      );
      final encoded = savedConfig.toJson();
      final decoded = AgentProviderConfig.tryDecode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.selectedPermissionProfileId, 'team-safe');
      expect(decoded.selectedPermissionOptionId, 'team-safe');

      final restored = AgentConversationPermissionSelectionController(
        persistSelection: (_) async {},
      );
      restored.seedFromConfig(decoded);
      restored.bindProvider(_CodexLikeProvider());

      expect(restored.selection.permissionProfileId, 'team-safe');
      expect(restored.selection.optionId, 'team-safe');
      expect(restored.selection.protocolPermissionProfileId, 'team-safe');
      expect(
        restored.selection.protocolPermissionProfileId,
        isNot(':workspace'),
      );
    });
  });
}

class _GrokLikeProvider extends FakeAgentProvider {
  AgentPermissionSelection? lastSelection;
  int listCalls = 0;

  _GrokLikeProvider()
    : super(
        config: AgentProviderConfig.defaultGrok,
        declaredCapabilities: AgentProviderCapabilities.grokAcp,
      );

  @override
  void updatePermissionSelection(AgentPermissionSelection selection) {
    lastSelection = selection;
  }

  @override
  Future<List<AgentPermissionProfileSummary>> listPermissionProfiles() async {
    listCalls += 1;
    return const <AgentPermissionProfileSummary>[
      AgentPermissionProfileSummary(
        id: 'ask',
        allowed: true,
        description: 'Ask',
      ),
      AgentPermissionProfileSummary(
        id: 'always-approve',
        allowed: true,
        description: 'Always approve',
      ),
    ];
  }
}

class _CodexLikeProvider extends FakeAgentProvider {
  AgentPermissionSelection? lastSelection;

  _CodexLikeProvider()
    : super(
        config: AgentProviderConfig.defaultCodex,
        declaredCapabilities: AgentProviderCapabilities.codexAppServer,
      );

  @override
  void updatePermissionSelection(AgentPermissionSelection selection) {
    lastSelection = selection;
  }
}
