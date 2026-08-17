import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/application/agent_conversation_permission_selection_controller.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_identity.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';

/// 一个逻辑会话的稳定身份；草稿拿到真实 threadId 后会原子晋升。
sealed class AgentConversationBindingKey {
  const AgentConversationBindingKey({required this.providerId});

  final String providerId;

  const factory AgentConversationBindingKey.draft({
    required String providerId,
    required String entryId,
  }) = AgentConversationDraftBindingKey;

  const factory AgentConversationBindingKey.thread({
    required String providerId,
    required String threadId,
  }) = AgentConversationThreadBindingKey;
}

final class AgentConversationDraftBindingKey
    extends AgentConversationBindingKey {
  const AgentConversationDraftBindingKey({
    required super.providerId,
    required this.entryId,
  });

  final String entryId;

  @override
  bool operator ==(Object other) =>
      other is AgentConversationDraftBindingKey &&
      other.providerId == providerId &&
      other.entryId == entryId;

  @override
  int get hashCode => Object.hash(runtimeType, providerId, entryId);

  @override
  String toString() => 'draft($providerId,$entryId)';
}

final class AgentConversationThreadBindingKey
    extends AgentConversationBindingKey {
  const AgentConversationThreadBindingKey({
    required super.providerId,
    required this.threadId,
  });

  final String threadId;

  @override
  bool operator ==(Object other) =>
      other is AgentConversationThreadBindingKey &&
      other.providerId == providerId &&
      other.threadId == threadId;

  @override
  int get hashCode => Object.hash(runtimeType, providerId, threadId);

  @override
  String toString() => 'thread($providerId,$threadId)';
}

/// Binding 当前会话运行时的只读能力上下文。
@immutable
final class AgentConversationRuntimeContext {
  const AgentConversationRuntimeContext({
    required this.bundle,
    required this.runtimeIdentity,
  });

  final AgentProviderBundle bundle;
  final AgentProviderRuntimeIdentity runtimeIdentity;

  AgentProviderConfig get config => bundle.runtime.config;
  AgentProviderCapabilities get capabilities => bundle.runtime.capabilities;
  AgentRuntimeScope? get runtimeScope => bundle.runtime.runtimeScope;
}

/// 空闲扫描使用的不可变候选，带精确 runtime identity 防止 ABA。
@immutable
final class AgentConversationBindingRuntimeSnapshot {
  const AgentConversationBindingRuntimeSnapshot({
    required this.runtimeIdentity,
    required this.lastActiveAt,
    required this.activeOperationCount,
  });

  final AgentProviderRuntimeIdentity runtimeIdentity;
  final DateTime lastActiveAt;
  final int activeOperationCount;
}

/// 从首次发送开始持有到 turn 终态的活动令牌。
final class AgentConversationTurnActivity {
  AgentConversationTurnActivity._(this.runtime, this._binding);

  final AgentConversationRuntimeContext runtime;
  AgentConversationBinding? _binding;

  bool get isCurrent =>
      _binding?.isRuntimeCurrent(runtime.runtimeIdentity) ?? false;

  Future<void> release() async {
    final binding = _binding;
    if (binding == null) {
      return;
    }
    _binding = null;
    binding._finishActivity(runtime.runtimeIdentity);
  }
}

/// Manager 同步提交 draft→thread 映射；不得做异步工作，以免出现半晋升窗口。
typedef AgentConversationBindingPromotion =
    void Function(
      AgentConversationBinding binding,
      AgentConversationBindingKey previousKey,
      AgentConversationThreadBindingKey nextKey,
    );

/// runtime 被清除后通知 Manager，以便立刻回收无消费者空壳 Binding。
typedef AgentConversationBindingRuntimeCleared =
    void Function(AgentConversationBinding binding);

/// 一个逻辑会话的运行时聚合根。
///
/// 它长期保存会话权限和事件入口，但 session Provider 仍由 registry 唯一拥有；
/// 只有 [beginTurn] 可以惰性创建 Provider，其他操作只能通过 [runCurrent] 使用
/// 已存在的实例。
final class AgentConversationBinding extends ChangeNotifier {
  AgentConversationBinding({
    required AgentConversationBindingKey key,
    required String runtimeScopeId,
    required AgentProviderRuntimeRegistry runtimeRegistry,
    required AgentProviderConfig Function(String providerId) resolveConfig,
    required Future<void> Function(String optionId) persistPermissionOptionId,
    required DateTime Function() clock,
    required AgentConversationBindingPromotion promote,
    required AgentConversationBindingRuntimeCleared onRuntimeCleared,
    AgentUiTextCatalog? textCatalog,
  }) : _key = key,
       _runtimeScope = AgentProviderRuntimeScopeKey.session(runtimeScopeId),
       _clock = clock,
       permissions = AgentConversationPermissionSelectionController(
         persistOptionId: persistPermissionOptionId,
         textCatalog: textCatalog,
       ),
       _lastActiveAt = clock() {
    _runtimeRegistry = runtimeRegistry;
    _runtimeRegistry.addListener(_handleRuntimeRegistryChanged);
    _resolveConfig = resolveConfig;
    _promote = promote;
    _onRuntimeCleared = onRuntimeCleared;
    final config = _resolveConfig(key.providerId);
    permissions.resetForProvider(
      port: null,
      persistedOptionId: config.resolvedPermissionOptionId,
    );
    permissions.bindThread(_threadIdOf(key));
  }

  AgentConversationBindingKey _key;
  final AgentProviderRuntimeScopeKey _runtimeScope;
  late final AgentProviderRuntimeRegistry _runtimeRegistry;
  late final AgentProviderConfig Function(String providerId) _resolveConfig;
  final DateTime Function() _clock;
  late final AgentConversationBindingPromotion _promote;
  late final AgentConversationBindingRuntimeCleared _onRuntimeCleared;
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast(sync: true);

  final AgentConversationPermissionSelectionController permissions;

  AgentProviderRuntimeLease? _runtimeLease;
  Future<AgentConversationRuntimeContext>? _runtimeFuture;
  StreamSubscription<AgentEvent>? _providerEvents;
  int _activeOperationCount = 0;
  int _consumerCount = 0;
  DateTime _lastActiveAt;
  bool _disposed = false;

  AgentConversationBindingKey get key => _key;
  String get providerId => _key.providerId;
  String? get threadId => _threadIdOf(_key);
  Stream<AgentEvent> get events => _events.stream;
  int get consumerCount => _consumerCount;
  bool get hasRuntime => currentRuntime != null;

  AgentConversationRuntimeContext? get currentRuntime {
    final lease = _runtimeLease;
    if (lease == null || !lease.isCurrent) {
      return null;
    }
    return AgentConversationRuntimeContext(
      bundle: lease.bundle,
      runtimeIdentity: lease.runtimeIdentity,
    );
  }

  AgentConversationBindingRuntimeSnapshot? get runtimeSnapshot {
    final runtime = currentRuntime;
    if (runtime == null) {
      return null;
    }
    return AgentConversationBindingRuntimeSnapshot(
      runtimeIdentity: runtime.runtimeIdentity,
      lastActiveAt: _lastActiveAt,
      activeOperationCount: _activeOperationCount,
    );
  }

  void attachConsumer() {
    if (_disposed) {
      throw StateError('Agent conversation binding is disposed');
    }
    _consumerCount += 1;
  }

  void detachConsumer() {
    if (_consumerCount > 0) {
      _consumerCount -= 1;
    }
  }

  /// 绑定 global runtime 读取到的目录；不会把 global port 当成 session apply port。
  Future<void> bindPermissionCatalog({
    required AgentPermissionPolicyPort? port,
    required String? persistedOptionId,
  }) async {
    permissions.bindCatalogOnly(
      port: port,
      persistedOptionId: persistedOptionId,
    );
    await permissions.refreshOptions();
  }

  /// 唯一允许创建 session Provider 的入口。
  Future<AgentConversationTurnActivity> beginTurn() async {
    _activeOperationCount += 1;
    _touch();
    notifyListeners();
    try {
      final runtime = await _ensureRuntime();
      return AgentConversationTurnActivity._(runtime, this);
    } catch (_) {
      _activeOperationCount -= 1;
      _touch();
      notifyListeners();
      rethrow;
    }
  }

  /// 在当前实例上执行短操作；实例不存在或已经被回收时返回 null。
  Future<T?> runCurrent<T>(
    Future<T> Function(AgentConversationRuntimeContext runtime) operation,
  ) async {
    final runtime = currentRuntime;
    if (runtime == null) {
      return null;
    }
    _activeOperationCount += 1;
    _touch();
    notifyListeners();
    try {
      return await operation(runtime);
    } finally {
      _finishActivity(runtime.runtimeIdentity);
    }
  }

  bool isRuntimeCurrent(AgentProviderRuntimeIdentity identity) {
    return currentRuntime?.runtimeIdentity == identity;
  }

  /// 草稿拿到真实 threadId 后由 manager 原子重建索引。
  ///
  /// 映射、[_key] 与权限 threadId 在同一同步提交中完成，随后才通知监听者。
  void promoteToThread(String threadId) {
    final normalized = threadId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(threadId, 'threadId', 'Must not be empty');
    }
    final previous = _key;
    final next = AgentConversationThreadBindingKey(
      providerId: providerId,
      threadId: normalized,
    );
    if (previous == next) {
      return;
    }
    if (previous is AgentConversationThreadBindingKey) {
      throw StateError(
        'Conversation $previous cannot be rebound to $next; '
        'acquire a separate Binding for the target thread',
      );
    }
    _promote(this, previous, next);
    notifyListeners();
  }

  /// 仅供 Manager 在同步晋升提交阶段写入 thread 身份；调用方负责之后统一通知。
  void acceptPromotedThreadKey(AgentConversationThreadBindingKey nextKey) {
    if (_disposed) {
      throw StateError('Agent conversation binding is disposed');
    }
    if (_key is AgentConversationThreadBindingKey && _key != nextKey) {
      throw StateError(
        'Conversation $_key cannot be rebound to $nextKey; '
        'acquire a separate Binding for the target thread',
      );
    }
    _key = nextKey;
    permissions.bindThread(nextKey.threadId);
  }

  /// 按精确 identity 回收空闲实例。返回 false 表示候选已经过期。
  Future<bool> reapIfIdle({
    required AgentProviderRuntimeIdentity expectedIdentity,
    required DateTime idleCutoff,
  }) async {
    final snapshot = runtimeSnapshot;
    if (snapshot == null ||
        snapshot.runtimeIdentity != expectedIdentity ||
        snapshot.activeOperationCount != 0 ||
        snapshot.lastActiveAt.isAfter(idleCutoff)) {
      return false;
    }
    return _detachRuntime(expectedIdentity: expectedIdentity, invalidate: true);
  }

  Future<void> invalidateRuntime() async {
    final identity = currentRuntime?.runtimeIdentity;
    if (identity == null) {
      return;
    }
    await _detachRuntime(expectedIdentity: identity, invalidate: true);
  }

  Future<AgentConversationRuntimeContext> _ensureRuntime() async {
    if (_disposed) {
      throw StateError('Agent conversation binding is disposed');
    }
    final current = currentRuntime;
    if (current != null) {
      return current;
    }
    final creating = _runtimeFuture;
    if (creating != null) {
      return creating;
    }
    final future = _createRuntime();
    _runtimeFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_runtimeFuture, future)) {
        _runtimeFuture = null;
      }
    }
  }

  Future<AgentConversationRuntimeContext> _createRuntime() async {
    final config = _resolveConfig(providerId);
    if (config.id != providerId) {
      throw StateError(
        'Binding for $providerId resolved configuration for ${config.id}',
      );
    }
    final staleLease = _runtimeLease;
    if (staleLease != null && !staleLease.isCurrent) {
      _runtimeLease = null;
      await staleLease.release();
      permissions.detachRuntime();
    }
    final lease = await _runtimeRegistry.acquire(config, scope: _runtimeScope);
    try {
      final bundle = lease.bundle;
      await bundle.runtime.initialize();
      if (_disposed || !lease.isCurrent) {
        throw StateError('Agent conversation runtime was invalidated');
      }
      _runtimeLease = lease;
      final runtime = AgentConversationRuntimeContext(
        bundle: bundle,
        runtimeIdentity: lease.runtimeIdentity,
      );
      permissions.bind(
        port: runtime.bundle.permissionPolicy,
        persistedOptionId: config.resolvedPermissionOptionId,
        runtimeIdentity: runtime.runtimeIdentity,
      );
      // global runtime 预热出的完整目录在端口切换期间继续可见；session 端口随后
      // 重新校验目录，确保本次请求使用当前 runtime 的 allowed/default 事实。
      await permissions.refreshOptions();
      if (_disposed || !lease.isCurrent) {
        throw StateError('Agent conversation runtime was invalidated');
      }
      await _replaceProviderEvents(runtime);
      _touch();
      notifyListeners();
      return runtime;
    } catch (_) {
      await _runtimeRegistry.invalidateScopeIfCurrent(
        providerId: config.id,
        scope: _runtimeScope,
        expectedIdentity: lease.runtimeIdentity,
      );
      await lease.release();
      rethrow;
    }
  }

  Future<void> _replaceProviderEvents(
    AgentConversationRuntimeContext runtime,
  ) async {
    await _providerEvents?.cancel();
    final identity = runtime.runtimeIdentity;
    _providerEvents = runtime.bundle.runtime.events.listen(
      (event) {
        if (!_disposed && isRuntimeCurrent(identity)) {
          _events.add(event);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_disposed && isRuntimeCurrent(identity)) {
          _events.addError(error, stackTrace);
        }
      },
      onDone: () {
        if (!_disposed && isRuntimeCurrent(identity)) {
          unawaited(_handleProviderEventsDone(identity));
        }
      },
    );
  }

  Future<void> _handleProviderEventsDone(
    AgentProviderRuntimeIdentity identity,
  ) async {
    // CLI 的事件流关闭即表示该 session runtime 已不可继续使用。只按捕获的
    // identity 条件失效，避免旧流迟到的 onDone 误伤后来创建的新进程。
    await _detachRuntime(expectedIdentity: identity, invalidate: true);
  }

  Future<bool> _detachRuntime({
    required AgentProviderRuntimeIdentity expectedIdentity,
    required bool invalidate,
  }) async {
    final lease = _runtimeLease;
    if (lease == null || lease.runtimeIdentity != expectedIdentity) {
      return false;
    }
    _runtimeLease = null;
    final providerEvents = _providerEvents;
    _providerEvents = null;
    permissions.detachRuntime();
    notifyListeners();
    // runtime 事后消失时复检「无消费者空壳」不变量；不能只靠 _release /
    // 带 runtime 的 idle sweep，否则外部 invalidate 会留下永久幽灵 Binding。
    _notifyRuntimeCleared();
    // 先调用 registry 的条件失效：该调用在第一次 await 前会移除旧 entry 并
    // 建立 dispose barrier。这样并发 beginTurn/acquire 要么看见旧 identity 已
    // 失效，要么等待旧 CLI 完全退出，不能在 cancel/release 窗口复用旧进程。
    final invalidation = invalidate
        ? _runtimeRegistry.invalidateScopeIfCurrent(
            providerId: providerId,
            scope: _runtimeScope,
            expectedIdentity: expectedIdentity,
          )
        : Future<bool>.value(false);
    await providerEvents?.cancel();
    await invalidation;
    await lease.release();
    return true;
  }

  void _notifyRuntimeCleared() {
    if (_disposed) {
      return;
    }
    _onRuntimeCleared(this);
  }

  void _finishActivity(AgentProviderRuntimeIdentity identity) {
    if (_activeOperationCount > 0) {
      _activeOperationCount -= 1;
    }
    if (isRuntimeCurrent(identity)) {
      _touch();
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _touch() {
    _lastActiveAt = _clock();
  }

  void _handleRuntimeRegistryChanged() {
    final lease = _runtimeLease;
    if (_disposed || lease == null || lease.isCurrent) {
      return;
    }
    _runtimeLease = null;
    unawaited(_providerEvents?.cancel());
    _providerEvents = null;
    permissions.detachRuntime();
    unawaited(lease.release());
    notifyListeners();
    _notifyRuntimeCleared();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _runtimeRegistry.removeListener(_handleRuntimeRegistryChanged);
    final lease = _runtimeLease;
    _runtimeLease = null;
    unawaited(_providerEvents?.cancel());
    _providerEvents = null;
    unawaited(lease?.release());
    permissions.dispose();
    unawaited(_events.close());
    super.dispose();
  }
}

String? _threadIdOf(AgentConversationBindingKey key) {
  return switch (key) {
    AgentConversationThreadBindingKey(:final threadId) => threadId,
    AgentConversationDraftBindingKey() => null,
  };
}
