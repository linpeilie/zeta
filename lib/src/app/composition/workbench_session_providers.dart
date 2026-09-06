import 'package:zeta/src/features/agent/presentation/agent_pane_retention.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_entry_resources.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/app/agent_management_slice/workspace_agent_runtime_fact_source.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_notifier.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_providers.dart';
import 'package:zeta/src/app/conversation_workspace_slice/conversation_slice_lifetime_coordinator.dart';
import 'package:zeta/src/app/localization/zeta_text_catalog_providers.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import 'package:zeta/src/app/project_threads_slice/project_threads_slice_composition.dart';
import 'package:zeta/src/app/shell/ide_shell_controller.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_owner_key.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_session_dependencies.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_notifier.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_store.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_notifier.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_notifier.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_corpus.dart';
import 'package:zeta/src/features/workspace/application/workspace_notifier.dart';
import 'agent_session_resource_providers.dart';
import 'app_dependencies.dart';
import 'zeta_environment_providers.dart';

/// UI 事件没有可重放业务状态；页面只借用订阅，应用关闭事件源。
final class WorkbenchUiEvents {
  final _status = StreamController<String>.broadcast(sync: true);
  final _terminals = StreamController<AgentTurnTerminalSignal>.broadcast(
    sync: true,
  );
  Stream<String> get status => _status.stream;
  Stream<AgentTurnTerminalSignal> get terminals => _terminals.stream;
  void reportStatus(String value) {
    if (!_status.isClosed) _status.add(value);
  }

  void turnTerminal(AgentTurnTerminalSignal value) {
    if (!_terminals.isClosed) _terminals.add(value);
  }

  Future<void> close() async {
    await Future.wait([_status.close(), _terminals.close()]);
  }
}

final workbenchUiEventsProvider = Provider((ref) => WorkbenchUiEvents());

final agentElapsedTickerFactoryProvider =
    Provider<AgentElapsedTicker Function()>((ref) => AgentElapsedTicker.new);

/// 外部端口替换点；内部 owner 依赖仅安装一次。
final agentConversationWorkspaceInputsProvider =
    Provider<AgentConversationWorkspaceDependencies>((ref) {
      final events = ref.read(workbenchUiEventsProvider);
      final attention = ref.read(desktopAttentionSliceProvider.notifier);
      return AgentConversationWorkspaceDependencies(
        providerController: ref.read(
          agentProviderSettingsSliceProvider.notifier,
        ),
        workspaceFileCorpus: ref.read(workspaceFileCorpusProvider),
        runtimeRegistry: ref.read(agentProviderRuntimeRegistryProvider),
        bindingManager: ref.read(agentConversationBindingManagerProvider),
        globalRuntime: ref.read(agentProviderGlobalRuntimeProvider),
        textCatalog: ref.read(agentUiTextCatalogProvider),
        turnContextStore: ref.read(agentTurnContextStoreProvider),
        metrics: ref.read(zetaMetricsPortProvider),
        providerMetricLabel: zetaAgentProviderDefinitionCatalog.metricLabelFor,
        elapsedTickerFactory: ref.read(agentElapsedTickerFactoryProvider),
        onTurnTerminal: events.turnTerminal,
        onAttention: (value) => unawaited(attention.handleAttention(value)),
      );
    });

List<Override> conversationWorkspaceOverrides() => [
  agentConversationWorkspaceDependenciesProvider.overrideWith(
    (ref) => ref.read(agentConversationWorkspaceInputsProvider),
  ),
  agentConversationSessionDependenciesProvider.overrideWith(
    (ref, key) => ref
        .read(agentConversationWorkspaceProvider.notifier)
        .requireLiveSessionDependencies(key),
  ),
  agentConversationOwnerResolutionProvider.overrideWith(
    (ref, key) =>
        ref.watch(
          agentConversationWorkspaceProvider.select((s) => s.aliases[key]),
        ) ??
        const AgentConversationOwnerUnknown(),
  ),
];

final conversationEntryLeaseReleaseProvider =
    Provider<Future<void> Function(AgentConversationEntryResources)>((ref) {
      final retention = ref.read(agentPaneRetentionProvider);
      return (entry) async {
        await entry.bindingLease.release();
        await retention.closeEntry(entry.controller);
      };
    });

final conversationSliceLifetimesProvider =
    Provider<ConversationSliceLifetimeCoordinator>(
      (ref) => ConversationSliceLifetimeCoordinator(
        releaseEntryLease: ref.read(conversationEntryLeaseReleaseProvider),
        workspace: ref.read(agentConversationWorkspaceProvider.notifier),
        retainOwner: (key) => ref.container.listen(
          agentConversationSliceOwnerProvider(key),
          (_, _) {},
        ),
        readOwner: (key) =>
            ref.read(agentConversationSliceOwnerProvider(key).notifier),
        invalidateOwner: (key) =>
            ref.invalidate(agentConversationSliceOwnerProvider(key)),
      ),
    );

/// 事实源只依赖 Workspace/BindingManager，不依赖 workbench 或管理 owner。
final workspaceAgentRuntimeFactSourceProvider =
    Provider<WorkspaceAgentRuntimeFactSource>(
      (ref) => WorkspaceAgentRuntimeFactSource(
        ref.read(agentConversationWorkspaceProvider.notifier),
        subscribeWorkspace: ref.read(agentConversationWorkspaceChangesProvider),
      ),
    );

final class WorkbenchSession {
  WorkbenchSession({
    required this.shell,
    required this.lifetimes,
    required this.events,
  });
  final IdeShellController shell;
  final ConversationSliceLifetimeCoordinator lifetimes;
  final WorkbenchUiEvents events;
}

/// 构造没有启动副作用；组合根在此 provider 完成后调用 Shell.start。
final workbenchSessionProvider = Provider<WorkbenchSession>((ref) {
  final settings = ref.read(agentProviderSettingsSliceProvider.notifier);
  final events = ref.read(workbenchUiEventsProvider);
  final lifetimes = ref.read(conversationSliceLifetimesProvider);
  final shell = IdeShellController(
    workspace: ref.read(workspaceProvider.notifier),
    workspaceFileCorpus: ref.read(workspaceFileCorpusProvider),
    workspaceFileIndexController: ref.read(
      workspaceFileIndexControllerProvider,
    ),
    ideSessionOperations: ref.read(ideSessionSliceProvider.notifier),
    projectThreadsController: ref.read(projectThreadsOperationsProvider),
    subscribeProjectThreads: ref.read(projectThreadsChangesProvider),
    agentConversationWorkspace: ref.read(
      agentConversationWorkspaceProvider.notifier,
    ),
    subscribeConversationWorkspace: ref.read(
      agentConversationWorkspaceChangesProvider,
    ),
    lifetimes: lifetimes,
    agentProviderGlobalRuntime: ref.read(agentProviderGlobalRuntimeProvider),
    agentProviderSettingsPort: settings,
    activeModelCatalogLoader: settings.loadActiveModelCatalog,
    projectLocationOpener: ref.read(projectLocationOpenerProvider),
    statusReporter: events.reportStatus,
    agentProviderRuntimeRegistry: ref.read(
      agentProviderRuntimeRegistryProvider,
    ),
    agentUiTextCatalog: ref.read(agentUiTextCatalogProvider),
    metrics: ref.read(zetaMetricsPortProvider),
    providerMetricLabel: zetaAgentProviderDefinitionCatalog.metricLabelFor,
  );
  return WorkbenchSession(shell: shell, lifetimes: lifetimes, events: events);
}, dependencies: [ideSessionSliceProvider]);
