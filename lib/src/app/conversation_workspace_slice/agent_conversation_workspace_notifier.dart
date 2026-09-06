import 'dart:async';

import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_intent.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_reducer.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_state.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_composer_state_owner.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'agent_conversation_entry_resources.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_owner_key.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_session_dependencies.dart';
import 'package:zeta/src/features/agent/presentation/agent_ui_update_scheduler.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_corpus_port.dart';

final class AgentConversationWorkspaceDependencies {
  AgentConversationWorkspaceDependencies({
    required this.providerController,
    required this.workspaceFileCorpus,
    required this.runtimeRegistry,
    required this.bindingManager,
    required this.globalRuntime,
    this.onTurnTerminal,
    this.onAttention,
    this.uiFrameSchedulerFactory,
    this.elapsedTickerFactory,
    this.turnContextStore,
    AgentUiTextCatalog? textCatalog,
    this.metrics = noopZetaMetricsPort,
    this.providerMetricLabel = ZetaMetricLabel.hashed,
  }) : _textCatalog = textCatalog ?? const FallbackAgentUiTextCatalog();

  /// @mention 只经 workspace 查询端口取语料，不拼接索引实现或 Flutter listener。
  final WorkspaceFileCorpusPort workspaceFileCorpus;
  final AgentProviderRuntimeRegistry runtimeRegistry;
  final AgentProviderSettingsPort providerController;

  final AgentConversationBindingManager bindingManager;
  final AgentProviderGlobalRuntime globalRuntime;
  final void Function(AgentTurnTerminalSignal)? onTurnTerminal;
  final void Function(AgentWorkspaceAttention)? onAttention;

  /// 为每个常驻 ViewModel 创建独立 frame 端口；生产环境为空时使用 Flutter 实现。
  final AgentFrameScheduler Function()? uiFrameSchedulerFactory;
  final AgentElapsedTicker Function()? elapsedTickerFactory;

  /// Zeta 自有 turn 上下文存储，注入到每个常驻 ViewModel。
  final AgentTurnContextStore? turnContextStore;

  /// 脱敏指标端口，转交给每个常驻 ViewModel 的事件管线与 UI 调度器。
  final ZetaMetricsPort metrics;

  /// Provider 身份到白名单指标标签的组合层投影。
  final ZetaMetricLabel Function(String providerId) providerMetricLabel;

  final AgentUiTextCatalog _textCatalog;
}

final agentConversationWorkspaceDependenciesProvider =
    Provider<AgentConversationWorkspaceDependencies>(
      (ref) => throw StateError(
        'Conversation workspace dependencies are not installed',
      ),
    );

final agentConversationWorkspaceProvider =
    NotifierProvider<
      AgentConversationWorkspaceNotifier,
      AgentConversationWorkspaceState
    >(
      AgentConversationWorkspaceNotifier.new,
      name: 'agentConversationWorkspace',
    );

final class AgentConversationWorkspaceNotifier
    extends Notifier<AgentConversationWorkspaceState> {
  late final AgentConversationWorkspaceDependencies _dependencies;
  final _reducer = const AgentConversationWorkspaceReducer();
  @override
  AgentConversationWorkspaceState build() {
    _dependencies = ref.read(agentConversationWorkspaceDependenciesProvider);
    ref.onDispose(() {
      _disposed = true;
    });
    return AgentConversationWorkspaceState();
  }

  WorkspaceFileCorpusPort get workspaceFileCorpus =>
      _dependencies.workspaceFileCorpus;
  AgentProviderRuntimeRegistry get runtimeRegistry =>
      _dependencies.runtimeRegistry;
  AgentProviderSettingsPort get providerController =>
      _dependencies.providerController;
  AgentConversationBindingManager get bindingManager =>
      _dependencies.bindingManager;
  AgentProviderGlobalRuntime get globalRuntime => _dependencies.globalRuntime;
  AgentFrameScheduler Function()? get uiFrameSchedulerFactory =>
      _dependencies.uiFrameSchedulerFactory;
  AgentTurnContextStore? get turnContextStore => _dependencies.turnContextStore;
  ZetaMetricsPort get metrics => _dependencies.metrics;
  ZetaMetricLabel Function(String) get providerMetricLabel =>
      _dependencies.providerMetricLabel;
  AgentUiTextCatalog get _textCatalog => _dependencies._textCatalog;
  final List<AgentConversationEntryResources> _entries =
      <AgentConversationEntryResources>[];
  final Map<AgentConversationOwnerKey, AgentConversationEntryResources>
  _resources = {};
  int _nextEntryId = 0;
  bool _disposed = false;

  AgentConversationWorkspaceState get current => state;

  List<AgentConversationEntryResources> get entries =>
      List<AgentConversationEntryResources>.unmodifiable(_entries);

  String? get selectedEntryId => state.selectedEntryId;

  bool get projectHomeActive => state.projectHomeActive;

  Map<String, String> get threadIdsByProject => state.threadIdsByProject;

  AgentConversationEntryResources? get selectedEntry {
    final selectedEntryId = state.selectedEntryId;
    if (selectedEntryId == null) {
      return null;
    }
    for (final entry in _entries) {
      if (entry.entryId == selectedEntryId) {
        return entry;
      }
    }
    return null;
  }

  AgentConversationEntryResources entryById(String entryId) {
    for (final entry in _entries) {
      if (entry.entryId == entryId) {
        return entry;
      }
    }
    throw StateError('Unknown conversation workspace entry $entryId');
  }

  AgentConversationEntryResources ensureDraftEntry({
    required String projectPath,
    required AgentConversationEntryCallbacks callbacks,
    required String providerId,
  }) {
    for (final entry in _entries) {
      final key = entry.key;
      if (key is AgentThreadWorkspaceDraftKey &&
          key.projectPath == projectPath &&
          key.providerId == providerId) {
        return entry;
      }
    }
    return _createEntry(
      callbacks: callbacks,
      key: AgentThreadWorkspaceKey.draft(
        projectPath: projectPath,
        providerId: providerId,
      ),
      projectPath: projectPath,
    );
  }

  AgentConversationEntryResources ensureThreadEntry({
    required String projectPath,
    required AgentConversationEntryCallbacks callbacks,
    required AgentThreadSummary thread,
  }) {
    for (final entry in _entries) {
      final key = entry.key;
      if (key is AgentThreadWorkspaceThreadKey &&
          key.providerId == thread.providerId &&
          key.threadId == thread.id) {
        if (entry.projectPath != projectPath) {
          entry.updateProjectPath(projectPath);
        }
        return entry;
      }
    }
    return _createEntry(
      callbacks: callbacks,
      key: AgentThreadWorkspaceKey.thread(
        providerId: thread.providerId,
        threadId: thread.id,
      ),
      projectPath: projectPath,
      initialThread: thread,
    );
  }

  AgentConversationEntryResources? entryForThread({
    required String providerId,
    required String threadId,
  }) {
    for (final entry in _entries) {
      final key = entry.key;
      if (key is AgentThreadWorkspaceThreadKey &&
          key.providerId == providerId &&
          key.threadId == threadId) {
        return entry;
      }
    }
    return null;
  }

  Iterable<AgentConversationEntryResources> entriesForProject(
    String projectPath,
  ) sync* {
    for (final entry in _entries) {
      if (entry.projectPath == projectPath) {
        yield entry;
      }
    }
  }

  void selectEntry(String entryId) {
    if (state.selectedEntryId == entryId && !state.projectHomeActive) {
      return;
    }
    final exists = _entries.any((entry) => entry.entryId == entryId);
    if (!exists) {
      return;
    }
    _dispatch(AgentConversationWorkspaceEntrySelected(entryId));
  }

  /// 进入项目首页并清除画布选择，但保留所有常驻运行时。
  void enterProjectHome() {
    if (state.projectHomeActive && state.selectedEntryId == null) {
      return;
    }
    _dispatch(const AgentConversationWorkspaceHomeEntered());
  }

  void setThreadMapping(String projectPath, String threadId) {
    _dispatch(
      AgentConversationWorkspaceThreadMappingSet(
        projectPath: projectPath,
        threadId: threadId,
      ),
    );
  }

  void removeThreadMapping(String projectPath) {
    _dispatch(AgentConversationWorkspaceThreadMappingRemoved(projectPath));
  }

  void restoreThreadMappings(Map<String, String> mappings) {
    _dispatch(AgentConversationWorkspaceThreadMappingsRestored(mappings));
  }

  AgentConversationEntryResources? resourcesFor(
    AgentConversationOwnerKey key,
  ) => _resources[key];
  int get retainedResourceCount => _resources.length;
  List<AgentConversationOwnerKey> get resourceOwnerKeys =>
      List.unmodifiable(_resources.keys);

  AgentConversationSessionDependencies requireLiveSessionDependencies(
    AgentConversationOwnerKey key,
  ) {
    final entry = _resources[key];
    if (entry == null || entry.closing) {
      throw StateError('Conversation entry is not live');
    }
    return AgentConversationSessionDependencies(
      ownerKey: key,
      regions: entry.controller,
      executor: entry.controller,
      scopeSnapshot: entry.controller.currentCommandScope,
      onProjectionUnobserved: entry.callbacks.onProjectionUnobserved,
    );
  }

  void markClosing(AgentConversationOwnerKey key) {
    final entry = _resources[key];
    if (entry == null || entry.closing) return;
    entry.closing = true;
    state = state.withAliases({
      for (final alias in state.aliases.entries)
        alias.key: _belongsTo(alias.value, key)
            ? AgentConversationOwnerClosing(key)
            : alias.value,
    });
  }

  void removeVisibleEntry(AgentConversationOwnerKey key) {
    final entry = _resources[key];
    if (entry == null) return;
    _entries.remove(entry);
    _dispatch(
      AgentConversationWorkspaceEntryRemoved(
        entryId: entry.entryId,
        fallbackEntryId: _entries.isEmpty ? null : _entries.last.entryId,
      ),
    );
  }

  void finishEntryRelease(AgentConversationOwnerKey key) {
    _resources.remove(key);
    state = state.withAliases({
      for (final alias in state.aliases.entries)
        alias.key: _belongsTo(alias.value, key)
            ? AgentConversationOwnerClosed(key)
            : alias.value,
    });
  }

  void removeReleasedAliases(AgentConversationOwnerKey key) {
    state = state.withAliases({
      for (final alias in state.aliases.entries)
        if (!_belongsTo(alias.value, key)) alias.key: alias.value,
    });
  }

  bool _belongsTo(
    AgentConversationOwnerResolution value,
    AgentConversationOwnerKey key,
  ) => switch (value) {
    AgentConversationOwnerLive(:final ownerKey) ||
    AgentConversationOwnerClosing(:final ownerKey) ||
    AgentConversationOwnerClosed(:final ownerKey) => ownerKey == key,
    AgentConversationOwnerUnknown() => false,
  };

  AgentConversationEntryResources _createEntry({
    required AgentThreadWorkspaceKey key,
    required AgentConversationEntryCallbacks callbacks,
    required String projectPath,
    AgentThreadSummary? initialThread,
  }) {
    // entryId 先生成，用作尚未取得 threadId 的稳定 Binding 身份；创建 entry 本身
    // 不会创建 session Provider。
    if (_disposed) throw StateError('Conversation workspace is closed');
    final entryId = 'agent-workspace-entry-${_nextEntryId += 1}';
    final ownerKey = AgentConversationOwnerKey(entryId);
    final bindingLease = switch (key) {
      AgentThreadWorkspaceThreadKey(:final providerId, :final threadId) =>
        bindingManager.acquireThread(
          providerId: providerId,
          threadId: threadId,
          resolveConfig: (id) =>
              providerController.providerConfigById(id) ??
              providerController.activeProviderConfig,
          persistPermissionOptionId: (optionId) => providerController
              .persistPermissionOptionIdForProvider(providerId, optionId),
        ),
      AgentThreadWorkspaceDraftKey(:final providerId) =>
        bindingManager.acquireDraft(
          providerId: providerId,
          entryId: entryId,
          resolveConfig: (id) =>
              providerController.providerConfigById(id) ??
              providerController.activeProviderConfig,
          persistPermissionOptionId: (optionId) => providerController
              .persistPermissionOptionIdForProvider(providerId, optionId),
        ),
    };
    late final AgentConversationEntryResources entry;
    late final AgentConversationRuntimeController controller;
    controller = AgentConversationRuntimeController(
      providerController: providerController,
      conversationBinding: bindingLease.binding,
      globalRuntime: globalRuntime,
      composerStateOwner: AgentConversationComposerStateOwner.create(
        providerController: providerController,
        textCatalog: _textCatalog,
      ),
      textCatalog: _textCatalog,
      workspaceFileCorpus: workspaceFileCorpus,
      onTurnTerminal: _dependencies.onTurnTerminal,
      onProviderSwitchRequested: (providerId) async {
        final draft = ensureDraftEntry(
          callbacks: callbacks,
          projectPath: entry.projectPath,
          providerId: providerId,
        );
        selectEntry(draft.entryId);
      },
      onCreatedThread: callbacks.onCreatedThread,
      initialProjectPath: projectPath,
      initialThread: initialThread,
      turnContextStore: turnContextStore,
      metrics: metrics,
      providerMetricLabel: providerMetricLabel,
      onAttention: (signal) {
        final threadId = signal.threadId ?? entry.threadId;
        if (threadId == null || threadId.trim().isEmpty) {
          return;
        }
        _dependencies.onAttention?.call(
          AgentWorkspaceAttention(
            signal: signal.withThreadId(threadId),
            providerId: entry.providerId,
            threadId: threadId,
            projectPath: entry.projectPath,
          ),
        );
      },
      elapsedTicker: _dependencies.elapsedTickerFactory?.call(),
      uiFrameScheduler:
          uiFrameSchedulerFactory?.call() ??
          const SchedulerBindingAgentFrameScheduler(),
    );
    entry = AgentConversationEntryResources(
      entryId: entryId,
      key: key,
      projectPath: projectPath,
      providerController: providerController,
      bindingLease: bindingLease,
      controller: controller,
      ownerKey: ownerKey,
      callbacks: callbacks,
      onChanged: _handleEntryChanged,
    );
    _resources[ownerKey] = entry;
    callbacks.ensureSlice(ownerKey);
    _entries.add(entry);
    _dispatch(AgentConversationWorkspaceEntryRegistered(entry.state));
    unawaited(controller.loadSettings());
    return entry;
  }

  void _handleEntryChanged(AgentConversationEntryResources entry) {
    _dispatch(AgentConversationWorkspaceEntryUpdated(entry.state));
    entry.callbacks.onEntryChanged(entry);
  }

  void _dispatch(AgentConversationWorkspaceIntent intent) {
    if (_disposed) {
      return;
    }
    final aliases =
        Map<AgentConversationBindingKey, AgentConversationOwnerResolution>.of(
          state.aliases,
        );
    for (final entry in _entries) {
      if (entry.closing) continue;
      final previous = aliases[entry.binding.key];
      if (previous is AgentConversationOwnerLive &&
          previous.ownerKey != entry.ownerKey) {
        throw StateError('Conversation alias collision');
      }
      if (previous is! AgentConversationOwnerLive ||
          previous.ownerKey != entry.ownerKey) {
        aliases[entry.binding.key] = AgentConversationOwnerLive(entry.ownerKey);
      }
    }
    final next = _reducer.reduce(state, intent).withAliases(aliases);
    if (next != state) state = next;
  }
}
