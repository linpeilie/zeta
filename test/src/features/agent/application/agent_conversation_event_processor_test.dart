import 'package:flutter_test/flutter_test.dart';

import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('AgentConversationEventProcessor', () {
    test(
      'applies state, timeline, snapshot request, UI, then after-effects',
      () {
        // Arrange
        final order = <String>[];
        final timeline = _runningTimeline();
        addTearDown(timeline.dispose);
        final stateSink = _RecordingStateSink(order: order);
        final uiUpdates = _RecordingUiUpdatePort(order);
        final effectRunner = _RecordingEffectRunner(order);
        final processor = _processor(
          timeline: timeline,
          stateSink: stateSink,
          uiUpdates: uiUpdates,
          effectRunner: effectRunner,
        );

        // Act
        final mutation = processor.process(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );

        // Assert
        expect(mutation.accepted, isTrue);
        expect(order, <String>[
          'before-effect',
          'state',
          'snapshot',
          'after-effect',
          'after-effect',
          'after-effect',
          'ui',
        ]);
        expect(timeline.isTurnRunning, isFalse);
        expect(timeline.isHistoryTurnId('turn-1'), isTrue);
        expect(stateSink.snapshotRefreshRequests, 1);
        expect(uiUpdates.requests, hasLength(1));
        expect(mutation.uiUpdate!.regions, isEmpty);
        expect(
          uiUpdates.requests.single.regions,
          containsAll(<AgentUiRegion>[
            AgentUiRegion.history,
            AgentUiRegion.liveTurnBinding,
            AgentUiRegion.header,
            AgentUiRegion.composer,
            AgentUiRegion.pendingInteraction,
          ]),
        );
        expect(effectRunner.effects, hasLength(4));
        expect(
          effectRunner.effects.whereType<AgentTurnCompletedEffect>(),
          hasLength(1),
        );
      },
    );

    test('runs a rejected error logging effect before returning', () {
      // Arrange
      final order = <String>[];
      final timeline = AgentConversationTimelineStore();
      addTearDown(timeline.dispose);
      final stateSink = _RecordingStateSink(order: order);
      final uiUpdates = _RecordingUiUpdatePort(order);
      final effectRunner = _RecordingEffectRunner(order);
      final processor = _processor(
        timeline: timeline,
        stateSink: stateSink,
        uiUpdates: uiUpdates,
        effectRunner: effectRunner,
      );

      // Act
      final mutation = processor.process(
        const AgentErrorEvent(
          message: 'error from another thread',
          sessionId: 'thread-other',
          turnId: 'turn-other',
        ),
      );

      // Assert
      expect(mutation.accepted, isFalse);
      expect(mutation.rejectionReason, 'currentThreadMismatch');
      expect(order, <String>['before-effect']);
      expect(effectRunner.effects, hasLength(1));
      expect(effectRunner.effects.single, isA<AgentLogProviderErrorEffect>());
      expect(stateSink.applyCount, 0);
      expect(stateSink.snapshotRefreshRequests, 0);
      expect(uiUpdates.requests, isEmpty);
      expect(timeline.messages, isEmpty);
    });

    test('adds header region when a timeline mutation changes activity', () {
      // Arrange
      final timeline = _runningTimeline();
      addTearDown(timeline.dispose);
      final uiUpdates = _RecordingUiUpdatePort(<String>[]);
      final processor = _processor(
        timeline: timeline,
        stateSink: _RecordingStateSink(),
        uiUpdates: uiUpdates,
        effectRunner: _RecordingEffectRunner(<String>[]),
      );

      // Act
      final mutation = processor.process(
        const AgentMessageDeltaEvent(
          messageId: 'message-1',
          delta: 'Hello',
          role: AgentMessageRole.agent,
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );

      // Assert
      expect(mutation.accepted, isTrue);
      expect(mutation.uiUpdate!.regions, isEmpty);
      expect(uiUpdates.requests, hasLength(1));
      expect(
        uiUpdates.requests.single.regions,
        containsAll(<AgentUiRegion>[
          AgentUiRegion.liveTurn,
          AgentUiRegion.header,
        ]),
      );
    });

    test('records accepted live turn start and complete events', () {
      final timeline = _runningTimeline();
      addTearDown(timeline.dispose);
      final recorder = _RecordingTurnContextRecorder();
      final processor = _processor(
        timeline: timeline,
        stateSink: _RecordingStateSink(),
        uiUpdates: _RecordingUiUpdatePort(<String>[]),
        effectRunner: _RecordingEffectRunner(<String>[]),
        turnContextRecorder: recorder,
      );

      processor.process(
        const AgentTurnStartedEvent(
          AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
          modelId: 'gpt',
          reasoningEffort: 'high',
        ),
      );
      processor.process(
        const AgentTurnCompletedEvent(sessionId: 'thread-1', turnId: 'turn-1'),
      );

      expect(recorder.started, hasLength(1));
      expect(recorder.started.single.reasoningEffort, 'high');
      expect(recorder.completed, hasLength(1));
    });

    test('does not record rejected or history-scoped turn events', () {
      final timeline = AgentConversationTimelineStore();
      addTearDown(timeline.dispose);
      final recorder = _RecordingTurnContextRecorder();
      final liveProcessor = _processor(
        timeline: timeline,
        stateSink: _RecordingStateSink(),
        uiUpdates: _RecordingUiUpdatePort(<String>[]),
        effectRunner: _RecordingEffectRunner(<String>[]),
        turnContextRecorder: recorder,
      );
      liveProcessor.process(
        const AgentTurnCompletedEvent(
          sessionId: 'thread-other',
          turnId: 'turn-other',
        ),
      );

      final historyTimeline = AgentConversationTimelineStore();
      addTearDown(historyTimeline.dispose);
      final historyProcessor = AgentConversationEventProcessor(
        reducer: AgentConversationReducer.history(
          clock: () => DateTime.utc(2026, 7, 31),
        ),
        context: () => AgentConversationReducerContext(
          scope: AgentConversationReductionScope.history,
          selectedThreadId: 'thread-1',
          requiresResumedSelectedThread: false,
          pendingTurnGroupId: historyTimeline.pendingTurnGroupId,
          hasTurn: historyTimeline.hasTurn,
          isHistoryTurnId: historyTimeline.isHistoryTurnId,
          hasRunningTurnExcluding: (_) => false,
          modelsRefreshing: false,
          activeProviderName: 'Codex',
          activeProviderConfig: defaultCodexAgentProviderConfig,
          effectScope: const AgentConversationEffectScope(
            reductionScope: AgentConversationReductionScope.history,
            providerId: 'codex',
            listenerGeneration: 1,
            threadId: 'thread-1',
          ),
        ),
        timeline: historyTimeline,
        stateSink: _RecordingStateSink(),
        uiUpdates: _RecordingUiUpdatePort(<String>[]),
        effectRunner: _RecordingEffectRunner(<String>[]),
        observers: <AgentEventObserver>[AgentTurnContextObserver(recorder)],
      );
      historyProcessor.process(
        const AgentTurnStartedEvent(
          AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
          modelId: 'history-model',
        ),
      );

      expect(recorder.started, isEmpty);
      expect(recorder.completed, isEmpty);
    });

    test('keeps the mutation when the recorder throws', () {
      final timeline = _runningTimeline();
      addTearDown(timeline.dispose);
      final processor = _processor(
        timeline: timeline,
        stateSink: _RecordingStateSink(),
        uiUpdates: _RecordingUiUpdatePort(<String>[]),
        effectRunner: _RecordingEffectRunner(<String>[]),
        turnContextRecorder: _ThrowingTurnContextRecorder(),
      );

      final mutation = processor.process(
        const AgentTurnCompletedEvent(sessionId: 'thread-1', turnId: 'turn-1'),
      );

      expect(mutation.accepted, isTrue);
      expect(timeline.isTurnRunning, isFalse);
    });
  });
}

AgentConversationEventProcessor _processor({
  required AgentConversationTimelineStore timeline,
  required AgentConversationStateSink stateSink,
  required AgentUiUpdatePort uiUpdates,
  required AgentConversationEffectRunner effectRunner,
  AgentTurnContextRecorder? turnContextRecorder,
}) {
  return AgentConversationEventProcessor(
    reducer: AgentConversationReducer.live(
      clock: () => DateTime.utc(2026, 7, 31),
    ),
    context: () => _contextFor(timeline),
    timeline: timeline,
    stateSink: stateSink,
    uiUpdates: uiUpdates,
    effectRunner: effectRunner,
    observers: <AgentEventObserver>[
      if (turnContextRecorder != null)
        AgentTurnContextObserver(turnContextRecorder),
    ],
  );
}

AgentConversationReducerContext _contextFor(
  AgentConversationTimelineStore timeline,
) {
  return AgentConversationReducerContext(
    scope: AgentConversationReductionScope.live,
    selectedThreadId: 'thread-1',
    requiresResumedSelectedThread: false,
    pendingTurnGroupId: timeline.pendingTurnGroupId,
    hasTurn: timeline.hasTurn,
    isHistoryTurnId: timeline.isHistoryTurnId,
    hasRunningTurnExcluding: (turnId) {
      final running = timeline.selectedRunningTurnId;
      return running != null && running != turnId;
    },
    modelsRefreshing: false,
    activeProviderName: 'Codex',
    activeProviderConfig: defaultCodexAgentProviderConfig,
    effectScope: const AgentConversationEffectScope(
      reductionScope: AgentConversationReductionScope.live,
      providerId: 'codex',
      listenerGeneration: 7,
      runtimeId: 'runtime-1',
      connectionEpoch: 3,
      threadId: 'thread-1',
    ),
  );
}

AgentConversationTimelineStore _runningTimeline() {
  final timeline = AgentConversationTimelineStore();
  timeline.startPendingLiveTurn();
  timeline.beginLiveTurnGroup(
    const AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
  );
  timeline.takeDirtyRegions();
  return timeline;
}

final class _RecordingStateSink implements AgentConversationStateSink {
  _RecordingStateSink({List<String>? order}) : order = order ?? <String>[];

  final List<String> order;
  @override
  AgentConversationSessionState sessionState =
      const AgentConversationSessionState.initial(
        defaultTitle: agentDefaultThreadTitle,
      );
  int applyCount = 0;
  int snapshotRefreshRequests = 0;

  @override
  void applyReducedState(AgentConversationSessionState next) {
    sessionState = next;
    applyCount += 1;
    order.add('state');
  }

  @override
  void requestThreadSnapshotRefresh() {
    snapshotRefreshRequests += 1;
    order.add('snapshot');
  }
}

final class _RecordingUiUpdatePort implements AgentUiUpdatePort {
  _RecordingUiUpdatePort(this.order);

  final List<String> order;
  final List<AgentUiUpdateRequest> requests = <AgentUiUpdateRequest>[];

  @override
  void publish(AgentUiUpdateRequest request) {
    requests.add(request);
    order.add('ui');
  }
}

final class _RecordingEffectRunner implements AgentConversationEffectRunner {
  _RecordingEffectRunner(this.order);

  final List<String> order;
  final List<AgentConversationEffect> effects = <AgentConversationEffect>[];
  bool disposed = false;

  @override
  void run(AgentConversationEffect effect) {
    effects.add(effect);
    order.add(
      effect.timing == AgentConversationEffectTiming.beforeMutation
          ? 'before-effect'
          : 'after-effect',
    );
  }

  @override
  void dispose() {
    disposed = true;
  }
}

final class _RecordingTurnContextRecorder implements AgentTurnContextRecorder {
  final List<AgentTurnStartedEvent> started = <AgentTurnStartedEvent>[];
  final List<AgentTurnCompletedEvent> completed = <AgentTurnCompletedEvent>[];

  @override
  void recordStarted({
    required String providerId,
    required AgentTurnStartedEvent event,
  }) {
    started.add(event);
  }

  @override
  void recordCompleted({
    required String providerId,
    required AgentTurnCompletedEvent event,
  }) {
    completed.add(event);
  }
}

final class _ThrowingTurnContextRecorder implements AgentTurnContextRecorder {
  @override
  void recordStarted({
    required String providerId,
    required AgentTurnStartedEvent event,
  }) {
    throw StateError('recorder failed');
  }

  @override
  void recordCompleted({
    required String providerId,
    required AgentTurnCompletedEvent event,
  }) {
    throw StateError('recorder failed');
  }
}
