import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_binding.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_identity.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/fallback_agent_ui_text_catalog.dart';

final _log = loggerFor('zeta.agent.conversation_bindings');

/// Workspace 对 Binding 的可释放引用。
final class AgentConversationBindingLease {
  AgentConversationBindingLease._(this.binding, this._manager);

  final AgentConversationBinding binding;
  AgentConversationBindingManager? _manager;

  Future<void> release() async {
    final manager = _manager;
    if (manager == null) {
      return;
    }
    _manager = null;
    manager._release(binding);
  }
}

/// 维护逻辑会话到 [AgentConversationBinding] 的唯一映射，并统一执行空闲回收。
final class AgentConversationBindingManager extends ChangeNotifier {
  AgentConversationBindingManager({
    required this.runtimeRegistry,
    DateTime Function()? clock,
    Timer Function(Duration duration, void Function(Timer timer) callback)?
    timerFactory,
    this.scanInterval = const Duration(minutes: 1),
    this.idleTtl = const Duration(minutes: 10),
    AgentUiTextCatalog? textCatalog,
  }) : clock = clock ?? DateTime.now,
       timerFactory = timerFactory ?? Timer.periodic,
       _textCatalog = textCatalog ?? const FallbackAgentUiTextCatalog();

  final AgentProviderRuntimeRegistry runtimeRegistry;
  final DateTime Function() clock;
  final Timer Function(Duration duration, void Function(Timer timer) callback)
  timerFactory;
  final Duration scanInterval;
  final Duration idleTtl;
  final AgentUiTextCatalog _textCatalog;

  final Map<AgentConversationBindingKey, AgentConversationBinding> _bindings =
      <AgentConversationBindingKey, AgentConversationBinding>{};
  int _nextRuntimeScopeId = 0;
  Timer? _timer;
  Future<void>? _sweepFuture;
  bool _closed = false;

  UnmodifiableMapView<AgentConversationBindingKey, AgentConversationBinding>
  get bindings => UnmodifiableMapView(_bindings);

  bool get isRunning => _timer != null;

  void start() {
    if (_closed || _timer != null) {
      return;
    }
    _timer = timerFactory(scanInterval, (_) => _scheduleSweep());
  }

  AgentConversationBindingLease acquireDraft({
    required String providerId,
    required String entryId,
    required AgentProviderConfig Function(String providerId) resolveConfig,
    required Future<void> Function(String optionId) persistPermissionOptionId,
  }) {
    return _acquire(
      AgentConversationBindingKey.draft(
        providerId: providerId,
        entryId: entryId,
      ),
      resolveConfig: resolveConfig,
      persistPermissionOptionId: persistPermissionOptionId,
    );
  }

  AgentConversationBindingLease acquireThread({
    required String providerId,
    required String threadId,
    required AgentProviderConfig Function(String providerId) resolveConfig,
    required Future<void> Function(String optionId) persistPermissionOptionId,
  }) {
    return _acquire(
      AgentConversationBindingKey.thread(
        providerId: providerId,
        threadId: threadId,
      ),
      resolveConfig: resolveConfig,
      persistPermissionOptionId: persistPermissionOptionId,
    );
  }

  AgentConversationBinding? bindingForThread({
    required String providerId,
    required String threadId,
  }) {
    return _bindings[AgentConversationBindingKey.thread(
      providerId: providerId,
      threadId: threadId,
    )];
  }

  Future<void> sweepNow() {
    final existing = _sweepFuture;
    if (existing != null) {
      return existing;
    }
    final future = _sweepOnce();
    _sweepFuture = future;
    return future.whenComplete(() {
      if (identical(_sweepFuture, future)) {
        _sweepFuture = null;
      }
    });
  }

  void _scheduleSweep() {
    unawaited(
      sweepNow().catchError((Object error, StackTrace stackTrace) {
        _log.w(
          'Conversation binding idle sweep failed',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  AgentConversationBindingLease _acquire(
    AgentConversationBindingKey key, {
    required AgentProviderConfig Function(String providerId) resolveConfig,
    required Future<void> Function(String optionId) persistPermissionOptionId,
  }) {
    if (_closed) {
      throw StateError('Agent conversation binding manager is closed');
    }
    var binding = _bindings[key];
    binding ??= AgentConversationBinding(
      key: key,
      runtimeScopeId: 'agent-conversation-binding-${_nextRuntimeScopeId += 1}',
      runtimeRegistry: runtimeRegistry,
      resolveConfig: resolveConfig,
      persistPermissionOptionId: persistPermissionOptionId,
      clock: clock,
      promote: _promote,
      onRuntimeCleared: _handleRuntimeCleared,
      textCatalog: _textCatalog,
    );
    _bindings[key] = binding;
    binding.attachConsumer();
    notifyListeners();
    return AgentConversationBindingLease._(binding, this);
  }

  /// 同步原子晋升：先写入 Binding 身份，再改映射，最后才通知监听者。
  void _promote(
    AgentConversationBinding binding,
    AgentConversationBindingKey previousKey,
    AgentConversationThreadBindingKey nextKey,
  ) {
    if (!identical(_bindings[previousKey], binding)) {
      throw StateError('Conversation binding is no longer registered');
    }
    final collision = _bindings[nextKey];
    if (collision != null && !identical(collision, binding)) {
      throw StateError(
        'Thread ${nextKey.threadId} already has a conversation binding',
      );
    }
    binding.acceptPromotedThreadKey(nextKey);
    _bindings.remove(previousKey);
    _bindings[nextKey] = binding;
    notifyListeners();
  }

  void _release(AgentConversationBinding binding) {
    binding.detachConsumer();
    _pruneIfOrphan(binding);
    notifyListeners();
  }

  /// Binding 在外部失效或 idle reap 后清除 runtime 时回调。
  ///
  /// 与 [_release] 共用「无消费者且无 runtime → 移除」不变量，避免只清进程、
  /// 却把轻量 Binding 永久留在映射中。
  void _handleRuntimeCleared(AgentConversationBinding binding) {
    if (_closed) {
      return;
    }
    if (_pruneIfOrphan(binding)) {
      notifyListeners();
    }
  }

  bool _pruneIfOrphan(AgentConversationBinding binding) {
    if (binding.consumerCount != 0 || binding.hasRuntime) {
      return false;
    }
    _removeBinding(binding);
    return true;
  }

  Future<void> _sweepOnce() async {
    if (_closed) {
      return;
    }
    final cutoff = clock().subtract(idleTtl);
    final candidates =
        <
          ({
            AgentConversationBinding binding,
            AgentProviderRuntimeIdentity identity,
          })
        >[];
    for (final binding in _bindings.values) {
      final snapshot = binding.runtimeSnapshot;
      if (snapshot != null &&
          snapshot.activeOperationCount == 0 &&
          !snapshot.lastActiveAt.isAfter(cutoff)) {
        candidates.add((binding: binding, identity: snapshot.runtimeIdentity));
      }
    }
    for (final candidate in candidates) {
      final reaped = await candidate.binding.reapIfIdle(
        expectedIdentity: candidate.identity,
        idleCutoff: cutoff,
      );
      if (reaped &&
          candidate.binding.consumerCount == 0 &&
          !candidate.binding.hasRuntime) {
        _removeBinding(candidate.binding);
      }
    }
  }

  void _removeBinding(AgentConversationBinding binding) {
    final key = _bindings.entries
        .where((entry) => identical(entry.value, binding))
        .map((entry) => entry.key)
        .firstOrNull;
    if (key == null) {
      return;
    }
    _bindings.remove(key);
    binding.dispose();
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _timer?.cancel();
    _timer = null;
    await _sweepFuture;
    final bindings = _bindings.values.toSet().toList(growable: false);
    _bindings.clear();
    for (final binding in bindings) {
      binding.dispose();
    }
    notifyListeners();
    super.dispose();
  }
}
