import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/application/agent_conversation_binding.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_binding_manager.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_thread_snapshot.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/application/agent_provider_global_runtime.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_port.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_turn_terminal_signal.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

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
class AgentThreadWorkspaceEntry extends ChangeNotifier {
  AgentThreadWorkspaceEntry({
    required this.entryId,
    required this._key,
    required this.projectPath,
    required this.providerController,
    required this.bindingLease,
    required this.viewModel,
  }) : _threadSnapshot = viewModel.threadSnapshot {
    viewModel.threadSnapshotListenable.addListener(_handleRuntimeChanged);
    providerController.addListener(_handleRuntimeChanged);
  }

  final String entryId;
  final AgentProviderSettingsPort providerController;
  final AgentConversationBindingLease bindingLease;
  final AgentConversationViewModel viewModel;

  AgentConversationBinding get binding => bindingLease.binding;

  String projectPath;
  AgentThreadWorkspaceKey _key;
  AgentConversationThreadSnapshot _threadSnapshot;
  bool _disposed = false;

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

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    viewModel.threadSnapshotListenable.removeListener(_handleRuntimeChanged);
    providerController.removeListener(_handleRuntimeChanged);
    viewModel.dispose();
    unawaited(bindingLease.release());
    super.dispose();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}

/// 管理 Agent Canvas 中多个常驻 thread/draft 运行时。
class AgentThreadWorkspaceController extends ChangeNotifier {
  AgentThreadWorkspaceController({
    required this.providerController,
    required this._workspaceFilesProvider,
    required this.runtimeRegistry,
    AgentConversationBindingManager? bindingManager,
    AgentProviderGlobalRuntime? globalRuntime,
    this._workspaceFilesListenable,
    this._workspaceFilesIndexReady,
    this._onTurnTerminal,
    this._onAttention,
    this.onCreatedThread,
    this.uiFrameSchedulerFactory,
  }) : bindingManager =
           bindingManager ??
           AgentConversationBindingManager(runtimeRegistry: runtimeRegistry),
       globalRuntime =
           globalRuntime ??
           AgentProviderGlobalRuntime(runtimeRegistry: runtimeRegistry),
       _ownsBindingManager = bindingManager == null {
    this.bindingManager.start();
  }

  final List<WorkspaceNode> Function() _workspaceFilesProvider;
  final Listenable? _workspaceFilesListenable;
  final bool Function()? _workspaceFilesIndexReady;
  final AgentProviderRuntimeRegistry runtimeRegistry;
  final AgentProviderSettingsPort providerController;
  final AgentConversationBindingManager bindingManager;
  final AgentProviderGlobalRuntime globalRuntime;
  final bool _ownsBindingManager;
  final ValueChanged<AgentTurnTerminalSignal>? _onTurnTerminal;
  final ValueChanged<AgentWorkspaceAttention>? _onAttention;
  final AgentCreatedThreadCallback? onCreatedThread;

  /// 为每个常驻 ViewModel 创建独立 frame 端口；生产环境为空时使用 Flutter 实现。
  final AgentFrameScheduler Function()? uiFrameSchedulerFactory;

  final List<AgentThreadWorkspaceEntry> _entries =
      <AgentThreadWorkspaceEntry>[];
  int _nextEntryId = 0;
  String? _selectedEntryId;
  bool _disposed = false;

  List<AgentThreadWorkspaceEntry> get entries =>
      UnmodifiableListView<AgentThreadWorkspaceEntry>(_entries);

  String? get selectedEntryId => _selectedEntryId;

  AgentThreadWorkspaceEntry? get selectedEntry {
    final selectedEntryId = _selectedEntryId;
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
    if (_selectedEntryId == entryId) {
      return;
    }
    final exists = _entries.any((entry) => entry.entryId == entryId);
    if (!exists) {
      return;
    }
    _selectedEntryId = entryId;
    _notify();
  }

  /// 清除当前画布选择，但保留所有 workspace 条目及其运行时状态。
  ///
  /// 项目首页使用该状态暂时隐藏 Agent 画布；再次选中原条目时，草稿、滚动位置
  /// 和进行中的会话仍可继续复用。
  void clearSelection() {
    if (_selectedEntryId == null) {
      return;
    }
    _selectedEntryId = null;
    _notify();
  }

  bool removeEntry(String entryId) {
    for (var index = 0; index < _entries.length; index += 1) {
      final entry = _entries[index];
      if (entry.entryId != entryId) {
        continue;
      }
      entry.removeListener(_handleEntryChanged);
      entry.dispose();
      _entries.removeAt(index);
      if (_selectedEntryId == entryId) {
        _selectedEntryId = _entries.isEmpty ? null : _entries.last.entryId;
      }
      _notify();
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

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final entry in _entries.toList(growable: false)) {
      entry.removeListener(_handleEntryChanged);
      entry.dispose();
    }
    _entries.clear();
    if (_ownsBindingManager) {
      unawaited(bindingManager.close());
    }
    super.dispose();
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
      workspaceFilesProvider: _workspaceFilesProvider,
      workspaceFilesListenable: _workspaceFilesListenable,
      workspaceFilesIndexReady: _workspaceFilesIndexReady,
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
    );
    entry.addListener(_handleEntryChanged);
    _entries.add(entry);
    unawaited(viewModel.loadSettings());
    _notify();
    return entry;
  }

  void _handleEntryChanged() {
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}
