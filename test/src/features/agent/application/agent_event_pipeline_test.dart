import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_reducer.dart';
import 'package:zeta/src/features/agent/application/agent_event_pipeline.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

import '../../../testing/agent_file_change_canonical.dart';
import '../../../testing/agent_event_storm_fixture.dart';

void main() {
  group('AgentEventPipeline', () {
    const runtime1 = AgentRuntimeScope(
      runtimeId: 'runtime-1',
      connectionEpoch: 1,
    );
    const runtime2 = AgentRuntimeScope(
      runtimeId: 'runtime-2',
      connectionEpoch: 2,
    );

    test('正常事件经过 merge 和 barrier 后保持顺序', () async {
      final source = StreamController<AgentEvent>(sync: true);
      final processed = <AgentEvent>[];
      final pipeline = _pipeline(
        source: source,
        currentRuntimeScope: () => runtime1,
        processed: processed,
      );

      source
        ..add(_delta('Hello'))
        ..add(_delta(' world'))
        ..add(_updated('complete'));
      await Future<void>.delayed(Duration.zero);

      expect(processed, hasLength(2));
      expect((processed.first as AgentMessageDeltaEvent).delta, 'Hello world');
      expect(processed.last, isA<AgentMessageUpdatedEvent>());
      expect(pipeline.diagnostics.receivedEvents, 3);
      expect(pipeline.diagnostics.acceptedEvents, 2);
      expect(pipeline.diagnostics.buffer.coalescedEvents, 1);
      expect(pipeline.diagnostics.buffer.barrierEvents, 1);

      await pipeline.close();
      await source.close();
    });

    test('turn 文件快照经 Pipeline latest-wins 且先于完成屏障', () async {
      final source = StreamController<AgentEvent>(sync: true);
      final processed = <AgentEvent>[];
      final pipeline = _pipeline(
        source: source,
        currentRuntimeScope: () => runtime1,
        processed: processed,
      );

      source
        ..add(_turnFileChanges(revision: 1, patch: 'old diff'))
        ..add(_turnFileChanges(revision: 2, patch: 'latest diff'))
        ..add(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
      await Future<void>.delayed(Duration.zero);

      expect(processed, hasLength(2));
      expect(processed.first, isA<AgentTurnFileChangesEvent>());
      expect(processed.last, isA<AgentTurnCompletedEvent>());
      final envelopes = canonicalFileChangeEnvelopes(processed);
      expect(envelopes, hasLength(1));
      expect(envelopes.single.snapshot.revision, 2);
      expect(envelopes.single.snapshotSignature, contains('latest diff'));

      await pipeline.close();
      await source.close();
    });

    test('Thread 切换丢弃旧 generation 的普通缓存', () async {
      final oldSource = StreamController<AgentEvent>(sync: true);
      final newSource = StreamController<AgentEvent>(sync: true);
      final oldProcessed = <AgentEvent>[];
      final newProcessed = <AgentEvent>[];
      final oldPipeline = _pipeline(
        source: oldSource,
        currentRuntimeScope: () => runtime1,
        processed: oldProcessed,
        threadId: 'thread-old',
      );

      oldSource.add(_delta('stale'));
      final newPipeline = _pipeline(
        source: newSource,
        currentRuntimeScope: () => runtime1,
        processed: newProcessed,
        threadId: 'thread-new',
        replaces: oldPipeline,
      );
      newSource.add(_updated('current'));
      await Future<void>.delayed(Duration.zero);

      expect(oldProcessed, isEmpty);
      expect(newProcessed, hasLength(1));
      expect(
        oldPipeline.diagnostics.closeReason,
        AgentEventPipelineCloseReason.replaced,
      );
      expect(newPipeline.currentListenerScope?.threadId, 'thread-new');

      await newPipeline.close();
      await oldSource.close();
      await newSource.close();
    });

    test('runtime epoch 变化会在 dispatch 前拒绝旧事件', () async {
      final source = StreamController<AgentEvent>(sync: true);
      final processed = <AgentEvent>[];
      var runtime = runtime1;
      final pipeline = _pipeline(
        source: source,
        currentRuntimeScope: () => runtime,
        processed: processed,
      );

      source.add(_updated('stale-runtime'));
      runtime = runtime2;
      await Future<void>.delayed(Duration.zero);

      expect(processed, isEmpty);
      expect(pipeline.diagnostics.rejectedStaleEvents, 1);

      await pipeline.close();
      await source.close();
    });

    test('detached runtime 只接受 reducer 现有 critical allowlist', () async {
      final source = StreamController<AgentEvent>(sync: true);
      final processed = <AgentEvent>[];
      AgentRuntimeScope? runtime = runtime1;
      final pipeline = _pipeline(
        source: source,
        currentRuntimeScope: () => runtime,
        processed: processed,
      );

      runtime = null;
      source
        ..add(
          const AgentStatusEvent(
            AgentProviderStatus(
              state: AgentProviderConnectionState.error,
              message: 'detached',
            ),
          ),
        )
        ..add(_updated('ordinary'));
      await Future<void>.delayed(Duration.zero);

      expect(processed, hasLength(1));
      expect(processed.single, isA<AgentStatusEvent>());
      expect(pipeline.diagnostics.rejectedStaleEvents, 1);

      await pipeline.close();
      await source.close();
    });

    test('旧 onDone 不释放或回调新 generation', () async {
      final oldSource = StreamController<AgentEvent>(sync: true);
      final newSource = StreamController<AgentEvent>(sync: true);
      var oldDoneCount = 0;
      var newDoneCount = 0;
      final processed = <AgentEvent>[];
      final oldPipeline = _pipeline(
        source: oldSource,
        currentRuntimeScope: () => runtime1,
        processed: <AgentEvent>[],
        onDone: () => oldDoneCount += 1,
      );
      final newPipeline = _pipeline(
        source: newSource,
        currentRuntimeScope: () => runtime1,
        processed: processed,
        replaces: oldPipeline,
        onDone: () => newDoneCount += 1,
      );

      await oldPipeline.done;
      await oldSource.close();
      newSource.add(_updated('new-generation'));
      await Future<void>.delayed(Duration.zero);

      expect(oldDoneCount, 0);
      expect(newDoneCount, 0);
      expect(newPipeline.currentListenerScope, isNotNull);
      expect(processed, hasLength(1));

      await newPipeline.close();
      await newSource.close();
    });

    test('自然 onDone 有界 drain，显式 close clear 且 dispose 后无回调', () async {
      final source = StreamController<AgentEvent>(sync: true);
      final processed = <AgentEvent>[];
      final scheduled = <void Function()>[];
      var doneCount = 0;
      final pipeline = _pipeline(
        source: source,
        currentRuntimeScope: () => runtime1,
        processed: processed,
        maxEventsPerTurn: 1,
        scheduleInitialDispatch: scheduled.add,
        scheduleContinuationDispatch: scheduled.add,
        onDone: () => doneCount += 1,
      );

      source
        ..add(_updated('first', messageId: 'message-1'))
        ..add(_updated('second', messageId: 'message-2'));
      await source.close();
      expect(processed, isEmpty);
      expect(pipeline.currentListenerScope, isNotNull);

      while (scheduled.isNotEmpty) {
        scheduled.removeAt(0)();
      }
      await pipeline.done;

      expect(
        processed.whereType<AgentMessageUpdatedEvent>().map(
          (event) => event.text,
        ),
        <String>['first', 'second'],
      );
      expect(doneCount, 1);
      expect(pipeline.currentListenerScope, isNull);
      expect(pipeline.diagnostics.dispatcher.yieldCount, 1);
      expect(
        pipeline.diagnostics.closeReason,
        AgentEventPipelineCloseReason.sourceDone,
      );

      final clearSource = StreamController<AgentEvent>(sync: true);
      final cleared = <AgentEvent>[];
      final clearPipeline = _pipeline(
        source: clearSource,
        currentRuntimeScope: () => runtime1,
        processed: cleared,
      );
      clearSource.add(_delta('clear-me'));
      await clearPipeline.close(
        reason: AgentEventPipelineCloseReason.threadSwitch,
      );
      await Future<void>.delayed(Duration.zero);
      clearSource.add(_updated('after-close'));

      expect(cleared, isEmpty);
      expect(
        clearPipeline.diagnostics.closeReason,
        AgentEventPipelineCloseReason.threadSwitch,
      );
      await clearSource.close();
    });

    test('固定事件风暴经 Pipeline 合并、让步且 critical 零丢失', () async {
      final fixture = AgentEventStormFixture();
      final source = StreamController<AgentEvent>(sync: true);
      final processed = <AgentEvent>[];
      final pipeline = _pipeline(
        source: source,
        currentRuntimeScope: () => runtime1,
        processed: processed,
      );

      for (final event in fixture.events) {
        source.add(event);
      }
      final sentinel = fixture.createEventQueueSentinel();
      final deliveredAtSentinelFuture = sentinel.schedule(
        readDeliveredCount: () =>
            pipeline.diagnostics.dispatcher.deliveredEvents,
      );
      unawaited(source.close());

      final deliveredAtSentinel = await deliveredAtSentinelFuture;
      await pipeline.done;
      final diagnostics = pipeline.diagnostics;

      expect(diagnostics.receivedEvents, fixture.expectedInputEventCount);
      expect(
        diagnostics.acceptedEvents,
        diagnostics.dispatcher.deliveredEvents,
      );
      expect(diagnostics.rejectedStaleEvents, 0);
      expect(diagnostics.buffer.coalescedEvents, 10516);
      expect(diagnostics.buffer.maxPendingKeys, 71);
      expect(diagnostics.dispatcher.deliveredEvents, 309);
      expect(diagnostics.dispatcher.batchCount, 5);
      expect(diagnostics.dispatcher.yieldCount, 4);
      expect(deliveredAtSentinel, 64);
      expect(
        processed.whereType<AgentPermissionRequestedEvent>(),
        hasLength(1),
      );
      expect(processed.whereType<AgentPermissionResolvedEvent>(), hasLength(1));
      expect(processed.whereType<AgentErrorEvent>(), hasLength(1));
      expect(processed.whereType<AgentTurnCompletedEvent>(), hasLength(1));
    });
  });
}

AgentEventPipeline _pipeline({
  required StreamController<AgentEvent> source,
  required AgentRuntimeScope? Function() currentRuntimeScope,
  required List<AgentEvent> processed,
  String threadId = 'thread-1',
  AgentEventPipeline? replaces,
  int maxEventsPerTurn = 64,
  void Function(void Function() callback)? scheduleInitialDispatch,
  void Function(void Function() callback)? scheduleContinuationDispatch,
  void Function()? onDone,
}) {
  return AgentEventPipeline(
    source: source.stream,
    providerId: 'provider-neutral',
    threadId: threadId,
    runtimeScope: currentRuntimeScope(),
    currentRuntimeScope: currentRuntimeScope,
    allowDetachedEvent: AgentConversationReducer.isCriticalDetachedEvent,
    processEvent: processed.add,
    onSourceError: (error, stackTrace) {},
    onDone: onDone ?? () {},
    replaces: replaces,
    maxEventsPerTurn: maxEventsPerTurn,
    scheduleInitialDispatch: scheduleInitialDispatch,
    scheduleContinuationDispatch: scheduleContinuationDispatch,
  );
}

AgentMessageDeltaEvent _delta(String delta) {
  return AgentMessageDeltaEvent(
    messageId: 'message-1',
    delta: delta,
    role: AgentMessageRole.agent,
    sessionId: 'thread-1',
    turnId: 'turn-1',
  );
}

AgentMessageUpdatedEvent _updated(
  String text, {
  String messageId = 'message-1',
}) {
  return AgentMessageUpdatedEvent(
    messageId: messageId,
    text: text,
    sessionId: 'thread-1',
    turnId: 'turn-1',
  );
}

AgentTurnFileChangesEvent _turnFileChanges({
  required int revision,
  required String patch,
}) {
  return AgentTurnFileChangesEvent(
    sessionId: 'thread-1',
    turnId: 'turn-1',
    snapshot: AgentFileChangeSnapshot(
      revision: revision,
      replayability: AgentFileChangeReplayability.liveOnly,
      changes: <AgentFileChange>[
        AgentFileChange(
          id: 'change-1',
          path: 'lib/a.dart',
          kind: AgentFileChangeKind.modified,
          evidence: AgentUnifiedPatchEvidence(patch: patch),
        ),
      ],
    ),
  );
}
