import 'dart:async';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/core/logging/structured_error_logging.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_effect.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

typedef AgentConversationEffectScopeReader =
    AgentConversationEffectScope? Function();
typedef AgentModelCatalogRecorder =
    Future<void> Function({
      required AgentProviderConfig config,
      required AgentModelList models,
      required String source,
    });
typedef AgentAttentionCallback = void Function(AgentAttentionSignal signal);

/// application effect 的执行端口。
abstract interface class AgentConversationEffectRunner {
  void run(AgentConversationEffect effect);

  void dispose();
}

/// 生产环境 effect runner。
///
/// 每个 effect 先校验 listener generation、runtime/epoch 与必要 thread scope；
/// 同一个 effect 实例最多执行一次。异步失败只记录诊断，不回滚已接受事件。
final class DefaultAgentConversationEffectRunner
    implements AgentConversationEffectRunner {
  factory DefaultAgentConversationEffectRunner({
    required AgentConversationEffectScopeReader currentScope,
    required AgentModelCatalogRecorder recordModelCatalog,
    void Function()? onTurnCompleted,
    AgentAttentionCallback? onAttention,
  }) => DefaultAgentConversationEffectRunner._(
    currentScope,
    recordModelCatalog,
    onTurnCompleted,
    onAttention,
  );

  DefaultAgentConversationEffectRunner._(
    this._currentScope,
    this._recordModelCatalog,
    this._onTurnCompleted,
    this._onAttention,
  );

  static final _log = loggerFor('zeta.agent.conversation.effects');

  final AgentConversationEffectScopeReader _currentScope;
  final AgentModelCatalogRecorder _recordModelCatalog;
  final void Function()? _onTurnCompleted;
  final AgentAttentionCallback? _onAttention;
  Expando<bool> _executed = Expando<bool>(
    'AgentConversationEffectRunner.executed',
  );
  bool _disposed = false;

  @override
  void run(AgentConversationEffect effect) {
    if (_disposed ||
        !effect.scope.matches(
          _currentScope(),
          requireThread: effect.requireThread,
        ) ||
        _executed[effect] == true) {
      return;
    }
    // Expando 不强持有 effect，长生命周期会话不会因 once 语义积累历史对象。
    _executed[effect] = true;

    switch (effect) {
      case AgentTurnCompletedEffect():
        _runSynchronous(
          effect,
          operation: 'turn/completed-callback',
          callback: () => _onTurnCompleted?.call(),
        );
        _runSynchronous(
          effect,
          operation: 'turn/completed-attention',
          callback: () => _onAttention?.call(effect.attention),
        );
      case AgentAttentionEffect():
        _runSynchronous(
          effect,
          operation: 'agent-attention',
          callback: () => _onAttention?.call(effect.signal),
        );
      case AgentRecordModelCatalogEffect():
        _runModelCatalogRecord(effect);
      case AgentLogProviderErrorEffect():
        _logProviderError(effect);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _executed = Expando<bool>('AgentConversationEffectRunner.disposed');
  }

  void _runModelCatalogRecord(AgentRecordModelCatalogEffect effect) {
    try {
      final future = _recordModelCatalog(
        config: effect.config,
        models: effect.models,
        source: effect.source,
      );
      unawaited(
        future.catchError((Object error, StackTrace stackTrace) {
          _logEffectFailure(
            effect,
            operation: 'model-catalog/record',
            error: error,
            stackTrace: stackTrace,
          );
        }),
      );
    } catch (error, stackTrace) {
      _logEffectFailure(
        effect,
        operation: 'model-catalog/record',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _logProviderError(AgentLogProviderErrorEffect effect) {
    final event = effect.event;
    logStructuredFailure(
      _log,
      message: 'Agent provider error event',
      error: event.exception,
      stackTrace: event.stackTrace,
      context: <String, Object?>{
        ..._scopeLogContext(effect.scope),
        'operation': 'provider/event',
        'eventType': event.runtimeType.toString(),
        'sessionId': event.sessionId,
        'turnId': event.turnId,
        'message': event.message,
        'details': event.details,
        'code': event.code,
        'willRetry': event.willRetry,
        'diagnostic': event.raw,
      },
    );
  }

  void _runSynchronous(
    AgentConversationEffect effect, {
    required String operation,
    required void Function() callback,
  }) {
    try {
      callback();
    } catch (error, stackTrace) {
      _logEffectFailure(
        effect,
        operation: operation,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _logEffectFailure(
    AgentConversationEffect effect, {
    required String operation,
    required Object error,
    required StackTrace stackTrace,
  }) {
    logStructuredFailure(
      _log,
      message: 'Agent conversation effect failed',
      error: error,
      stackTrace: stackTrace,
      context: <String, Object?>{
        ..._scopeLogContext(effect.scope),
        'operation': operation,
        'effectType': effect.runtimeType.toString(),
      },
    );
  }

  Map<String, Object?> _scopeLogContext(AgentConversationEffectScope scope) {
    return <String, Object?>{
      'providerId': scope.providerId,
      'listenerGeneration': scope.listenerGeneration,
      if (scope.providerLifecycleState != null)
        'lifecycleState': scope.providerLifecycleState,
      if (scope.runtimeId != null) 'runtimeId': scope.runtimeId,
      if (scope.connectionEpoch != null)
        'connectionEpoch': scope.connectionEpoch,
      if (scope.threadId != null) 'threadId': scope.threadId,
      if (scope.turnId != null) 'turnId': scope.turnId,
      'reductionScope': scope.reductionScope.name,
    };
  }
}
