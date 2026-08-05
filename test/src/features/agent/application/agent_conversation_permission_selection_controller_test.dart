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
  _CodexLikeProvider()
    : super(
        config: AgentProviderConfig.defaultCodex,
        declaredCapabilities: AgentProviderCapabilities.codexAppServer,
      );
}
