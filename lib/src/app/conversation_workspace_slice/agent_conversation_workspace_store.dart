import 'dart:async';

import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_intent.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_reducer.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_state.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_composer_state_owner.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/app/conversation_slice/agent_conversation_slice_composition.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_corpus_port.dart';

/// Agent Canvas 中单个常驻线程/草稿的逻辑标识。
sealed class AgentThreadWorkspaceKey {
  const AgentThreadWorkspaceKey();

  const factory AgentThreadWorkspaceKey.thread({
    required String providerId,
    required String threadId,
  }) = AgentThreadWorkspaceThreadKey;

  const factory AgentThreadWorkspaceKey.draft({
    required String projectPath,
    required String providerId,
  }) = AgentThreadWorkspaceDraftKey;
}

/// 已绑定真实 thread 的 key。
final class AgentThreadWorkspaceThreadKey extends AgentThreadWorkspaceKey {
  const AgentThreadWorkspaceThreadKey({
    required this.providerId,
    required this.threadId,
  });

  final String providerId;
  final String threadId;

  @override
  bool operator ==(Object other) {
    return other is AgentThreadWorkspaceThreadKey &&
        other.providerId == providerId &&
        other.threadId == threadId;
  }

  @override
  int get hashCode => Object.hash(providerId, threadId);
}

/// 尚未启动真实 thread 的草稿 key。
final class AgentThreadWorkspaceDraftKey extends AgentThreadWorkspaceKey {
  const AgentThreadWorkspaceDraftKey({
    required this.projectPath,
    required this.providerId,
  });

  final String projectPath;
  final String providerId;

  @override
  bool operator ==(Object other) {
    return other is AgentThreadWorkspaceDraftKey &&
        other.projectPath == projectPath &&
        other.providerId == providerId;
  }

  @override
  int get hashCode => Object.hash(projectPath, providerId);
}

/// Agent Canvas 中单个常驻 Pane 的运行时条目。
///
/// 一个 entry 对应独立的 Binding 与 conversation view model；Provider 设置由
/// Workspace 共享，entryId 在草稿晋升为真实 thread 后保持不变。
final class AgentThreadWorkspaceEntry {
  AgentThreadWorkspaceEntry({
    required this.entryId,
    required this._key,
    required this.projectPath,
    required this.providerController,
    required this.bindingLease,
    required this.viewModel,
    required this.sliceBinding,
  }) : _threadSnapshot = viewModel.threadSnapshot {
    viewModel.threadSnapshotListenable.addListener(_handleRuntimeChanged);
    _unsubscribeProviderSettings = providerController.subscribe(
      _handleRuntimeChanged,
    );
  }

  final String entryId;
  final AgentProviderSettingsPort providerController;
  late final void Function() _unsubscribeProviderSettings;
  final AgentConversationBindingLease bindingLease;
  final AgentConversationViewModel viewModel;

  /// Conversation Slice 是每个 entry 的必选接线，不存在旧 ViewModel 回退路径。
  final AgentConversationSliceComposition sliceBinding;

  AgentConversationSliceStore get sliceStore => sliceBinding.store;

  AgentConversationBinding get binding => bindingLease.binding;

  String projectPath;
  AgentThreadWorkspaceKey _key;
  AgentConversationThreadSnapshot _threadSnapshot;
  bool _disposed = false;
  final List<void Function()> _listeners = <void Function()>[];

  void addListener(void Function() listener) {
    if (!_disposed && !_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  AgentThreadWorkspaceKey get key => _key;

  AgentConversationThreadSnapshot get threadSnapshot => _threadSnapshot;

  String get providerId => switch (_key) {
    AgentThreadWorkspaceThreadKey(:final providerId) => providerId,
    AgentThreadWorkspaceDraftKey(:final providerId) => providerId,
  };

  String? get threadId => switch (_key) {
    AgentThreadWorkspaceThreadKey(:final threadId) => threadId,
    AgentThreadWorkspaceDraftKey() => null,
  };

  bool get isDraft => _key is AgentThreadWorkspaceDraftKey;

  AgentConversationWorkspaceEntryState get state =>
      AgentConversationWorkspaceEntryState(
        entryId: entryId,
        projectPath: projectPath,
        providerId: providerId,
        threadId: threadId,
        bindingKey: binding.key,
        threadSnapshot: threadSnapshot,
      );

  /// 将 entry 绑定到新的项目草稿身份。
  void applyDraftIdentity({
    required String projectPath,
    required String providerId,
  }) {
    var changed = false;
    if (this.projectPath != projectPath) {
      this.projectPath = projectPath;
      changed = true;
    }
    final nextKey = AgentThreadWorkspaceKey.draft(
      projectPath: projectPath,
      providerId: providerId,
    );
    if (_key != nextKey) {
      _key = nextKey;
      changed = true;
    }
    if (changed) {
      _notify();
    }
  }

  /// 更新同一 thread 的项目归属展示，不改变已经冻结的 Provider/thread key。
  void updateProjectPath(String projectPath) {
    if (this.projectPath != projectPath) {
      this.projectPath = projectPath;
      _notify();
    }
  }

  void _handleRuntimeChanged() {
    var changed = false;
    final nextSnapshot = viewModel.threadSnapshot;
    if (nextSnapshot != _threadSnapshot) {
      _threadSnapshot = nextSnapshot;
      changed = true;
    }
    final sessionId = nextSnapshot.sessionId;
    if (sessionId != null) {
      final nextKey = AgentThreadWorkspaceKey.thread(
        providerId: nextSnapshot.providerId,
        threadId: sessionId,
      );
      if (_key != nextKey) {
        _key = nextKey;
        changed = true;
      }
    }
    if (changed) {
      _notify();
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    viewModel.threadSnapshotListenable.removeListener(_handleRuntimeChanged);
    _unsubscribeProviderSettings();
    // 切片先于 ViewModel 释放：它订阅了 ViewModel 的 region listenable。
    sliceBinding.dispose();
    viewModel.dispose();
    unawaited(bindingLease.release());
    _listeners.clear();
  }

  void _notify() {
    if (!_disposed) {
      for (final listener in List<void Function()>.of(_listeners)) {
        listener();
      }
    }
  }
}

/// Conversation Workspace 的唯一运行时与状态 owner。
///
/// reducer 只处理不可变状态；Binding、ViewModel 与 SliceBinding 的创建/释放留在
/// 本 app 组合层 store。Shell 只订阅这个 owner，不再逐 entry 维护镜像监听表。
final class AgentConversationWorkspaceStore {
  AgentConversationWorkspaceStore({
    required this.providerController,
    required this.workspaceFileCorpus,
    required this.runtimeRegistry,
    AgentConversationBindingManager? bindingManager,
    AgentProviderGlobalRuntime? globalRuntime,
    this._onTurnTerminal,
    this._onAttention,
    this.onCreatedThread,
    this.uiFrameSchedulerFactory,
    this.turnContextStore,
    AgentUiTextCatalog? textCatalog,
    this.metrics = noopZetaMetricsPort,
    this.providerMetricLabel = ZetaMetricLabel.hashed,
    this._reducer = const AgentConversationWorkspaceReducer(),
  }) : bindingManager =
           bindingManager ??
           AgentConversationBindingManager(
             runtimeRegistry: runtimeRegistry,
             textCatalog: textCatalog ?? const FallbackAgentUiTextCatalog(),
           ),
       globalRuntime =
           globalRuntime ??
           AgentProviderGlobalRuntime(runtimeRegistry: runtimeRegistry),
       _ownsBindingManager = bindingManager == null,
       _textCatalog = textCatalog ?? const FallbackAgentUiTextCatalog() {
    this.bindingManager.start();
  }

  /// @mention 只经 workspace 查询端口取语料，不拼接索引实现或 Flutter listener。
  final WorkspaceFileCorpusPort workspaceFileCorpus;
  final AgentProviderRuntimeRegistry runtimeRegistry;
  final AgentProviderSettingsPort providerController;

  final AgentConversationBindingManager bindingManager;
  final AgentProviderGlobalRuntime globalRuntime;
  final bool _ownsBindingManager;
  final void Function(AgentTurnTerminalSignal)? _onTurnTerminal;
  final void Function(AgentWorkspaceAttention)? _onAttention;
  final AgentCreatedThreadCallback? onCreatedThread;

  /// 为每个常驻 ViewModel 创建独立 frame 端口；生产环境为空时使用 Flutter 实现。
  final AgentFrameScheduler Function()? uiFrameSchedulerFactory;

  /// Zeta 自有 turn 上下文存储，注入到每个常驻 ViewModel。
  final AgentTurnContextStore? turnContextStore;

  /// 脱敏指标端口，转交给每个常驻 ViewModel 的事件管线与 UI 调度器。
  final ZetaMetricsPort metrics;

  /// Provider 身份到白名单指标标签的组合层投影。
  final ZetaMetricLabel Function(String providerId) providerMetricLabel;

  final AgentUiTextCatalog _textCatalog;
  final AgentConversationWorkspaceReducer _reducer;

  final List<AgentThreadWorkspaceEntry> _entries =
      <AgentThreadWorkspaceEntry>[];
  final Map<String, void Function()> _entryListeners =
      <String, void Function()>{};
  final List<void Function()> _listeners = <void Function()>[];
  final List<void Function(AgentThreadWorkspaceEntry)> _entryChangedListeners =
      <void Function(AgentThreadWorkspaceEntry)>[];
  AgentConversationWorkspaceState _state = AgentConversationWorkspaceState();
  int _nextEntryId = 0;
  bool _disposed = false;

  AgentConversationWorkspaceState get state => _state;

  List<AgentThreadWorkspaceEntry> get entries =>
      List<AgentThreadWorkspaceEntry>.unmodifiable(_entries);

  String? get selectedEntryId => _state.selectedEntryId;

  bool get projectHomeActive => _state.projectHomeActive;

  Map<String, String> get threadIdsByProject => _state.threadIdsByProject;

  void addListener(void Function() listener) {
    if (!_disposed && !_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void addEntryChangedListener(
    void Function(AgentThreadWorkspaceEntry) listener,
  ) {
    if (!_disposed && !_entryChangedListeners.contains(listener)) {
      _entryChangedListeners.add(listener);
    }
  }

  void removeEntryChangedListener(
    void Function(AgentThreadWorkspaceEntry) listener,
  ) => _entryChangedListeners.remove(listener);

  AgentThreadWorkspaceEntry? get selectedEntry {
    final selectedEntryId = _state.selectedEntryId;
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

  AgentThreadWorkspaceEntry entryById(String entryId) {
    for (final entry in _entries) {
      if (entry.entryId == entryId) {
        return entry;
      }
    }
    throw StateError('Unknown conversation workspace entry $entryId');
  }

  AgentThreadWorkspaceEntry ensureDraftEntry({
    required String projectPath,
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
      key: AgentThreadWorkspaceKey.draft(
        projectPath: projectPath,
        providerId: providerId,
      ),
      projectPath: projectPath,
    );
  }

  AgentThreadWorkspaceEntry ensureThreadEntry({
    required String projectPath,
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
      key: AgentThreadWorkspaceKey.thread(
        providerId: thread.providerId,
        threadId: thread.id,
      ),
      projectPath: projectPath,
      initialThread: thread,
    );
  }

  AgentThreadWorkspaceEntry? entryForThread({
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

  Iterable<AgentThreadWorkspaceEntry> entriesForProject(
    String projectPath,
  ) sync* {
    for (final entry in _entries) {
      if (entry.projectPath == projectPath) {
        yield entry;
      }
    }
  }

  void selectEntry(String entryId) {
    if (_state.selectedEntryId == entryId && !_state.projectHomeActive) {
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
    if (_state.projectHomeActive && _state.selectedEntryId == null) {
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

  bool removeEntry(String entryId) {
    for (var index = 0; index < _entries.length; index += 1) {
      final entry = _entries[index];
      if (entry.entryId != entryId) {
        continue;
      }
      final listener = _entryListeners.remove(entry.entryId);
      if (listener != null) {
        entry.removeListener(listener);
      }
      entry.dispose();
      _entries.removeAt(index);
      _dispatch(
        AgentConversationWorkspaceEntryRemoved(
          entryId: entryId,
          fallbackEntryId: _entries.isEmpty ? null : _entries.last.entryId,
        ),
      );
      return true;
    }
    return false;
  }

  void removeEntriesForProject(String projectPath) {
    final removedIds = <String>[
      for (final entry in _entries)
        if (entry.projectPath == projectPath) entry.entryId,
    ];
    if (removedIds.isEmpty) {
      return;
    }
    for (final entryId in removedIds) {
      removeEntry(entryId);
    }
  }

  bool removeThreadEntry({
    required String providerId,
    required String threadId,
  }) {
    final entry = entryForThread(providerId: providerId, threadId: threadId);
    if (entry == null) {
      return false;
    }
    return removeEntry(entry.entryId);
  }

  /// 按 Binding 身份解析该会话唯一的切片 store；未知身份 fail-closed。
  AgentConversationSliceStore sliceStoreForBinding(
    AgentConversationBindingKey key,
  ) {
    for (final entry in _entries) {
      if (entry.binding.key == key) {
        return entry.sliceStore;
      }
    }
    throw StateError('No conversation workspace entry registered for $key');
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final entry in _entries.toList(growable: false)) {
      final listener = _entryListeners.remove(entry.entryId);
      if (listener != null) {
        entry.removeListener(listener);
      }
      entry.dispose();
    }
    _entries.clear();
    if (_ownsBindingManager) {
      unawaited(bindingManager.close());
    }
    _listeners.clear();
    _entryChangedListeners.clear();
  }

  AgentThreadWorkspaceEntry _createEntry({
    required AgentThreadWorkspaceKey key,
    required String projectPath,
    AgentThreadSummary? initialThread,
  }) {
    // entryId 先生成，用作尚未取得 threadId 的稳定 Binding 身份；创建 entry 本身
    // 不会创建 session Provider。
    final entryId = 'agent-workspace-entry-${_nextEntryId += 1}';
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
    late final AgentThreadWorkspaceEntry entry;
    late final AgentConversationViewModel viewModel;
    viewModel = AgentConversationViewModel(
      providerController: providerController,
      conversationBinding: bindingLease.binding,
      globalRuntime: globalRuntime,
      composerStateOwner: AgentConversationComposerStateOwner.create(
        providerController: providerController,
        textCatalog: _textCatalog,
      ),
      textCatalog: _textCatalog,
      workspaceFileCorpus: workspaceFileCorpus,
      onTurnTerminal: _onTurnTerminal,
      onProviderSwitchRequested: (providerId) async {
        final draft = ensureDraftEntry(
          projectPath: entry.projectPath,
          providerId: providerId,
        );
        selectEntry(draft.entryId);
      },
      onCreatedThread: onCreatedThread,
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
        _onAttention?.call(
          AgentWorkspaceAttention(
            signal: signal.withThreadId(threadId),
            providerId: entry.providerId,
            threadId: threadId,
            projectPath: entry.projectPath,
          ),
        );
      },
      uiFrameScheduler: uiFrameSchedulerFactory?.call(),
    );
    entry = AgentThreadWorkspaceEntry(
      entryId: entryId,
      key: key,
      projectPath: projectPath,
      providerController: providerController,
      bindingLease: bindingLease,
      viewModel: viewModel,
      sliceBinding: AgentConversationSliceComposition(
        regions: viewModel,
        commands: viewModel,
      ),
    );
    void listener() => _handleEntryChanged(entry);
    entry.addListener(listener);
    _entryListeners[entry.entryId] = listener;
    _entries.add(entry);
    _dispatch(AgentConversationWorkspaceEntryRegistered(entry.state));
    unawaited(viewModel.loadSettings());
    return entry;
  }

  void _handleEntryChanged(AgentThreadWorkspaceEntry entry) {
    _dispatch(AgentConversationWorkspaceEntryUpdated(entry.state));
    for (final listener in List<void Function(AgentThreadWorkspaceEntry)>.of(
      _entryChangedListeners,
    )) {
      listener(entry);
    }
  }

  void _dispatch(AgentConversationWorkspaceIntent intent) {
    if (_disposed) {
      return;
    }
    final next = _reducer.reduce(_state, intent);
    if (next == _state) {
      return;
    }
    _state = next;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }
}
