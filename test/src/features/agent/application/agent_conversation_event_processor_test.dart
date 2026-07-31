import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/application/agent_conversation_effect.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_effect_runner.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_event_processor.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_mutation.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_reducer.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_port.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentConversationEventProcessor', () {
    test(
      'applies pre-state, timeline, post-state, snapshot request, UI, then effect once',
      () {
        // Arrange
        final order = <String>[];
        final timeline = _runningTimeline();
        addTearDown(timeline.dispose);
        final stateTarget = _RecordingStateTarget(
          timeline: timeline,
          order: order,
          pendingInteractionOnTurnCompleted: true,
        );
        final uiUpdates = _RecordingUiUpdatePort(order);
        final effectRunner = _RecordingEffectRunner(order);
        final processor = _processor(
          timeline: timeline,
          stateTarget: stateTarget,
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
          'pre-state',
          'timeline',
          'post-state',
          'snapshot',
          'ui',
          'after-effect',
        ]);
        expect(timeline.isTurnRunning, isFalse);
        expect(timeline.isHistoryTurnId('turn-1'), isTrue);
        expect(stateTarget.snapshotRefreshRequests, 1);
        expect(uiUpdates.requests, hasLength(1));
        expect(
          mutation.uiUpdate!.regions,
          isNot(contains(AgentUiRegion.pendingInteraction)),
        );
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
        expect(effectRunner.effects, hasLength(1));
        expect(effectRunner.effects.single, isA<AgentTurnCompletedEffect>());
      },
    );

    test('runs a rejected error logging effect before returning', () {
      // Arrange
      final order = <String>[];
      final timeline = AgentConversationTimelineStore();
      addTearDown(timeline.dispose);
      final stateTarget = _RecordingStateTarget(
        timeline: timeline,
        order: order,
      );
      final uiUpdates = _RecordingUiUpdatePort(order);
      final effectRunner = _RecordingEffectRunner(order);
      final processor = _processor(
        timeline: timeline,
        stateTarget: stateTarget,
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
      expect(stateTarget.appliedChanges, isEmpty);
      expect(stateTarget.snapshotRefreshRequests, 0);
      expect(uiUpdates.requests, isEmpty);
      expect(timeline.messages, isEmpty);
    });

    test('adds header region when a timeline mutation changes activity', () {
      // Arrange
      final timeline = _runningTimeline();
      addTearDown(timeline.dispose);
      final stateTarget = _RecordingStateTarget(
        timeline: timeline,
        order: <String>[],
      );
      final uiUpdates = _RecordingUiUpdatePort(<String>[]);
      final processor = _processor(
        timeline: timeline,
        stateTarget: stateTarget,
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
      expect(mutation.uiUpdate!.regions, isNot(contains(AgentUiRegion.header)));
      expect(uiUpdates.requests, hasLength(1));
      expect(
        uiUpdates.requests.single.regions,
        containsAll(<AgentUiRegion>[
          AgentUiRegion.liveTurn,
          AgentUiRegion.header,
        ]),
      );
    });
  });
}

AgentConversationEventProcessor _processor({
  required AgentConversationTimelineStore timeline,
  required AgentConversationStateMutationTarget stateTarget,
  required AgentUiUpdatePort uiUpdates,
  required AgentConversationEffectRunner effectRunner,
}) {
  return AgentConversationEventProcessor(
    reducer: AgentConversationReducer.live(
      clock: () => DateTime.utc(2026, 7, 31),
    ),
    context: () => _contextFor(timeline),
    timeline: timeline,
    stateTarget: stateTarget,
    uiUpdates: uiUpdates,
    effectRunner: effectRunner,
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
    modelsRefreshing: false,
    activeProviderName: 'Codex',
    activeProviderConfig: AgentProviderConfig.defaultCodex,
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
  timeline.takeActivityDirty();
  return timeline;
}

final class _RecordingStateTarget
    implements AgentConversationStateMutationTarget {
  _RecordingStateTarget({
    required this.timeline,
    required this.order,
    this.pendingInteractionOnTurnCompleted = false,
  });

  final AgentConversationTimelineStore timeline;
  final List<String> order;
  final bool pendingInteractionOnTurnCompleted;
  final List<AgentConversationStateChange> appliedChanges =
      <AgentConversationStateChange>[];
  int snapshotRefreshRequests = 0;

  @override
  AgentConversationStateMutationOutcome apply(
    AgentConversationStateChange change,
  ) {
    appliedChanges.add(change);
    switch (change) {
      case AgentPrepareTurnCompletedChange():
        expect(timeline.isTurnRunning, isTrue);
        order.add('pre-state');
      case AgentFinalizeTurnCompletedChange():
        expect(timeline.isTurnRunning, isFalse);
        expect(timeline.isHistoryTurnId(change.event.turnId), isTrue);
        order
          ..add('timeline')
          ..add('post-state');
        return AgentConversationStateMutationOutcome(
          pendingInteractionChanged: pendingInteractionOnTurnCompleted,
        );
      default:
        order.add('state');
    }
    return AgentConversationStateMutationOutcome.none;
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
