import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_corpus_port.dart';
import 'package:zeta/src/app/composition/workbench_session_providers.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_notifier.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_providers.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_entry_resources.dart';
import 'package:zeta/src/app/conversation_workspace_slice/conversation_slice_lifetime_coordinator.dart';
export 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_notifier.dart';
export 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_entry_resources.dart';

final _containers = Expando<ProviderContainer>();
AgentConversationWorkspaceNotifier createConversationWorkspaceTestOwner({
  required AgentProviderSettingsPort providerController,
  required WorkspaceFileCorpusPort workspaceFileCorpus,
  required AgentProviderRuntimeRegistry runtimeRegistry,
  required AgentConversationBindingManager bindingManager,
  AgentProviderGlobalRuntime? globalRuntime,
  AgentFrameScheduler Function()? uiFrameSchedulerFactory,
  AgentUiTextCatalog? textCatalog,
  AgentTurnContextStore? turnContextStore,
  void Function(AgentTurnTerminalSignal)? onTurnTerminal,
  void Function(AgentWorkspaceAttention)? onAttention,
  ZetaMetricsPort metrics = noopZetaMetricsPort,
}) {
  final container = ProviderContainer(
    overrides: [
      ...conversationWorkspaceOverrides(),
      agentConversationWorkspaceInputsProvider.overrideWithValue(
        AgentConversationWorkspaceDependencies(
          providerController: providerController,
          workspaceFileCorpus: workspaceFileCorpus,
          runtimeRegistry: runtimeRegistry,
          bindingManager: bindingManager,
          globalRuntime:
              globalRuntime ??
              AgentProviderGlobalRuntime(runtimeRegistry: runtimeRegistry),
          uiFrameSchedulerFactory: uiFrameSchedulerFactory,
          textCatalog: textCatalog,
          turnContextStore: turnContextStore,
          onTurnTerminal: onTurnTerminal,
          onAttention: onAttention,
          metrics: metrics,
        ),
      ),
    ],
  );
  final owner = container.read(agentConversationWorkspaceProvider.notifier);
  _containers[owner] = container;
  return owner;
}

ProviderContainer conversationWorkspaceTestContainer(
  AgentConversationWorkspaceNotifier owner,
) => _containers[owner]!;
ConversationSliceLifetimeCoordinator conversationWorkspaceTestLifetimes(
  AgentConversationWorkspaceNotifier owner,
) => _containers[owner]!.read(conversationSliceLifetimesProvider);
void Function() Function(void Function()) conversationWorkspaceTestChanges(
  AgentConversationWorkspaceNotifier owner,
) => _containers[owner]!.read(agentConversationWorkspaceChangesProvider);
AgentConversationEntryCallbacks conversationWorkspaceTestCallbacks(
  AgentConversationWorkspaceNotifier owner,
) {
  final lifetimes = conversationWorkspaceTestLifetimes(owner);
  return AgentConversationEntryCallbacks(
    onCreatedThread:
        ({required session, required context, initialMessage}) async {
          throw UnsupportedError(
            'Created thread callback must be supplied by Shell',
          );
        },
    ensureSlice: lifetimes.ensureSlice,
    onProjectionUnobserved: lifetimes.onProjectionUnobserved,
    onEntryChanged: (_) {},
  );
}

Future<void> closeConversationWorkspaceTestOwner(
  AgentConversationWorkspaceNotifier owner,
) async {
  final container = _containers[owner];
  if (container == null) return;
  await conversationWorkspaceTestLifetimes(owner).closeAllEntries();
  _containers[owner] = null;
  container.dispose();
}
