import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_event_stream_buffer.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentEventStreamBuffer', () {
    test('合并同 item 连续文本 delta', () async {
      final events = <AgentEvent>[];
      final buffer = AgentEventStreamBuffer(onEvent: events.add);

      buffer
        ..add(
          _messageDelta(
            'Hello',
            sourceMessageId: 'source-message-1',
            kind: AgentMessageKind.plan,
            phase: AgentMessagePhase.commentary,
            status: AgentMessageStatus.streaming,
          ),
        )
        ..add(
          _messageDelta(
            ' world',
            sourceMessageId: 'source-message-1',
            kind: AgentMessageKind.plan,
            phase: AgentMessagePhase.commentary,
            status: AgentMessageStatus.completed,
          ),
        );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      final event = events.single as AgentMessageDeltaEvent;
      expect(event.delta, 'Hello world');
      expect(event.sourceMessageId, 'source-message-1');
      expect(event.kind, AgentMessageKind.plan);
      expect(event.phase, AgentMessagePhase.commentary);
      expect(event.status, AgentMessageStatus.completed);
    });

    test('does not coalesce the same entryId across message kinds', () async {
      final events = <AgentEvent>[];
      final buffer = AgentEventStreamBuffer(onEvent: events.add);

      buffer
        ..add(_messageDelta('regular'))
        ..add(_messageDelta('plan', kind: AgentMessageKind.plan));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(2));
      expect(
        events.whereType<AgentMessageDeltaEvent>().map((event) => event.kind),
        <AgentMessageKind>[AgentMessageKind.regular, AgentMessageKind.plan],
      );
    });

    test('keeps Message Tool Message order for different entryIds', () {
      final events = <AgentEvent>[];
      final buffer = AgentEventStreamBuffer(onEvent: events.add);

      buffer
        ..add(_messageDelta('before', messageId: 'message-seg1'))
        ..add(
          _toolEvent(
            id: 'tool-1',
            status: AgentToolStatus.pending,
            content: 'pending',
          ),
        )
        ..add(_messageDelta('after', messageId: 'message-seg2'))
        ..flush();

      expect(events, hasLength(3));
      expect((events[0] as AgentMessageDeltaEvent).messageId, 'message-seg1');
      expect((events[1] as AgentToolCallEvent).toolCall.id, 'tool-1');
      expect((events[2] as AgentMessageDeltaEvent).messageId, 'message-seg2');
    });

    test('reasoning merge preserves source item kind and index', () async {
      final events = <AgentEvent>[];
      final buffer = AgentEventStreamBuffer(onEvent: events.add);

      buffer
        ..add(
          const AgentReasoningDeltaEvent(
            itemId: 'reasoning-phase-1',
            sourceItemId: 'provider-reasoning-1',
            kind: AgentReasoningDeltaKind.summaryText,
            delta: 'summary ',
            summaryIndex: 2,
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        )
        ..add(
          const AgentReasoningDeltaEvent(
            itemId: 'reasoning-phase-1',
            sourceItemId: 'provider-reasoning-1',
            kind: AgentReasoningDeltaKind.summaryText,
            delta: 'continued',
            summaryIndex: 2,
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
      await Future<void>.delayed(Duration.zero);

      final event = events.single as AgentReasoningDeltaEvent;
      expect(event.delta, 'summary continued');
      expect(event.sourceItemId, 'provider-reasoning-1');
      expect(event.kind, AgentReasoningDeltaKind.summaryText);
      expect(event.summaryIndex, 2);
    });

    test('同 turn 的 token、上下文与 diff 快照只发布最新值', () async {
      final events = <AgentEvent>[];
      final buffer = AgentEventStreamBuffer(onEvent: events.add);

      buffer
        ..add(
          const AgentTokenUsageEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            tokenUsage: AgentTokenUsage(totalTokens: 10),
          ),
        )
        ..add(
          const AgentTokenUsageEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            tokenUsage: AgentTokenUsage(totalTokens: 20),
          ),
        )
        ..add(
          const AgentContextWindowUsageEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            usedTokens: 100,
          ),
        )
        ..add(
          const AgentContextWindowUsageEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            usedTokens: 150,
          ),
        )
        ..add(
          const AgentTurnDiffEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            diff: 'old diff',
          ),
        )
        ..add(
          const AgentTurnDiffEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            diff: 'latest diff',
          ),
        );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(3));
      expect((events[0] as AgentTokenUsageEvent).tokenUsage.totalTokens, 20);
      expect((events[1] as AgentContextWindowUsageEvent).usedTokens, 150);
      expect((events[2] as AgentTurnDiffEvent).diff, 'latest diff');
    });

    test('工具进度可追加合并，终态会先 flush 进度且自身不丢失', () {
      final events = <AgentEvent>[];
      final buffer = AgentEventStreamBuffer(onEvent: events.add);

      buffer
        ..add(_toolEvent(status: AgentToolStatus.inProgress, content: 'line 1'))
        ..add(_toolEvent(status: AgentToolStatus.inProgress, content: 'line 2'))
        ..add(_toolEvent(status: AgentToolStatus.completed, content: 'done'));

      expect(events, hasLength(2));
      final progress = (events[0] as AgentToolCallEvent).toolCall;
      final completed = (events[1] as AgentToolCallEvent).toolCall;
      expect(progress.content, 'line 1\nline 2');
      expect(progress.status, AgentToolStatus.inProgress);
      expect(completed.status, AgentToolStatus.completed);
      expect(completed.content, 'done');
    });

    test('item 完整快照前先 flush delta', () {
      final events = <AgentEvent>[];
      final buffer = AgentEventStreamBuffer(onEvent: events.add);

      buffer
        ..add(_messageDelta('partial'))
        ..add(
          const AgentMessageUpdatedEvent(
            messageId: 'message-1',
            text: 'complete',
            status: AgentMessageStatus.completed,
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );

      expect(events, hasLength(2));
      expect(events[0], isA<AgentMessageDeltaEvent>());
      expect(events[1], isA<AgentMessageUpdatedEvent>());
    });

    test('turn 终态、审批、错误与连接状态按序立即发布', () {
      final events = <AgentEvent>[];
      final buffer = AgentEventStreamBuffer(onEvent: events.add);

      buffer
        ..add(_messageDelta('before terminal'))
        ..add(
          const AgentPermissionRequestedEvent(
            AgentPermissionRequest(
              id: 'approval-1',
              title: 'Run command',
              kind: AgentPermissionKind.commandExecution,
              sessionId: 'thread-1',
              turnId: 'turn-1',
            ),
          ),
        )
        ..add(
          const AgentPermissionResolvedEvent(
            requestId: 'approval-1',
            threadId: 'thread-1',
          ),
        )
        ..add(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        )
        ..add(const AgentErrorEvent(message: 'failed'))
        ..add(
          const AgentStatusEvent(
            AgentProviderStatus(
              state: AgentProviderConnectionState.error,
              message: 'disconnected',
            ),
          ),
        );

      expect(events, hasLength(6));
      expect(events[0], isA<AgentMessageDeltaEvent>());
      expect(events[1], isA<AgentPermissionRequestedEvent>());
      expect(events[2], isA<AgentPermissionResolvedEvent>());
      expect(events[3], isA<AgentTurnCompletedEvent>());
      expect(events[4], isA<AgentErrorEvent>());
      expect(events[5], isA<AgentStatusEvent>());
    });

    test('背压达到上限时仅上报计数并立即 flush', () {
      final events = <AgentEvent>[];
      final diagnostics = <int>[];
      final buffer = AgentEventStreamBuffer(
        onEvent: events.add,
        maxPendingEvents: 2,
        onBackpressure: diagnostics.add,
      );

      buffer
        ..add(_messageDelta('one', messageId: 'message-1'))
        ..add(_messageDelta('two', messageId: 'message-2'));

      expect(diagnostics, <int>[2]);
      expect(events, hasLength(2));
    });

    test('listener 失效时丢弃旧代数尚未发布的增量', () async {
      final events = <AgentEvent>[];
      final buffer = AgentEventStreamBuffer(onEvent: events.add);

      buffer.add(_messageDelta('stale'));
      buffer.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    });
  });
}

AgentMessageDeltaEvent _messageDelta(
  String delta, {
  String messageId = 'message-1',
  String? sourceMessageId,
  AgentMessageKind kind = AgentMessageKind.regular,
  AgentMessagePhase? phase,
  AgentMessageStatus? status,
}) {
  return AgentMessageDeltaEvent(
    messageId: messageId,
    sourceMessageId: sourceMessageId,
    kind: kind,
    delta: delta,
    role: AgentMessageRole.agent,
    phase: phase,
    status: status,
    sessionId: 'thread-1',
    turnId: 'turn-1',
  );
}

AgentToolCallEvent _toolEvent({
  String id = 'tool-1',
  required AgentToolStatus status,
  required String content,
}) {
  return AgentToolCallEvent(
    AgentToolCall(
      id: id,
      title: 'Command',
      status: status,
      content: content,
      sessionId: 'thread-1',
      turnId: 'turn-1',
      raw: const <String, Object?>{'_progressAppend': true},
    ),
  );
}
