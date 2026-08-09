import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/application/agent_permission_request_resolver.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_identity.dart';
import 'package:zeta/src/features/agent/domain/agent_permission_policy_models.dart';

/// 会话权限事实的来源。
enum AgentPermissionStateSource {
  providerDefault,
  userSelection,
  serverSettings,
  runtimeSelection,
}

/// 当前会话内的一项已生效或待生效权限值。
@immutable
final class AgentConversationPermissionValue {
  const AgentConversationPermissionValue({
    required this.selection,
    required this.source,
    required this.lastApplyScope,
    this.warning,
  });

  final AgentPermissionSelection selection;
  final AgentPermissionStateSource source;
  final AgentPermissionApplyScope lastApplyScope;
  final String? warning;
}

/// Provider 已 apply、但默认偏好持久化失败的可重试状态。
@immutable
final class AgentPermissionPersistenceFailure {
  const AgentPermissionPersistenceFailure({
    required this.selection,
    required this.message,
  });

  final AgentPermissionSelection selection;
  final String message;
}

/// 一个 [AgentConversationBinding] 独占的不可变权限快照。
///
/// Binding 已经保证一个逻辑会话最多绑定一个 thread 和一个 session runtime，
/// 因此这里不再维护 provider/runtime/thread 注册表。runtime identity 只用于拒绝
/// 已失效 runtime 实例的迟到异步结果。
@immutable
final class AgentConversationPermissionState {
  const AgentConversationPermissionState({
    this.runtimeIdentity,
    this.threadId,
    this.providerDefaultPreference,
    this.sessionEffective,
    this.pendingTurn,
    this.runtimeSelection,
    this.source,
    this.lastApplyScope,
    this.warning,
    this.persistenceFailure,
    this.revision = 0,
  });

  final AgentProviderRuntimeIdentity? runtimeIdentity;
  final String? threadId;
  final AgentPermissionSelection? providerDefaultPreference;
  final AgentConversationPermissionValue? sessionEffective;

  /// `currentTurn` 只供下一次请求取走，不进入 session effective。
  final AgentConversationPermissionValue? pendingTurn;

  /// 只属于当前 CLI 进程；runtime 回收时清除。
  final AgentPermissionSelection? runtimeSelection;
  final AgentPermissionStateSource? source;
  final AgentPermissionApplyScope? lastApplyScope;
  final String? warning;
  final AgentPermissionPersistenceFailure? persistenceFailure;
  final int revision;

  AgentConversationPermissionValue? get effectiveValue {
    final pending = pendingTurn;
    if (pending != null) {
      return pending;
    }
    final runtime = runtimeSelection;
    if (runtime != null) {
      return AgentConversationPermissionValue(
        selection: runtime,
        source: AgentPermissionStateSource.runtimeSelection,
        lastApplyScope: AgentPermissionApplyScope.runtime,
        warning: warning,
      );
    }
    final session = sessionEffective;
    if (session != null) {
      return session;
    }
    final providerDefault = providerDefaultPreference;
    if (providerDefault == null) {
      return null;
    }
    return AgentConversationPermissionValue(
      selection: providerDefault,
      source: AgentPermissionStateSource.providerDefault,
      lastApplyScope: lastApplyScope ?? AgentPermissionApplyScope.nextSession,
      warning: warning,
    );
  }

  bool isCurrent(AgentProviderRuntimeIdentity identity) {
    return runtimeIdentity == identity;
  }

  /// draft 晋升为真实 thread 时保留逻辑状态；真实 thread 不允许改绑或退回 draft。
  AgentConversationPermissionState bindThread(String? value) {
    final normalized = _normalizeThreadId(value);
    if (normalized == threadId) {
      return this;
    }
    if (threadId != null) {
      throw StateError(
        'Permission state for $threadId cannot bind to '
        '${normalized ?? 'a draft'}',
      );
    }
    if (normalized == null) {
      return this;
    }
    return _copyWith(threadId: normalized, revision: revision + 1);
  }

  AgentConversationPermissionState attachRuntime(
    AgentProviderRuntimeIdentity identity, {
    AgentPermissionSelection? initialProviderDefault,
  }) {
    if (runtimeIdentity == identity) {
      return seedProviderDefault(initialProviderDefault);
    }
    return _copyWith(
      runtimeIdentity: identity,
      providerDefaultPreference:
          providerDefaultPreference ?? initialProviderDefault,
      runtimeSelection: null,
      revision: revision + 1,
    );
  }

  /// runtime-only selection 随 CLI 回收清除，逻辑会话状态继续保留。
  AgentConversationPermissionState detachRuntime() {
    if (runtimeIdentity == null && runtimeSelection == null) {
      return this;
    }
    final session = sessionEffective;
    final runtimeWasLast = lastApplyScope == AgentPermissionApplyScope.runtime;
    return _copyWith(
      runtimeIdentity: null,
      runtimeSelection: null,
      source: runtimeWasLast ? session?.source : source,
      lastApplyScope: runtimeWasLast ? session?.lastApplyScope : lastApplyScope,
      warning: runtimeWasLast ? session?.warning : warning,
      revision: revision + 1,
    );
  }

  AgentConversationPermissionState seedProviderDefault(
    AgentPermissionSelection? selection,
  ) {
    if (providerDefaultPreference != null || selection == null) {
      return this;
    }
    return _copyWith(
      providerDefaultPreference: selection,
      source: AgentPermissionStateSource.providerDefault,
      revision: revision + 1,
    );
  }

  AgentConversationPermissionState commitApplyResult({
    required AgentPermissionApplyResult result,
    required AgentPermissionStateSource source,
    required bool updateDefault,
  }) {
    var nextProviderDefault = providerDefaultPreference;
    var nextSession = sessionEffective;
    var nextPending = pendingTurn;
    var nextRuntime = runtimeSelection;
    var nextSource = source;
    final value = AgentConversationPermissionValue(
      selection: result.normalizedSelection,
      source: source,
      lastApplyScope: result.scope,
      warning: result.warning,
    );

    switch (result.scope) {
      case AgentPermissionApplyScope.currentTurn:
        nextPending = value;
      case AgentPermissionApplyScope.currentSession:
        nextSession = value;
        if (updateDefault) {
          nextProviderDefault = result.normalizedSelection;
        }
      case AgentPermissionApplyScope.runtime:
        nextRuntime = result.normalizedSelection;
        nextSource = AgentPermissionStateSource.runtimeSelection;
        if (updateDefault) {
          nextProviderDefault = result.normalizedSelection;
        }
      case AgentPermissionApplyScope.nextSession:
        if (updateDefault) {
          nextProviderDefault = result.normalizedSelection;
        }
    }

    return _copyWith(
      providerDefaultPreference: nextProviderDefault,
      sessionEffective: nextSession,
      pendingTurn: nextPending,
      runtimeSelection: nextRuntime,
      source: nextSource,
      lastApplyScope: result.scope,
      warning: result.warning,
      persistenceFailure:
          updateDefault && result.scope != AgentPermissionApplyScope.currentTurn
          ? null
          : persistenceFailure,
      revision: revision + 1,
    );
  }

  ({
    AgentConversationPermissionState state,
    AgentPermissionRequestSnapshot snapshot,
  })
  takeRequestSnapshot({
    required String? requestedThreadId,
    required AgentPermissionSelection? catalogDefault,
  }) {
    final requested = _normalizeThreadId(requestedThreadId);
    final addressesBinding =
        threadId == null || requested == null || requested == threadId;
    final pending = pendingTurn;
    if (addressesBinding && pending != null) {
      return (
        state: _copyWith(pendingTurn: null, revision: revision + 1),
        snapshot: AgentPermissionRequestSnapshot.resolved(
          selection: pending.selection,
          source: AgentPermissionRequestSource.threadEffective,
        ),
      );
    }

    final effective = addressesBinding
        ? runtimeSelection ?? sessionEffective?.selection
        : null;
    return (
      state: this,
      snapshot: AgentPermissionRequestResolver.resolve(
        threadEffective: effective,
        providerDefault: providerDefaultPreference,
        catalogDefault: catalogDefault,
      ),
    );
  }

  AgentConversationPermissionState recordPersistenceFailure({
    required AgentPermissionSelection selection,
    required String message,
  }) {
    return _copyWith(
      persistenceFailure: AgentPermissionPersistenceFailure(
        selection: selection,
        message: message,
      ),
      revision: revision + 1,
    );
  }

  AgentConversationPermissionState clearPersistenceFailure(
    AgentPermissionSelection selection,
  ) {
    if (persistenceFailure?.selection != selection) {
      return this;
    }
    return _copyWith(persistenceFailure: null, revision: revision + 1);
  }

  AgentConversationPermissionState _copyWith({
    Object? runtimeIdentity = _unset,
    Object? threadId = _unset,
    Object? providerDefaultPreference = _unset,
    Object? sessionEffective = _unset,
    Object? pendingTurn = _unset,
    Object? runtimeSelection = _unset,
    Object? source = _unset,
    Object? lastApplyScope = _unset,
    Object? warning = _unset,
    Object? persistenceFailure = _unset,
    int? revision,
  }) {
    return AgentConversationPermissionState(
      runtimeIdentity: identical(runtimeIdentity, _unset)
          ? this.runtimeIdentity
          : runtimeIdentity as AgentProviderRuntimeIdentity?,
      threadId: identical(threadId, _unset)
          ? this.threadId
          : threadId as String?,
      providerDefaultPreference: identical(providerDefaultPreference, _unset)
          ? this.providerDefaultPreference
          : providerDefaultPreference as AgentPermissionSelection?,
      sessionEffective: identical(sessionEffective, _unset)
          ? this.sessionEffective
          : sessionEffective as AgentConversationPermissionValue?,
      pendingTurn: identical(pendingTurn, _unset)
          ? this.pendingTurn
          : pendingTurn as AgentConversationPermissionValue?,
      runtimeSelection: identical(runtimeSelection, _unset)
          ? this.runtimeSelection
          : runtimeSelection as AgentPermissionSelection?,
      source: identical(source, _unset)
          ? this.source
          : source as AgentPermissionStateSource?,
      lastApplyScope: identical(lastApplyScope, _unset)
          ? this.lastApplyScope
          : lastApplyScope as AgentPermissionApplyScope?,
      warning: identical(warning, _unset) ? this.warning : warning as String?,
      persistenceFailure: identical(persistenceFailure, _unset)
          ? this.persistenceFailure
          : persistenceFailure as AgentPermissionPersistenceFailure?,
      revision: revision ?? this.revision,
    );
  }
}

const Object _unset = Object();

String? _normalizeThreadId(String? threadId) {
  final normalized = threadId?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
