import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_owner_key.dart';
import 'agent_conversation_workspace_state.dart';

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
/// 一个 entry 对应独立的 Binding 与 conversation runtime；Provider 设置由
/// Workspace 共享，entryId 在草稿晋升为真实 thread 后保持不变。
final class AgentConversationEntryResources {
  AgentConversationEntryResources({
    required this.entryId,
    required this._key,
    required this.projectPath,
    required this.providerController,
    required this.bindingLease,
    required this.controller,
    required this.ownerKey,
    required this.callbacks,
    required this.onChanged,
  }) : _threadSnapshot = controller.threadSnapshot {
    controller.threadSnapshotListenable.addListener(_handleRuntimeChanged);
    _unsubscribeProviderSettings = providerController.subscribe(
      _handleRuntimeChanged,
    );
  }

  final String entryId;
  final AgentProviderSettingsPort providerController;
  late final void Function() _unsubscribeProviderSettings;
  final AgentConversationBindingLease bindingLease;
  final AgentConversationRuntimeController controller;

  final AgentConversationOwnerKey ownerKey;
  final AgentConversationEntryCallbacks callbacks;
  final void Function(AgentConversationEntryResources) onChanged;
  bool closing = false;

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

  AgentConversationWorkspaceEntryState get state =>
      AgentConversationWorkspaceEntryState(
        ownerKey: ownerKey,
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
    final nextSnapshot = controller.threadSnapshot;
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

  void detachSnapshotSubscriptions() {
    if (_disposed) return;
    _disposed = true;
    controller.threadSnapshotListenable.removeListener(_handleRuntimeChanged);
    _unsubscribeProviderSettings();
  }

  void _notify() {
    if (!_disposed && !closing) onChanged(this);
  }
}

/// 一次 opening 的冻结回调。完整 Shell/coordinator 创建后才提供，禁止后补 bind。
final class AgentConversationEntryCallbacks {
  const AgentConversationEntryCallbacks({
    required this.onCreatedThread,
    required this.ensureSlice,
    required this.onProjectionUnobserved,
    required this.onEntryChanged,
  });
  final AgentCreatedThreadCallback onCreatedThread;
  final void Function(AgentConversationOwnerKey) ensureSlice;
  final void Function(AgentConversationOwnerKey) onProjectionUnobserved;
  final void Function(AgentConversationEntryResources) onEntryChanged;
}
