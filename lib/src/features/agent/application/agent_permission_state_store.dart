import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/application/agent_permission_request_resolver.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_identity.dart';
import 'package:zeta/src/features/agent/domain/agent_permission_policy_models.dart';

export 'package:zeta/src/features/agent/application/agent_provider_runtime_identity.dart';

/// application 权限状态的事实来源。
enum AgentPermissionStateSource {
  providerDefault,
  userSelection,
  serverSettings,
  runtimeBroadcast,
}

/// 单个 thread 的不可变权限状态。
final class AgentThreadPermissionState {
  const AgentThreadPermissionState({
    required this.threadId,
    required this.selection,
    required this.source,
    this.lastApplyScope,
    this.warning,
  });

  final String threadId;
  final AgentPermissionSelection selection;
  final AgentPermissionStateSource source;
  final AgentPermissionApplyScope? lastApplyScope;
  final String? warning;
}

/// Provider apply 已成功、但默认偏好持久化失败的可重试状态。
final class AgentPermissionPersistenceFailure {
  const AgentPermissionPersistenceFailure({
    required this.selection,
    required this.message,
  });

  final AgentPermissionSelection selection;
  final String message;
}

/// 单个 runtime generation 下的不可变权限快照。
final class AgentPermissionState {
  AgentPermissionState({
    required this.runtimeIdentity,
    this.providerDefaultPreference,
    this.runtimeSelection,
    Map<String, AgentThreadPermissionState> threadStates =
        const <String, AgentThreadPermissionState>{},
    Map<String, AgentThreadPermissionState> pendingTurnStates =
        const <String, AgentThreadPermissionState>{},
    this.source,
    this.lastApplyScope,
    this.warning,
    this.persistenceFailure,
    this.revision = 0,
  }) : threadStates = Map<String, AgentThreadPermissionState>.unmodifiable(
         threadStates,
       ),
       pendingTurnStates = Map<String, AgentThreadPermissionState>.unmodifiable(
         pendingTurnStates,
       );

  final AgentProviderRuntimeIdentity runtimeIdentity;
  final AgentPermissionSelection? providerDefaultPreference;

  /// runtime-global Provider（当前为 Grok）的显式共享状态。
  final AgentPermissionSelection? runtimeSelection;
  final Map<String, AgentThreadPermissionState> threadStates;

  /// `currentTurn` 只供下一次请求取走，不进入 thread effective。
  final Map<String, AgentThreadPermissionState> pendingTurnStates;
  final AgentPermissionStateSource? source;
  final AgentPermissionApplyScope? lastApplyScope;
  final String? warning;
  final AgentPermissionPersistenceFailure? persistenceFailure;
  final int revision;

  AgentThreadPermissionState? effectiveStateForThread(String? threadId) {
    final normalized = _normalizeThreadId(threadId);
    if (normalized != null) {
      final pendingTurn = pendingTurnStates[normalized];
      if (pendingTurn != null) {
        return pendingTurn;
      }
    }
    final runtime = runtimeSelection;
    if (runtime != null) {
      return AgentThreadPermissionState(
        threadId: normalized ?? '',
        selection: runtime,
        source: AgentPermissionStateSource.runtimeBroadcast,
        lastApplyScope: AgentPermissionApplyScope.runtime,
        warning: warning,
      );
    }
    if (normalized != null) {
      final thread = threadStates[normalized];
      if (thread != null) {
        return thread;
      }
    }
    final providerDefault = providerDefaultPreference;
    if (providerDefault == null) {
      return null;
    }
    return AgentThreadPermissionState(
      threadId: normalized ?? '',
      selection: providerDefault,
      source: AgentPermissionStateSource.providerDefault,
      lastApplyScope: lastApplyScope,
      warning: warning,
    );
  }
}

/// `runtime` scope 的显式广播载荷。
final class AgentPermissionRuntimeState {
  const AgentPermissionRuntimeState({
    required this.runtimeIdentity,
    required this.selection,
    required this.lastApplyScope,
    required this.revision,
    this.warning,
  });

  final AgentProviderRuntimeIdentity runtimeIdentity;
  final AgentPermissionSelection selection;
  final AgentPermissionApplyScope lastApplyScope;
  final String? warning;
  final int revision;
}

/// application 级权限状态真源。
///
/// 状态以 provider runtime identity/generation 隔离；thread 状态再以 threadId
/// 隔离。所有集合均以不可修改快照暴露。
final class AgentPermissionStateStore extends ChangeNotifier {
  final Map<AgentProviderRuntimeIdentity, AgentPermissionState> _states =
      <AgentProviderRuntimeIdentity, AgentPermissionState>{};
  final Map<String, AgentProviderRuntimeIdentity> _activeByProvider =
      <String, AgentProviderRuntimeIdentity>{};
  final StreamController<AgentPermissionRuntimeState> _runtimeStates =
      StreamController<AgentPermissionRuntimeState>.broadcast(sync: true);
  bool _disposed = false;

  Stream<AgentPermissionRuntimeState> get runtimeStates =>
      _runtimeStates.stream;

  Map<AgentProviderRuntimeIdentity, AgentPermissionState> get states =>
      Map<AgentProviderRuntimeIdentity, AgentPermissionState>.unmodifiable(
        _states,
      );

  AgentPermissionState stateFor(AgentProviderRuntimeIdentity identity) {
    return _states[identity] ?? AgentPermissionState(runtimeIdentity: identity);
  }

  bool isCurrent(AgentProviderRuntimeIdentity identity) {
    return !_disposed && _activeByProvider[identity.providerId] == identity;
  }

  /// 激活一个 runtime generation；较旧 generation 的迟到绑定会被忽略。
  void activateRuntime(
    AgentProviderRuntimeIdentity identity, {
    AgentPermissionSelection? initialProviderDefault,
  }) {
    if (_disposed) {
      return;
    }
    final current = _activeByProvider[identity.providerId];
    if (current != null &&
        current != identity &&
        current.generation > identity.generation) {
      return;
    }
    final changedIdentity = current != identity;
    _activeByProvider[identity.providerId] = identity;
    final existing = _states[identity];
    if (existing == null) {
      _states[identity] = AgentPermissionState(
        runtimeIdentity: identity,
        providerDefaultPreference: initialProviderDefault,
        source: initialProviderDefault == null
            ? null
            : AgentPermissionStateSource.providerDefault,
      );
      _notify();
      return;
    }
    if (existing.providerDefaultPreference == null &&
        initialProviderDefault != null) {
      _states[identity] = _replace(
        existing,
        providerDefaultPreference: initialProviderDefault,
        source: AgentPermissionStateSource.providerDefault,
      );
      _notify();
      return;
    }
    if (changedIdentity) {
      _notify();
    }
  }

  /// 使旧 runtime 立即失效；后续迟到 apply/broadcast 无法提交。
  void retireRuntime(AgentProviderRuntimeIdentity identity) {
    if (!isCurrent(identity)) {
      return;
    }
    _activeByProvider.remove(identity.providerId);
    _states.remove(identity);
    _notify();
  }

  /// 清理从未建立 runtime lease 的 Canvas 临时状态。
  void discardProvisionalRuntime(AgentProviderRuntimeIdentity identity) {
    _discardProvisional(identity);
  }

  /// 仅在当前 runtime 尚无内存默认时，从配置播种 provider preference。
  void seedProviderDefault(
    AgentProviderRuntimeIdentity identity,
    AgentPermissionSelection? selection,
  ) {
    if (!isCurrent(identity)) {
      return;
    }
    final current = stateFor(identity);
    if (current.providerDefaultPreference != null || selection == null) {
      return;
    }
    _states[identity] = _replace(
      current,
      providerDefaultPreference: selection,
      source: AgentPermissionStateSource.providerDefault,
    );
    _notify();
  }

  /// 将 runtime lease 建立前暂存的 thread settings 迁入真实 generation。
  ///
  /// 仅接受显式 provisional 身份，禁止在两个真实 runtime 之间搬运状态。
  void adoptProvisionalThreadState({
    required AgentProviderRuntimeIdentity provisionalIdentity,
    required AgentProviderRuntimeIdentity runtimeIdentity,
  }) {
    if (!provisionalIdentity.isProvisional ||
        provisionalIdentity == runtimeIdentity ||
        !isCurrent(runtimeIdentity)) {
      return;
    }
    final provisional = _states[provisionalIdentity];
    if (provisional == null) {
      return;
    }
    if (provisional.providerDefaultPreference == null &&
        provisional.threadStates.isEmpty &&
        provisional.pendingTurnStates.isEmpty &&
        provisional.persistenceFailure == null) {
      _discardProvisional(provisionalIdentity);
      return;
    }
    final current = stateFor(runtimeIdentity);
    _states[runtimeIdentity] = AgentPermissionState(
      runtimeIdentity: runtimeIdentity,
      providerDefaultPreference:
          provisional.providerDefaultPreference ??
          current.providerDefaultPreference,
      runtimeSelection: current.runtimeSelection,
      threadStates: <String, AgentThreadPermissionState>{
        ...provisional.threadStates,
        ...current.threadStates,
      },
      pendingTurnStates: <String, AgentThreadPermissionState>{
        ...provisional.pendingTurnStates,
        ...current.pendingTurnStates,
      },
      source: provisional.source ?? current.source,
      lastApplyScope: provisional.lastApplyScope ?? current.lastApplyScope,
      warning: provisional.warning ?? current.warning,
      persistenceFailure:
          provisional.persistenceFailure ?? current.persistenceFailure,
      revision: current.revision + 1,
    );
    _discardProvisional(provisionalIdentity, notify: false);
    _notify();
  }

  /// 将同一 Provider 的旧真实 runtime 状态迁入新 generation。
  ///
  /// 会话级 Provider 被空闲回收时，`runtime` scope 只属于旧进程，不能迁移；
  /// provider default、thread effective、current-turn override 与持久化失败仍属于
  /// 逻辑会话，需要保留到下次 resume。
  void adoptRetiredRuntimeState({
    required AgentProviderRuntimeIdentity previousIdentity,
    required AgentProviderRuntimeIdentity runtimeIdentity,
  }) {
    if (previousIdentity.isProvisional ||
        runtimeIdentity.isProvisional ||
        previousIdentity == runtimeIdentity ||
        previousIdentity.providerId != runtimeIdentity.providerId ||
        !isCurrent(runtimeIdentity)) {
      return;
    }
    final previous = _states[previousIdentity];
    if (previous == null) {
      return;
    }
    final current = stateFor(runtimeIdentity);
    _states[runtimeIdentity] = AgentPermissionState(
      runtimeIdentity: runtimeIdentity,
      providerDefaultPreference:
          previous.providerDefaultPreference ??
          current.providerDefaultPreference,
      // runtime selection 只属于已经退出的 CLI 进程，故意不迁移。
      threadStates: previous.threadStates,
      pendingTurnStates: previous.pendingTurnStates,
      source: previous.source ?? current.source,
      lastApplyScope: previous.lastApplyScope ?? current.lastApplyScope,
      warning: previous.warning ?? current.warning,
      persistenceFailure:
          previous.persistenceFailure ?? current.persistenceFailure,
      revision: previous.revision + 1,
    );
    _states.remove(previousIdentity);
    _notify();
  }

  void _discardProvisional(
    AgentProviderRuntimeIdentity identity, {
    bool notify = true,
  }) {
    if (!identity.isProvisional) {
      return;
    }
    if (_activeByProvider[identity.providerId] == identity) {
      _activeByProvider.remove(identity.providerId);
    }
    final removed = _states.remove(identity) != null;
    if (removed && notify) {
      _notify();
    }
  }

  /// 统一提交 adapter 返回的完整 apply result。
  bool commitApplyResult({
    required AgentProviderRuntimeIdentity identity,
    required String? threadId,
    required AgentPermissionApplyResult result,
    required AgentPermissionStateSource source,
    required bool updateDefault,
  }) {
    if (!isCurrent(identity)) {
      return false;
    }
    final current = stateFor(identity);
    final normalizedThread = _normalizeThreadId(threadId);
    final threads = Map<String, AgentThreadPermissionState>.from(
      current.threadStates,
    );
    final pendingTurns = Map<String, AgentThreadPermissionState>.from(
      current.pendingTurnStates,
    );
    var providerDefault = current.providerDefaultPreference;
    var runtimeSelection = current.runtimeSelection;
    var committedSource = source;

    switch (result.scope) {
      case AgentPermissionApplyScope.currentTurn:
        if (normalizedThread != null) {
          pendingTurns[normalizedThread] = AgentThreadPermissionState(
            threadId: normalizedThread,
            selection: result.normalizedSelection,
            source: source,
            lastApplyScope: result.scope,
            warning: result.warning,
          );
        }
      case AgentPermissionApplyScope.currentSession:
        if (normalizedThread != null) {
          threads[normalizedThread] = AgentThreadPermissionState(
            threadId: normalizedThread,
            selection: result.normalizedSelection,
            source: source,
            lastApplyScope: result.scope,
            warning: result.warning,
          );
        }
        if (updateDefault) {
          providerDefault = result.normalizedSelection;
        }
      case AgentPermissionApplyScope.runtime:
        runtimeSelection = result.normalizedSelection;
        committedSource = AgentPermissionStateSource.runtimeBroadcast;
        if (updateDefault) {
          providerDefault = result.normalizedSelection;
        }
      case AgentPermissionApplyScope.nextSession:
        if (updateDefault) {
          providerDefault = result.normalizedSelection;
        }
    }

    final next = AgentPermissionState(
      runtimeIdentity: identity,
      providerDefaultPreference: providerDefault,
      runtimeSelection: runtimeSelection,
      threadStates: threads,
      pendingTurnStates: pendingTurns,
      source: committedSource,
      lastApplyScope: result.scope,
      warning: result.warning,
      persistenceFailure:
          updateDefault && result.scope != AgentPermissionApplyScope.currentTurn
          ? null
          : current.persistenceFailure,
      revision: current.revision + 1,
    );
    _states[identity] = next;
    _notify();

    if (result.scope == AgentPermissionApplyScope.runtime) {
      _runtimeStates.add(
        AgentPermissionRuntimeState(
          runtimeIdentity: identity,
          selection: result.normalizedSelection,
          lastApplyScope: result.scope,
          warning: result.warning,
          revision: next.revision,
        ),
      );
    }
    return true;
  }

  /// 冻结一次请求权限；`currentTurn` override 在此被原子取走。
  AgentPermissionRequestSnapshot takeRequestSnapshot({
    required AgentProviderRuntimeIdentity identity,
    required String? threadId,
    required AgentPermissionSelection? catalogDefault,
  }) {
    if (!isCurrent(identity)) {
      return const AgentPermissionRequestSnapshot.providerFallback();
    }
    var current = stateFor(identity);
    final normalizedThread = _normalizeThreadId(threadId);
    if (normalizedThread != null) {
      final pending = current.pendingTurnStates[normalizedThread];
      if (pending != null) {
        final pendingTurns = Map<String, AgentThreadPermissionState>.from(
          current.pendingTurnStates,
        )..remove(normalizedThread);
        _states[identity] = _replace(current, pendingTurnStates: pendingTurns);
        current = _states[identity]!;
        return AgentPermissionRequestSnapshot.resolved(
          selection: pending.selection,
          source: AgentPermissionRequestSource.threadEffective,
        );
      }
    }

    // runtime-global 对所有 thread 生效，因此作为显式 effective override 参与同一
    // 中立优先级解析；resolver 本身不拥有状态，只集中定义来源顺序。
    final threadEffective =
        current.runtimeSelection ??
        (normalizedThread == null
            ? null
            : current.threadStates[normalizedThread]?.selection);
    return AgentPermissionRequestResolver.resolve(
      threadEffective: threadEffective,
      providerDefault: current.providerDefaultPreference,
      catalogDefault: catalogDefault,
    );
  }

  void recordPersistenceFailure({
    required AgentProviderRuntimeIdentity identity,
    required AgentPermissionSelection selection,
    required String message,
  }) {
    if (!isCurrent(identity)) {
      return;
    }
    final current = stateFor(identity);
    _states[identity] = _replace(
      current,
      persistenceFailure: AgentPermissionPersistenceFailure(
        selection: selection,
        message: message,
      ),
    );
    _notify();
  }

  void clearPersistenceFailure({
    required AgentProviderRuntimeIdentity identity,
    required AgentPermissionSelection selection,
  }) {
    if (!isCurrent(identity)) {
      return;
    }
    final current = stateFor(identity);
    if (current.persistenceFailure?.selection != selection) {
      return;
    }
    _states[identity] = _replace(current, clearPersistenceFailure: true);
    _notify();
  }

  AgentPermissionState _replace(
    AgentPermissionState current, {
    AgentPermissionSelection? providerDefaultPreference,
    AgentPermissionSelection? runtimeSelection,
    Map<String, AgentThreadPermissionState>? threadStates,
    Map<String, AgentThreadPermissionState>? pendingTurnStates,
    AgentPermissionStateSource? source,
    AgentPermissionApplyScope? lastApplyScope,
    String? warning,
    AgentPermissionPersistenceFailure? persistenceFailure,
    bool clearPersistenceFailure = false,
  }) {
    return AgentPermissionState(
      runtimeIdentity: current.runtimeIdentity,
      providerDefaultPreference:
          providerDefaultPreference ?? current.providerDefaultPreference,
      runtimeSelection: runtimeSelection ?? current.runtimeSelection,
      threadStates: threadStates ?? current.threadStates,
      pendingTurnStates: pendingTurnStates ?? current.pendingTurnStates,
      source: source ?? current.source,
      lastApplyScope: lastApplyScope ?? current.lastApplyScope,
      warning: warning ?? current.warning,
      persistenceFailure: clearPersistenceFailure
          ? null
          : persistenceFailure ?? current.persistenceFailure,
      revision: current.revision + 1,
    );
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_runtimeStates.close());
    super.dispose();
  }
}

String? _normalizeThreadId(String? threadId) {
  final normalized = threadId?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
