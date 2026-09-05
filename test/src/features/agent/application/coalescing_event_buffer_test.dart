import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import '../../../testing/agent_file_change_canonical.dart';

void main() {
  group('CoalescingEventBuffer with AgentEventCoalescingPolicy', () {
    test('合并同 item 连续文本 delta', () async {
      final events = <AgentEvent>[];
      final buffer = _agentBuffer(onEvent: events.add);

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
      final buffer = _agentBuffer(onEvent: events.add);

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
      final buffer = _agentBuffer(onEvent: events.add);

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
      final buffer = _agentBuffer(onEvent: events.add);

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

    test('同 turn 的 token、上下文与文件快照只发布最新值', () async {
      final events = <AgentEvent>[];
      final buffer = _agentBuffer(onEvent: events.add);

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
          AgentTurnFileChangesEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            snapshot: _fileChangeSnapshot(revision: 1, patch: 'old diff'),
          ),
        )
        ..add(
          AgentTurnFileChangesEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            snapshot: _fileChangeSnapshot(revision: 2, patch: 'latest diff'),
          ),
        );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(3));
      expect((events[0] as AgentTokenUsageEvent).tokenUsage.totalTokens, 20);
      expect((events[1] as AgentContextWindowUsageEvent).usedTokens, 150);
      final fileChanges = events[2] as AgentTurnFileChangesEvent;
      expect(fileChanges.snapshot.revision, 2);
      expect(
        (fileChanges.snapshot.changes.single.evidence
                as AgentUnifiedPatchEvidence)
            .patch,
        'latest diff',
      );
    });

    test('turn 文件快照 latest-wins 且在完成屏障前发布', () {
      final events = <AgentEvent>[];
      final buffer = _agentBuffer(onEvent: events.add);

      buffer
        ..add(
          AgentTurnFileChangesEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            snapshot: _fileChangeSnapshot(revision: 1, patch: 'old diff'),
          ),
        )
        ..add(
          AgentTurnFileChangesEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            snapshot: _fileChangeSnapshot(revision: 2, patch: 'latest diff'),
          ),
        )
        ..add(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );

      expect(events, hasLength(2));
      expect(events.first, isA<AgentTurnFileChangesEvent>());
      expect(events.last, isA<AgentTurnCompletedEvent>());
      final envelopes = canonicalFileChangeEnvelopes(events);
      expect(envelopes, hasLength(1));
      expect(envelopes.single.ownerType, 'turn');
      expect(envelopes.single.snapshot.revision, 2);
      expect(envelopes.single.snapshotSignature, contains('latest diff'));
    });

    test('工具进度 latest-wins 时携带 next 的完整文件快照', () async {
      final events = <AgentEvent>[];
      final buffer = _agentBuffer(onEvent: events.add);

      buffer
        ..add(
          _toolEvent(
            status: AgentToolStatus.inProgress,
            content: 'editing',
            fileChanges: _fileChangeSnapshot(revision: 1, patch: 'old'),
          ),
        )
        ..add(
          _toolEvent(
            status: AgentToolStatus.inProgress,
            content: 'still editing',
            fileChanges: _fileChangeSnapshot(revision: 2, patch: 'latest'),
          ),
        );
      await Future<void>.delayed(Duration.zero);

      final toolCall = (events.single as AgentToolCallEvent).toolCall;
      expect(toolCall.content, 'editing\nstill editing');
      expect(toolCall.fileChanges?.revision, 2);
      expect(
        (toolCall.fileChanges!.changes.single.evidence
                as AgentUnifiedPatchEvidence)
            .patch,
        'latest',
      );
    });

    test('tool_use/detail latest-wins，终态屏障前后都保留完整证据', () {
      final events = <AgentEvent>[];
      final buffer = _agentBuffer(onEvent: events.add);
      final snapshot = _fileChangeSnapshot(revision: 2, patch: 'latest diff');

      buffer
        ..add(_toolEvent(status: AgentToolStatus.pending, content: 'tool_use'))
        ..add(
          _toolEvent(
            status: AgentToolStatus.inProgress,
            content: 'detail',
            fileChanges: snapshot,
          ),
        )
        ..add(
          _toolEvent(
            status: AgentToolStatus.completed,
            content: 'done',
            fileChanges: snapshot,
          ),
        );

      expect(events, hasLength(2));
      final progress = (events[0] as AgentToolCallEvent).toolCall;
      final completed = (events[1] as AgentToolCallEvent).toolCall;
      expect(progress.content, 'tool_use\ndetail');
      expect(progress.status, AgentToolStatus.inProgress);
      expect(completed.status, AgentToolStatus.completed);
      expect(completed.content, 'done');
      final envelopes = canonicalFileChangeEnvelopes(events);
      expect(envelopes.map((event) => event.status), <String>[
        'inProgress',
        'completed',
      ]);
      expect(
        envelopes.map((event) => event.snapshotSignature).toSet(),
        hasLength(1),
      );
    });

    test('item 完整快照前先 flush delta', () {
      final events = <AgentEvent>[];
      final buffer = _agentBuffer(onEvent: events.add);

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
      final buffer = _agentBuffer(onEvent: events.add);

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

    test('diagnostics 记录输入、合并、透传与 pending key 峰值', () {
      final events = <AgentEvent>[];
      final buffer = _agentBuffer(onEvent: events.add);

      buffer
        ..add(_messageDelta('one'))
        ..add(_messageDelta('two'))
        ..add(_messageDelta('three', messageId: 'message-2'));
      final pendingSnapshot = buffer.diagnostics;

      expect(pendingSnapshot.receivedEvents, 3);
      expect(pendingSnapshot.coalescedEvents, 1);
      expect(pendingSnapshot.barrierEvents, 0);
      expect(pendingSnapshot.directPassThroughEvents, 0);
      expect(pendingSnapshot.backpressureFlushes, 0);
      expect(pendingSnapshot.currentPendingKeys, 2);
      expect(pendingSnapshot.maxPendingKeys, 2);

      buffer.add(
        const AgentTurnCompletedEvent(sessionId: 'thread-1', turnId: 'turn-1'),
      );
      final deliveredSnapshot = buffer.diagnostics;

      expect(events, hasLength(3));
      expect(deliveredSnapshot.receivedEvents, 4);
      expect(deliveredSnapshot.coalescedEvents, 1);
      expect(deliveredSnapshot.barrierEvents, 1);
      expect(deliveredSnapshot.directPassThroughEvents, 0);
      expect(deliveredSnapshot.backpressureFlushes, 0);
      expect(deliveredSnapshot.currentPendingKeys, 0);
      expect(deliveredSnapshot.maxPendingKeys, 2);
      // 先前取得的对象是值快照，不随内部 Map 后续变化。
      expect(pendingSnapshot.currentPendingKeys, 2);
    });

    test('背压达到上限时仅上报计数并立即 flush', () {
      final events = <AgentEvent>[];
      final diagnostics = <int>[];
      final buffer = _agentBuffer(
        onEvent: events.add,
        maxPendingEvents: 2,
        onBackpressure: diagnostics.add,
      );

      buffer
        ..add(_messageDelta('one', messageId: 'message-1'))
        ..add(_messageDelta('two', messageId: 'message-2'));

      expect(diagnostics, <int>[2]);
      expect(events, hasLength(2));
      expect(buffer.diagnostics.receivedEvents, 2);
      expect(buffer.diagnostics.coalescedEvents, 0);
      expect(buffer.diagnostics.barrierEvents, 0);
      expect(buffer.diagnostics.directPassThroughEvents, 0);
      expect(buffer.diagnostics.backpressureFlushes, 1);
      expect(buffer.diagnostics.currentPendingKeys, 0);
      expect(buffer.diagnostics.maxPendingKeys, 2);
    });

    test('listener 失效时丢弃旧代数尚未发布的增量', () async {
      final events = <AgentEvent>[];
      final buffer = _agentBuffer(onEvent: events.add);

      buffer.add(_messageDelta('stale'));
      buffer.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    });
  });
}

CoalescingEventBuffer<AgentEvent, AgentEventKey> _agentBuffer({
  required void Function(AgentEvent event) onEvent,
  int maxPendingEvents = 512,
  void Function(int pendingEventCount)? onBackpressure,
}) {
  return CoalescingEventBuffer<AgentEvent, AgentEventKey>(
    policy: const AgentEventCoalescingPolicy(),
    onEmit: onEvent,
    maxPendingKeys: maxPendingEvents,
    onBackpressure: onBackpressure,
  );
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
  AgentFileChangeSnapshot? fileChanges,
}) {
  return AgentToolCallEvent(
    AgentToolCall(
      id: id,
      title: 'Command',
      status: status,
      content: content,
      sessionId: 'thread-1',
      turnId: 'turn-1',
      appendsProgress: true,
      fileChanges: fileChanges,
    ),
  );
}

AgentFileChangeSnapshot _fileChangeSnapshot({
  required int revision,
  required String patch,
}) {
  return AgentFileChangeSnapshot(
    revision: revision,
    replayability: AgentFileChangeReplayability.replayable,
    changes: <AgentFileChange>[
      AgentFileChange(
        id: 'change-1',
        path: 'lib/a.dart',
        kind: AgentFileChangeKind.modified,
        evidence: AgentUnifiedPatchEvidence(patch: patch),
      ),
    ],
  );
}
