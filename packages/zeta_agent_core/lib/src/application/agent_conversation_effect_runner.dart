import 'dart:async';

import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';
import 'package:zeta_agent_core/src/domain/agent_turn_terminal_signal.dart';

typedef AgentConversationEffectScopeReader =
    AgentConversationEffectScope? Function();
typedef AgentModelCatalogRecorder =
    Future<void> Function({
      required AgentProviderConfig config,
      required AgentModelList models,
      required String source,
    });
typedef AgentAttentionCallback = void Function(AgentAttentionSignal signal);
typedef AgentTurnTerminalCallback =
    void Function(AgentTurnTerminalSignal signal);

/// application effect 的执行端口。
abstract interface class AgentConversationEffectRunner {
  void run(AgentConversationEffect effect);

  void dispose();
}

/// 会话副作用宿主。由 ViewModel 实现，EffectRunner 在身份校验之后回调。
abstract interface class AgentConversationSessionEffectHandler {
  void bindConversationModeThread({required String threadId});

  void applyThreadPermission({
    required String threadId,
    required AgentPermissionSelection permissionSelection,
  });

  void applyThreadSettings(AgentThreadSettingsUpdatedEvent event);

  void syncThreadSelectionFromSessionConfig(
    List<AgentSessionConfigOption> options,
  );

  void applyServerConversationMode(AgentConversationModeUpdatedEvent event);

  void preparePlanHandoff(AgentTurnCompletedEvent event);

  void syncTurnRunning({bool? forceRunning});

  void autoStartPlanExecution();

  void clearPlanHandoff();

  void applyModelList(AgentModelList models);
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
    AgentTurnTerminalCallback? onTurnTerminal,
    AgentAttentionCallback? onAttention,
    AgentConversationSessionEffectHandler? sessionEffects,
  }) => DefaultAgentConversationEffectRunner._(
    currentScope,
    recordModelCatalog,
    onTurnTerminal,
    onAttention,
    sessionEffects,
  );

  DefaultAgentConversationEffectRunner._(
    this._currentScope,
    this._recordModelCatalog,
    this._onTurnTerminal,
    this._onAttention,
    this._sessionEffects,
  );

  static final _log = zetaLoggerFor('zeta.agent.conversation.effects');

  final AgentConversationEffectScopeReader _currentScope;
  final AgentModelCatalogRecorder _recordModelCatalog;
  final AgentTurnTerminalCallback? _onTurnTerminal;
  final AgentAttentionCallback? _onAttention;
  final AgentConversationSessionEffectHandler? _sessionEffects;
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
        final terminalSignal = AgentTurnTerminalSignal(
          providerId: effect.scope.providerId,
          threadId: effect.scope.threadId,
          turnId: effect.turnId,
        );
        _runSynchronous(
          effect,
          operation: 'turn/terminal-callback',
          callback: () => _onTurnTerminal?.call(terminalSignal),
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
      case AgentBindConversationModeThreadEffect():
        _runSession(
          effect,
          operation: 'session/bind-conversation-mode',
          callback: () => _sessionEffects?.bindConversationModeThread(
            threadId: effect.threadId,
          ),
        );
      case AgentApplyThreadPermissionEffect():
        _runSession(
          effect,
          operation: 'session/apply-thread-permission',
          callback: () => _sessionEffects?.applyThreadPermission(
            threadId: effect.threadId,
            permissionSelection: effect.permissionSelection,
          ),
        );
      case AgentApplyThreadSettingsEffect():
        _runSession(
          effect,
          operation: 'session/apply-thread-settings',
          callback: () => _sessionEffects?.applyThreadSettings(effect.event),
        );
      case AgentSyncThreadSelectionEffect():
        _runSession(
          effect,
          operation: 'session/sync-thread-selection',
          callback: () => _sessionEffects?.syncThreadSelectionFromSessionConfig(
            effect.options,
          ),
        );
      case AgentApplyServerConversationModeEffect():
        _runSession(
          effect,
          operation: 'session/apply-server-conversation-mode',
          callback: () =>
              _sessionEffects?.applyServerConversationMode(effect.event),
        );
      case AgentPreparePlanHandoffEffect():
        _runSession(
          effect,
          operation: 'session/prepare-plan-handoff',
          callback: () => _sessionEffects?.preparePlanHandoff(effect.event),
        );
      case AgentSyncTurnRunningEffect():
        _runSession(
          effect,
          operation: 'session/sync-turn-running',
          callback: () => _sessionEffects?.syncTurnRunning(
            forceRunning: effect.forceRunning,
          ),
        );
      case AgentAutoStartPlanExecutionEffect():
        _runSession(
          effect,
          operation: 'session/auto-start-plan-execution',
          callback: () => _sessionEffects?.autoStartPlanExecution(),
        );
      case AgentClearPlanHandoffEffect():
        _runSession(
          effect,
          operation: 'session/clear-plan-handoff',
          callback: () => _sessionEffects?.clearPlanHandoff(),
        );
      case AgentApplyModelListEffect():
        _runSession(
          effect,
          operation: 'session/apply-model-list',
          callback: () => _sessionEffects?.applyModelList(effect.models),
        );
    }
  }

  void _runSession(
    AgentConversationEffect effect, {
    required String operation,
    required void Function() callback,
  }) {
    _runSynchronous(effect, operation: operation, callback: callback);
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
    _log.failure(
      'Agent provider error event',
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
    _log.failure(
      'Agent conversation effect failed',
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
