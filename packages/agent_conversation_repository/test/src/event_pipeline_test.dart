import 'dart:async';

import 'package:agent_conversation_repository/src/event_pipeline.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  test(
    'coalesces event storms and preserves barriers and FIFO turns',
    () async {
      final source = StreamController<AgentEvent>(sync: true);
      final delivered = <AgentEvent>[];
      final errors = <Object>[];
      final pipeline = ConversationEventPipeline(
        source: source.stream,
        isCurrent: () => true,
        onEvent: delivered.add,
        onError: (error, _) => errors.add(error),
        maxPendingKeys: 2,
        maxEventsPerTurn: 1,
      );

      source
        ..add(
          AgentMessageDeltaEvent(
            messageId: 'message',
            delta: 'a',
            role: AgentMessageRole.agent,
            turnId: 'turn',
          ),
        )
        ..add(
          AgentMessageDeltaEvent(
            messageId: 'message',
            delta: 'b',
            role: AgentMessageRole.agent,
            turnId: 'turn',
          ),
        )
        ..add(
          AgentReasoningDeltaEvent(
            itemId: 'reasoning',
            kind: AgentReasoningDeltaKind.text,
            delta: 'x',
            turnId: 'turn',
          ),
        )
        ..add(const AgentStatusEvent(AgentProviderStatus.idle()));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(delivered, hasLength(3));
      expect((delivered.first as AgentMessageDeltaEvent).delta, 'ab');
      expect(delivered.last, isA<AgentStatusEvent>());
      expect(errors, isEmpty);
      final diagnostics = pipeline.diagnostics;
      expect(diagnostics.receivedEvents, 4);
      expect(diagnostics.acceptedEvents, 3);
      expect(diagnostics.coalescedEvents, 1);
      expect(diagnostics.backpressureFlushes, 1);
      expect(diagnostics.maxQueueDepth, greaterThan(0));
      await pipeline.close();
      await pipeline.close();
      await source.close();
    },
  );

  test('merges snapshot kinds and append-only tool progress safely', () async {
    final source = StreamController<AgentEvent>(sync: true);
    final delivered = <AgentEvent>[];
    final pipeline = ConversationEventPipeline(
      source: source.stream,
      isCurrent: () => true,
      onEvent: delivered.add,
      onError: (_, _) {},
    );
    AgentToolCall progress(String? content, {bool append = true}) =>
        AgentToolCall(
          id: 'tool',
          title: 'Tool',
          status: AgentToolStatus.inProgress,
          content: content,
          turnId: 'turn',
          raw: <String, Object?>{'_progressAppend': append},
        );

    source
      ..add(
        AgentReasoningDeltaEvent(
          itemId: 'reasoning',
          kind: AgentReasoningDeltaKind.summaryText,
          delta: 'a',
          turnId: 'turn',
        ),
      )
      ..add(
        AgentReasoningDeltaEvent(
          itemId: 'reasoning',
          kind: AgentReasoningDeltaKind.summaryText,
          delta: 'b',
          sourceItemId: 'source',
          turnId: 'turn',
        ),
      )
      ..add(
        AgentTokenUsageEvent(
          tokenUsage: const AgentTokenUsage(totalTokens: 1),
          turnId: 'turn',
        ),
      )
      ..add(
        AgentTokenUsageEvent(
          tokenUsage: const AgentTokenUsage(totalTokens: 2),
          turnId: 'turn',
        ),
      )
      ..add(
        AgentContextWindowUsageEvent(usedTokens: 1, turnId: 'turn'),
      )
      ..add(
        AgentContextWindowUsageEvent(usedTokens: 2, turnId: 'turn'),
      )
      ..add(
        AgentTurnFileChangesEvent(
          sessionId: 'thread',
          turnId: 'turn',
          snapshot: AgentFileChangeSnapshot(
            revision: 1,
            replayability: AgentFileChangeReplayability.liveOnly,
            changes: const <AgentFileChange>[],
          ),
        ),
      )
      ..add(
        AgentTurnFileChangesEvent(
          sessionId: 'thread',
          turnId: 'turn',
          snapshot: AgentFileChangeSnapshot(
            revision: 2,
            replayability: AgentFileChangeReplayability.liveOnly,
            changes: const <AgentFileChange>[],
          ),
        ),
      )
      ..add(AgentToolCallEvent(progress('one')))
      ..add(AgentToolCallEvent(progress('two')));
    await Future<void>.delayed(Duration.zero);

    expect(delivered, hasLength(5));
    expect((delivered[0] as AgentReasoningDeltaEvent).delta, 'ab');
    expect(
      (delivered[1] as AgentTokenUsageEvent).tokenUsage.totalTokens,
      2,
    );
    expect((delivered[2] as AgentContextWindowUsageEvent).usedTokens, 2);
    expect(
      (delivered[3] as AgentTurnFileChangesEvent).snapshot.revision,
      2,
    );
    expect((delivered[4] as AgentToolCallEvent).toolCall.content, 'one\ntwo');

    source
      ..add(AgentToolCallEvent(progress(null)))
      ..add(AgentToolCallEvent(progress('two')))
      ..add(AgentToolCallEvent(progress('replace', append: false)));
    await Future<void>.delayed(Duration.zero);
    expect((delivered.last as AgentToolCallEvent).toolCall.content, 'replace');
    await source.close();
    await pipeline.close(drain: true);
  });

  test(
    'rejects stale source events and reports current source errors',
    () async {
      final source = StreamController<AgentEvent>(sync: true);
      var current = false;
      final delivered = <AgentEvent>[];
      final errors = <Object>[];
      final pipeline = ConversationEventPipeline(
        source: source.stream,
        isCurrent: () => current,
        onEvent: delivered.add,
        onError: (error, _) => errors.add(error),
      );
      source
        ..add(const AgentStatusEvent(AgentProviderStatus.idle()))
        ..addError(StateError('stale'));
      current = true;
      source
        ..add(const AgentStatusEvent(AgentProviderStatus.idle()))
        ..addError(StateError('current'));
      await Future<void>.delayed(Duration.zero);

      expect(delivered, hasLength(1));
      expect(errors, hasLength(1));
      expect(pipeline.diagnostics.rejectedStaleEvents, 1);
      await pipeline.close();
      source.add(const AgentStatusEvent(AgentProviderStatus.idle()));
      await source.close();
    },
  );

  test('source completion drains only a current generation', () async {
    for (final current in <bool>[true, false]) {
      final source = StreamController<AgentEvent>(sync: true);
      final delivered = <AgentEvent>[];
      var doneCalls = 0;
      final pipeline = ConversationEventPipeline(
        source: source.stream,
        isCurrent: () => current,
        onEvent: delivered.add,
        onError: (_, _) {},
        onDone: () => doneCalls += 1,
      );
      source.add(
        AgentMessageDeltaEvent(
          messageId: 'message',
          delta: 'value',
          role: AgentMessageRole.agent,
        ),
      );
      await source.close();
      await pipeline.close();
      expect(delivered.length, current ? 1 : 0);
      expect(doneCalls, current ? 1 : 0);
    }
  });

  test('queued events recheck generation before dispatch', () async {
    final source = StreamController<AgentEvent>(sync: true);
    var current = true;
    final delivered = <AgentEvent>[];
    final pipeline = ConversationEventPipeline(
      source: source.stream,
      isCurrent: () => current,
      onEvent: delivered.add,
      onError: (_, _) {},
    );
    source.add(
      AgentMessageDeltaEvent(
        messageId: 'message',
        delta: 'queued',
        role: AgentMessageRole.agent,
      ),
    );
    current = false;
    await Future<void>.delayed(Duration.zero);
    expect(delivered, isEmpty);
    expect(pipeline.diagnostics.rejectedStaleEvents, 1);
    await pipeline.close();
    await source.close();
  });

  test(
    'synchronous and asynchronous cancellation errors are contained',
    () async {
      final syncErrors = <Object>[];
      final syncPipeline = ConversationEventPipeline(
        source: _ThrowingCancelStream(),
        isCurrent: () => true,
        onEvent: (_) {},
        onError: (error, _) => syncErrors.add(error),
      );
      await syncPipeline.close();
      expect(syncErrors, hasLength(1));

      final asyncErrors = <Object>[];
      final source = StreamController<AgentEvent>(
        onCancel: () async => throw StateError('async cancel'),
      );
      final asyncPipeline = ConversationEventPipeline(
        source: source.stream,
        isCurrent: () => true,
        onEvent: (_) {},
        onError: (error, _) => asyncErrors.add(error),
      );
      await asyncPipeline.close();
      expect(asyncErrors, hasLength(1));
      await source.close();
    },
  );
}

final class _ThrowingCancelStream extends Stream<AgentEvent> {
  @override
  StreamSubscription<AgentEvent> listen(
    void Function(AgentEvent event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _ThrowingCancelSubscription();
}

final class _ThrowingCancelSubscription
    implements StreamSubscription<AgentEvent> {
  @override
  Future<void> cancel() => throw StateError('sync cancel');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
