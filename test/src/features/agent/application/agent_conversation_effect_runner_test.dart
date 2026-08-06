import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:zeta/src/features/agent/application/agent_conversation_effect.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_effect_runner.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('DefaultAgentConversationEffectRunner', () {
    test('runs a turn-completed callback once for matching full scope', () {
      // Arrange
      var currentScope = _scope(
        providerLifecycleState: 'ready',
        turnId: 'turn-current',
      );
      var callbackCount = 0;
      final runner = DefaultAgentConversationEffectRunner(
        currentScope: () => currentScope,
        recordModelCatalog: _discardCatalog,
        onTurnCompleted: () => callbackCount += 1,
      );
      addTearDown(runner.dispose);
      final effect = AgentTurnCompletedEffect(
        scope: _scope(providerLifecycleState: 'running', turnId: 'turn-1'),
        turnId: 'turn-1',
        attention: _turnCompletedAttention,
      );

      // Act
      runner.run(effect);
      runner.run(effect);

      // Assert
      expect(callbackCount, 1);

      // Provider、generation、runtime/epoch 与 thread 均属于强校验范围。
      for (final mismatchedScope in <AgentConversationEffectScope>[
        _scope(providerId: 'other-provider', turnId: 'turn-1'),
        _scope(listenerGeneration: 8, turnId: 'turn-1'),
        _scope(runtimeId: 'runtime-2', turnId: 'turn-1'),
        _scope(connectionEpoch: 4, turnId: 'turn-1'),
        _scope(threadId: 'thread-other', turnId: 'turn-1'),
        _scope(
          reductionScope: AgentConversationReductionScope.history,
          turnId: 'turn-1',
        ),
      ]) {
        runner.run(
          AgentTurnCompletedEffect(
            scope: mismatchedScope,
            turnId: 'turn-1',
            attention: _turnCompletedAttention,
          ),
        );
      }
      expect(callbackCount, 1);

      // lifecycle 仅用于诊断；completed turn 已归档，所以也不能要求 current
      // scope 的 turnId 仍等于 effect turnId。
      // 去重按对象 identity；新的 effect 实例仍代表一次新的执行。
      currentScope = _scope();
      runner.run(
        AgentTurnCompletedEffect(
          scope: _scope(turnId: 'turn-1'),
          turnId: 'turn-1',
          attention: _turnCompletedAttention,
        ),
      );
      expect(callbackCount, 2);
    });

    test(
      'records model catalog asynchronously once and ignores thread mismatch',
      () async {
        // Arrange
        final completion = Completer<void>();
        var currentScope = _scope(threadId: 'thread-current');
        var recordCount = 0;
        AgentProviderConfig? recordedConfig;
        AgentModelList? recordedModels;
        String? recordedSource;
        final runner = DefaultAgentConversationEffectRunner(
          currentScope: () => currentScope,
          recordModelCatalog:
              ({
                required AgentProviderConfig config,
                required AgentModelList models,
                required String source,
              }) {
                recordCount += 1;
                recordedConfig = config;
                recordedModels = models;
                recordedSource = source;
                return completion.future;
              },
        );
        addTearDown(runner.dispose);
        const models = AgentModelList(
          models: <AgentModelInfo>[
            AgentModelInfo(
              id: 'gpt-test',
              model: 'gpt-test',
              displayName: 'GPT Test',
            ),
          ],
        );
        final effect = AgentRecordModelCatalogEffect(
          scope: _scope(threadId: 'thread-from-event'),
          config: AgentProviderConfig.defaultCodex,
          models: models,
          source: 'runtime event',
        );

        // Act
        runner.run(effect);
        runner.run(effect);

        // Assert
        expect(recordCount, 1);
        expect(recordedConfig, AgentProviderConfig.defaultCodex);
        expect(recordedModels, same(models));
        expect(recordedSource, 'runtime event');

        // Provider-scoped effect 忽略 thread，但仍拒绝旧 generation/runtime。
        currentScope = _scope(threadId: 'another-current-thread');
        runner.run(
          AgentRecordModelCatalogEffect(
            scope: _scope(listenerGeneration: 8),
            config: AgentProviderConfig.defaultCodex,
            models: models,
            source: 'stale generation',
          ),
        );
        runner.run(
          AgentRecordModelCatalogEffect(
            scope: _scope(runtimeId: 'runtime-2'),
            config: AgentProviderConfig.defaultCodex,
            models: models,
            source: 'stale runtime',
          ),
        );
        expect(recordCount, 1);

        completion.complete();
        await pumpEventQueue();
      },
    );

    test(
      'logs provider errors only for matching provider generation and runtime',
      () async {
        // Arrange
        final records = <LogEvent>[];
        final listener = records.add;
        Logger.addLogListener(listener);
        addTearDown(() => Logger.removeLogListener(listener));
        final runner = DefaultAgentConversationEffectRunner(
          currentScope: () => _scope(threadId: 'thread-current'),
          recordModelCatalog: _discardCatalog,
        );
        addTearDown(runner.dispose);
        const staleMessage = 'effect-runner-stale-error';
        const acceptedMessage = 'effect-runner-accepted-error';

        // Act
        runner.run(
          AgentLogProviderErrorEffect(
            scope: _scope(
              listenerGeneration: 8,
              threadId: 'thread-other',
              turnId: 'turn-stale',
            ),
            event: const AgentErrorEvent(
              message: staleMessage,
              sessionId: 'thread-other',
              turnId: 'turn-stale',
            ),
          ),
        );
        final acceptedEffect = AgentLogProviderErrorEffect(
          scope: _scope(threadId: 'thread-other', turnId: 'turn-accepted'),
          event: const AgentErrorEvent(
            message: acceptedMessage,
            sessionId: 'thread-other',
            turnId: 'turn-accepted',
          ),
        );
        runner.run(acceptedEffect);
        runner.run(acceptedEffect);
        await pumpEventQueue();

        // Assert
        expect(
          records.where((record) => record.message.contains(staleMessage)),
          isEmpty,
        );
        final record = records.singleWhere(
          (record) => record.message.contains(acceptedMessage),
        );
        final context = _structuredContext(record);
        expect(context['providerId'], AgentProviderConfig.defaultCodex.id);
        expect(context['listenerGeneration'], 7);
        expect(context['runtimeId'], 'runtime-1');
        expect(context['connectionEpoch'], 3);
        // Error logging 是 provider-scoped，保留事件自己的 thread 诊断上下文。
        expect(context['threadId'], 'thread-other');
        expect(context['sessionId'], 'thread-other');
        expect(context['turnId'], 'turn-accepted');
      },
    );

    test('does not execute any new effect after dispose', () async {
      // Arrange
      var callbackCount = 0;
      var recordCount = 0;
      final records = <LogEvent>[];
      final listener = records.add;
      Logger.addLogListener(listener);
      addTearDown(() => Logger.removeLogListener(listener));
      final runner = DefaultAgentConversationEffectRunner(
        currentScope: _scope,
        recordModelCatalog:
            ({
              required AgentProviderConfig config,
              required AgentModelList models,
              required String source,
            }) async {
              recordCount += 1;
            },
        onTurnCompleted: () => callbackCount += 1,
      );
      runner.dispose();

      // Act
      runner.run(
        AgentTurnCompletedEffect(
          scope: _scope(turnId: 'turn-1'),
          turnId: 'turn-1',
          attention: _turnCompletedAttention,
        ),
      );
      runner.run(
        const AgentRecordModelCatalogEffect(
          scope: AgentConversationEffectScope(
            reductionScope: AgentConversationReductionScope.live,
            providerId: 'codex',
            listenerGeneration: 7,
            runtimeId: 'runtime-1',
            connectionEpoch: 3,
            threadId: 'thread-1',
          ),
          config: AgentProviderConfig.defaultCodex,
          models: AgentModelList(models: <AgentModelInfo>[]),
          source: 'disposed',
        ),
      );
      runner.run(
        AgentLogProviderErrorEffect(
          scope: _scope(turnId: 'turn-1'),
          event: const AgentErrorEvent(
            message: 'effect-runner-disposed-error',
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        ),
      );
      await pumpEventQueue();

      // Assert
      expect(callbackCount, 0);
      expect(recordCount, 0);
      expect(
        records.where(
          (record) => record.message.contains('effect-runner-disposed-error'),
        ),
        isEmpty,
      );
    });
  });
}

const _turnCompletedAttention = AgentAttentionSignal(
  kind: AgentAttentionKind.turnCompleted,
  phase: AgentAttentionPhase.raised,
  sourceId: 'turn-1',
  threadId: 'thread-1',
  turnId: 'turn-1',
);

AgentConversationEffectScope _scope({
  AgentConversationReductionScope reductionScope =
      AgentConversationReductionScope.live,
  String providerId = 'codex',
  int listenerGeneration = 7,
  String? runtimeId = 'runtime-1',
  int? connectionEpoch = 3,
  String? providerLifecycleState,
  String? threadId = 'thread-1',
  String? turnId,
}) {
  return AgentConversationEffectScope(
    reductionScope: reductionScope,
    providerId: providerId,
    listenerGeneration: listenerGeneration,
    runtimeId: runtimeId,
    connectionEpoch: connectionEpoch,
    providerLifecycleState: providerLifecycleState,
    threadId: threadId,
    turnId: turnId,
  );
}

Future<void> _discardCatalog({
  required AgentProviderConfig config,
  required AgentModelList models,
  required String source,
}) async {}

Map<String, Object?> _structuredContext(LogEvent record) {
  const prefix = 'Agent provider error event: ';
  final message = record.message;
  expect(message, startsWith(prefix));
  return (jsonDecode(message.substring(prefix.length)) as Map)
      .cast<String, Object?>();
}
