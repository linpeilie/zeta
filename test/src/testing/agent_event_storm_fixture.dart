import 'dart:async';

import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 阶段 0 使用的固定 AgentEvent 风暴。
///
/// 所有正文都是单字符或固定测试标签，且所有 raw payload 均为空，避免夹具意外
/// 携带用户数据。默认规模对应：
///
/// - 6,000 条 message delta；
/// - 4,000 条 reasoning delta；
/// - 500 条交错 tool progress；
/// - token/context/diff 各 100 个快照；
/// - permission requested/resolved、error、tool terminal 与 turn completed 屏障。
final class AgentEventStormFixture {
  AgentEventStormFixture({
    this.sessionId = 'storm-thread',
    this.turnId = 'storm-turn',
  });

  static const int messageDeltaCount = 6000;
  static const int reasoningDeltaCount = 4000;
  static const int toolProgressCount = 500;
  static const int snapshotCountPerKind = 100;
  static const int messageSegmentCount = 32;
  static const int reasoningItemCount = 16;
  static const int toolCount = 20;

  static const String permissionRequestId = 'storm-permission';
  static const String errorMessage = 'storm-fixture-error';

  final String sessionId;
  final String turnId;

  late final List<AgentEvent> events = List<AgentEvent>.unmodifiable(
    _buildEvents(),
  );

  int get expectedInputEventCount =>
      1 + // turn started
      messageDeltaCount +
      reasoningDeltaCount +
      toolProgressCount +
      (snapshotCountPerKind * 3) +
      1 + // permission requested
      1 + // permission resolved
      1 + // error
      toolCount + // terminal tool events
      1; // turn completed

  int get expectedMessageCharacters => messageDeltaCount;

  int get expectedReasoningCharacters => reasoningDeltaCount;

  /// 创建一个独立 sentinel；每次 fresh run 都应使用新实例。
  DartEventQueueSentinel createEventQueueSentinel() {
    return DartEventQueueSentinel();
  }

  List<AgentEvent> _buildEvents() {
    final result = <AgentEvent>[
      AgentTurnStartedEvent(AgentTurn(id: turnId, sessionId: sessionId)),
    ];
    var toolProgressIndex = 0;
    var snapshotIndex = 0;

    for (var index = 0; index < 10000; index += 1) {
      if (index % 5 < 3) {
        result.add(
          AgentMessageDeltaEvent(
            messageId: 'storm-message-${index % messageSegmentCount}',
            delta: 'm',
            role: AgentMessageRole.agent,
            phase: AgentMessagePhase.response,
            sessionId: sessionId,
            turnId: turnId,
          ),
        );
      } else {
        result.add(
          AgentReasoningDeltaEvent(
            itemId: 'storm-reasoning-${index % reasoningItemCount}',
            kind: AgentReasoningDeltaKind.text,
            delta: 'r',
            contentIndex: 0,
            sessionId: sessionId,
            turnId: turnId,
          ),
        );
      }

      if (index % 20 == 0) {
        final toolId = toolProgressIndex % toolCount;
        result.add(
          AgentToolCallEvent(
            AgentToolCall(
              id: 'storm-tool-$toolId',
              title: 'Fixture tool $toolId',
              kind: AgentToolKind.execute,
              status: AgentToolStatus.inProgress,
              content: 'progress',
              sessionId: sessionId,
              turnId: turnId,
            ),
          ),
        );
        toolProgressIndex += 1;
      }

      if (index % 100 == 0) {
        final tokenValue = snapshotIndex + 1;
        result
          ..add(
            AgentTokenUsageEvent(
              sessionId: sessionId,
              turnId: turnId,
              tokenUsage: AgentTokenUsage(
                inputTokens: tokenValue,
                outputTokens: tokenValue,
                totalTokens: tokenValue * 2,
                lastInputTokens: tokenValue,
                lastOutputTokens: tokenValue,
                lastTotalTokens: tokenValue * 2,
              ),
            ),
          )
          ..add(
            AgentContextWindowUsageEvent(
              usedTokens: tokenValue,
              modelContextWindow: 100000,
              sessionId: sessionId,
              turnId: turnId,
            ),
          )
          ..add(
            AgentTurnFileChangesEvent(
              sessionId: sessionId,
              turnId: turnId,
              snapshot: AgentFileChangeSnapshot(
                revision: snapshotIndex + 1,
                replayability: AgentFileChangeReplayability.liveOnly,
                changes: <AgentFileChange>[
                  AgentFileChange(
                    id: 'fixture-change',
                    path: 'fixture.txt',
                    kind: AgentFileChangeKind.modified,
                    evidence: AgentUnifiedPatchEvidence(
                      patch: 'fixture-diff-$snapshotIndex',
                    ),
                  ),
                ],
              ),
            ),
          );
        snapshotIndex += 1;
      }

      switch (index) {
        case 2499:
          result.add(
            AgentPermissionRequestedEvent(
              AgentPermissionRequest(
                id: permissionRequestId,
                title: 'Fixture approval',
                kind: AgentPermissionKind.commandExecution,
                command: 'fixture-command',
                sessionId: sessionId,
                turnId: turnId,
              ),
            ),
          );
        case 4999:
          result.add(
            AgentPermissionResolvedEvent(
              requestId: permissionRequestId,
              threadId: sessionId,
            ),
          );
        case 7499:
          result.add(
            AgentErrorEvent(
              message: errorMessage,
              sessionId: sessionId,
              turnId: turnId,
            ),
          );
      }
    }

    for (var index = 0; index < toolCount; index += 1) {
      result.add(
        AgentToolCallEvent(
          AgentToolCall(
            id: 'storm-tool-$index',
            title: 'Fixture tool $index',
            kind: AgentToolKind.execute,
            status: AgentToolStatus.completed,
            content: 'done',
            sessionId: sessionId,
            turnId: turnId,
          ),
        ),
      );
    }
    result.add(AgentTurnCompletedEvent(sessionId: sessionId, turnId: turnId));

    assert(toolProgressIndex == toolProgressCount);
    assert(snapshotIndex == snapshotCountPerKind);
    assert(result.length == expectedInputEventCount);
    return result;
  }
}

/// 插入 Dart event queue 的一次性哨兵。
///
/// 哨兵只采样调用方提供的整数计数，不读取或保留任何事件内容。
final class DartEventQueueSentinel {
  final Completer<int> _completer = Completer<int>();
  bool _scheduled = false;

  bool get hasRun => _completer.isCompleted;

  Future<int> schedule({required int Function() readDeliveredCount}) {
    if (_scheduled) {
      throw StateError('The event queue sentinel can only be scheduled once.');
    }
    _scheduled = true;
    Timer.run(() {
      _completer.complete(readDeliveredCount());
    });
    return _completer.future;
  }
}
