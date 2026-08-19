import 'dart:async';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/agent_turn_context_store.dart';
import 'package:zeta/src/features/agent/domain/agent_event_models.dart';
import 'package:zeta/src/features/agent/domain/agent_turn_context_models.dart';

final _log = loggerFor('zeta.agent.turn_context');

/// 将 live turn 开始/结束事件旁路写入会话上下文存储。
abstract interface class AgentTurnContextRecorder {
  void recordStarted({
    required String providerId,
    required AgentTurnStartedEvent event,
  });

  void recordCompleted({
    required String providerId,
    required AgentTurnCompletedEvent event,
  });
}

/// 异步字段级 upsert；失败只记诊断，不回抛到时间线。
final class DefaultAgentTurnContextRecorder
    implements AgentTurnContextRecorder {
  DefaultAgentTurnContextRecorder({
    required this._store,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AgentTurnContextStore _store;
  final DateTime Function() _now;
  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  @override
  void recordStarted({
    required String providerId,
    required AgentTurnStartedEvent event,
  }) {
    unawaited(
      _enqueue(
        providerId: providerId,
        threadId: event.turn.sessionId,
        incoming: AgentTurnContextRecord(
          turnId: event.turn.id,
          modelId: event.modelId,
          reasoningEffort: event.reasoningEffort,
          serviceTierId: event.serviceTierId,
          explicitFast: event.explicitFast,
          startedAt: event.startedAt,
        ),
        fillStartedAt: true,
      ),
    );
  }

  @override
  void recordCompleted({
    required String providerId,
    required AgentTurnCompletedEvent event,
  }) {
    unawaited(
      _enqueue(
        providerId: providerId,
        threadId: event.sessionId,
        incoming: AgentTurnContextRecord(
          turnId: event.turnId,
          completedAt: event.completedAt,
          status: event.status,
        ),
        fillCompletedAt: true,
      ),
    );
  }

  Future<void> _enqueue({
    required String providerId,
    required String threadId,
    required AgentTurnContextRecord incoming,
    bool fillStartedAt = false,
    bool fillCompletedAt = false,
  }) {
    final normalizedProviderId = providerId.trim();
    final normalizedThreadId = threadId.trim();
    final turnId = incoming.turnId.trim();
    if (normalizedProviderId.isEmpty ||
        normalizedThreadId.isEmpty ||
        turnId.isEmpty) {
      return Future<void>.value();
    }
    final key = '$normalizedProviderId\u0000$normalizedThreadId';
    final previous = _tails[key] ?? Future<void>.value();
    final operation = previous.then((_) async {
      try {
        final existing =
            await _store.load(
              providerId: normalizedProviderId,
              threadId: normalizedThreadId,
            ) ??
            AgentThreadTurnContext(
              providerId: normalizedProviderId,
              threadId: normalizedThreadId,
            );
        var next = existing.upsertTurn(
          AgentTurnContextRecord(
            turnId: turnId,
            modelId: incoming.modelId,
            reasoningEffort: incoming.reasoningEffort,
            serviceTierId: incoming.serviceTierId,
            explicitFast: incoming.explicitFast,
            startedAt: incoming.startedAt,
            completedAt: incoming.completedAt,
            status: incoming.status,
          ),
        );
        final merged = next.turnById(turnId);
        if (merged != null &&
            ((fillStartedAt && merged.startedAt == null) ||
                (fillCompletedAt && merged.completedAt == null))) {
          next = next.upsertTurn(
            AgentTurnContextRecord(
              turnId: turnId,
              startedAt: fillStartedAt && merged.startedAt == null
                  ? _now()
                  : null,
              completedAt: fillCompletedAt && merged.completedAt == null
                  ? _now()
                  : null,
            ),
          );
        }
        await _store.save(next);
      } catch (error) {
        _log.w('Could not persist Agent turn context (${error.runtimeType})');
      }
    });
    _tails[key] = operation.catchError((Object _) {});
    return operation;
  }

  /// 等待已入队的落盘完成，供测试使用。
  Future<void> flush() => Future.wait(_tails.values);
}
