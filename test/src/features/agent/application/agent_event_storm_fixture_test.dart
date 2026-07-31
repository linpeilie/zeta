import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_effect.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_effect_runner.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_event_processor.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_mutation.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_reducer.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_port.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';
import 'package:zeta/src/features/agent/application/agent_event_coalescing_policy.dart';
import 'package:zeta/src/features/agent/application/bounded_event_dispatcher.dart';
import 'package:zeta/src/features/agent/application/coalescing_event_buffer.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

import '../../../testing/agent_event_storm_fixture.dart';

void main() {
  test('fixed storm is deterministic and yields to Dart event queue', () async {
    final first = await _runStorm();
    final second = await _runStorm();

    debugPrint('agent-event-storm-baseline $first');
    expect(first, second);
    expect(first.receivedEvents, first.fixtureInputEvents);
    expect(first.deliveredAtSentinel, greaterThan(0));
    expect(first.deliveredAtSentinel, lessThan(first.deliveredEvents));
    expect(first.messageCharacters, AgentEventStormFixture.messageDeltaCount);
    expect(
      first.reasoningCharacters,
      AgentEventStormFixture.reasoningDeltaCount,
    );
    expect(first.permissionRequestedCount, 1);
    expect(first.permissionResolvedCount, 1);
    expect(first.errorCount, 1);
    expect(first.turnCompletedCount, 1);
    expect(first.terminalToolCount, AgentEventStormFixture.toolCount);
    expect(
      first.lastTokenTotal,
      AgentEventStormFixture.snapshotCountPerKind * 2,
    );
    expect(first.lastContextUsed, AgentEventStormFixture.snapshotCountPerKind);
    expect(
      first.lastDiff,
      'fixture-diff-${AgentEventStormFixture.snapshotCountPerKind - 1}',
    );
    expect(first.lastEventType, 'AgentTurnCompletedEvent');
    expect(first.currentPendingKeys, 0);
    expect(first.currentQueueDepth, 0);
  });

  test(
    'stage 4 processor preserves storm timeline, critical barriers, and effects',
    () async {
      final first = await _runProcessedStorm();
      final second = await _runProcessedStorm();
      addTearDown(first.timeline.dispose);
      addTearDown(second.timeline.dispose);
      final timeline = first.timeline;
      final historyTurn = timeline.visibleHistoryTurns.single;
      final stormMessages = timeline.messages
          .where((message) => message.id.startsWith('storm-message-'))
          .toList(growable: false);
      final reasoningTools = timeline.toolCalls
          .where(
            (tool) =>
                tool.kind == AgentToolKind.think &&
                tool.id.startsWith('storm-reasoning-'),
          )
          .toList(growable: false);
      final executeTools = timeline.toolCalls
          .where((tool) => tool.id.startsWith('storm-tool-'))
          .toList(growable: false);
      final timelineIds = timeline.timelineEntries
          .map((entry) => entry.id)
          .toList(growable: false);
      final secondTimelineIds = second.timeline.timelineEntries
          .map((entry) => entry.id)
          .toList(growable: false);

      expect(first.delivery, second.delivery);
      expect(timelineIds, orderedEquals(secondTimelineIds));
      expect(
        historyTurn.entries.map((entry) => entry.id),
        orderedEquals(
          second.timeline.visibleHistoryTurns.single.entries.map(
            (entry) => entry.id,
          ),
        ),
      );
      expect(first.acceptedEvents, first.delivery.deliveredEvents);
      expect(first.rejectedEvents, 0);
      expect(first.uiUpdates.publishedCount, first.delivery.deliveredEvents);

      final expectedTimelineEntries =
          AgentEventStormFixture.messageSegmentCount +
          AgentEventStormFixture.reasoningItemCount +
          AgentEventStormFixture.toolCount +
          1 + // latest turn diff
          1; // normalized provider error
      expect(timeline.timelineEntries, hasLength(expectedTimelineEntries));
      expect(timelineIds.toSet(), hasLength(timelineIds.length));
      expect(timeline.conversationTurns.map((turn) => turn.id), const <String>[
        'storm-turn',
      ]);
      expect(timeline.liveTurnState, isNull);
      expect(timeline.isTurnRunning, isFalse);
      expect(historyTurn.id, 'storm-turn');
      expect(historyTurn.status, AgentHistoryTurnStatus.completed);
      expect(historyTurn.entries, hasLength(expectedTimelineEntries));

      expect(
        stormMessages,
        hasLength(AgentEventStormFixture.messageSegmentCount),
      );
      expect(
        stormMessages.fold<int>(0, (sum, message) => sum + message.text.length),
        first.delivery.messageCharacters,
      );
      expect(
        reasoningTools,
        hasLength(AgentEventStormFixture.reasoningItemCount),
      );
      expect(
        reasoningTools.fold<int>(
          0,
          (sum, tool) => sum + (tool.content?.length ?? 0),
        ),
        first.delivery.reasoningCharacters,
      );
      expect(executeTools, hasLength(first.delivery.terminalToolCount));
      expect(
        executeTools.every((tool) => tool.status == AgentToolStatus.completed),
        isTrue,
      );
      expect(timeline.permissionRequests, isEmpty);
      expect(
        timeline.messages
            .where(
              (message) => message.text == AgentEventStormFixture.errorMessage,
            )
            .length,
        first.delivery.errorCount,
      );
      expect(
        (historyTurn.entries.last as AgentMessageTimelineEntry).message.text,
        AgentEventStormFixture.errorMessage,
      );
      expect(
        timeline.timelineEntries
            .whereType<AgentTurnDiffTimelineEntry>()
            .single
            .diff,
        first.delivery.lastDiff,
      );
      expect(
        historyTurn.tokenUsage?.totalTokens,
        first.delivery.lastTokenTotal,
      );
      expect(
        timeline.currentThreadTokenUsage?.totalTokens,
        first.delivery.lastTokenTotal,
      );

      expect(first.criticalEventTypes, const <Type>[
        AgentPermissionRequestedEvent,
        AgentPermissionResolvedEvent,
        AgentErrorEvent,
        AgentTurnCompletedEvent,
      ]);
      expect(
        first.criticalEventTypes
            .where((type) => type == AgentPermissionRequestedEvent)
            .length,
        first.delivery.permissionRequestedCount,
      );
      expect(
        first.criticalEventTypes
            .where((type) => type == AgentPermissionResolvedEvent)
            .length,
        first.delivery.permissionResolvedCount,
      );
      expect(
        first.criticalEventTypes
            .where((type) => type == AgentErrorEvent)
            .length,
        first.delivery.errorCount,
      );
      expect(
        first.criticalEventTypes
            .where((type) => type == AgentTurnCompletedEvent)
            .length,
        first.delivery.turnCompletedCount,
      );
      expect(
        first.effects.turnCompletedCount,
        first.delivery.turnCompletedCount,
      );
      expect(first.effects.providerErrorCount, first.delivery.errorCount);
      expect(first.effects.effectTypes, const <Type>[
        AgentLogProviderErrorEffect,
        AgentTurnCompletedEffect,
      ]);

      expect(
        first.stateTarget.appliedChanges
            .whereType<AgentFinalizeTurnStartedChange>(),
        hasLength(1),
      );
      expect(
        first.stateTarget.appliedChanges
            .whereType<AgentPrepareTurnCompletedChange>(),
        hasLength(first.delivery.turnCompletedCount),
      );
      expect(
        first.stateTarget.appliedChanges
            .whereType<AgentFinalizeTurnCompletedChange>(),
        hasLength(first.delivery.turnCompletedCount),
      );
      expect(first.stateTarget.snapshotRefreshRunningStates, const <bool>[
        true,
        false,
      ]);
    },
  );
}

Future<_StormBaselineSnapshot> _runStorm({
  AgentEventStormFixture? fixture,
  void Function(AgentEvent event)? onDelivered,
}) async {
  final resolvedFixture = fixture ?? AgentEventStormFixture();
  final delivered = <AgentEvent>[];
  late final BoundedEventDispatcher<AgentEvent> scheduler;
  scheduler = BoundedEventDispatcher<AgentEvent>(
    onEvent: (event) {
      delivered.add(event);
      onDelivered?.call(event);
    },
    maxEventsPerTurn: 64,
  );
  final buffer = CoalescingEventBuffer<AgentEvent, AgentEventKey>(
    policy: const AgentEventCoalescingPolicy(),
    onEmit: scheduler.add,
  );

  for (final event in resolvedFixture.events) {
    buffer.add(event);
  }
  buffer.flush();

  final sentinel = resolvedFixture.createEventQueueSentinel();
  final deliveredAtSentinel = await sentinel.schedule(
    readDeliveredCount: () => scheduler.diagnostics.deliveredEvents,
  );
  while (scheduler.diagnostics.currentQueueDepth > 0) {
    await Future<void>.delayed(Duration.zero);
  }

  final bufferDiagnostics = buffer.diagnostics;
  final schedulerDiagnostics = scheduler.diagnostics;
  final snapshot = _StormBaselineSnapshot(
    fixtureInputEvents: resolvedFixture.expectedInputEventCount,
    receivedEvents: bufferDiagnostics.receivedEvents,
    coalescedEvents: bufferDiagnostics.coalescedEvents,
    barrierOrDirectPassThroughEvents:
        bufferDiagnostics.barrierEvents +
        bufferDiagnostics.directPassThroughEvents,
    backpressureFlushes: bufferDiagnostics.backpressureFlushes,
    currentPendingKeys: bufferDiagnostics.currentPendingKeys,
    maxPendingKeys: bufferDiagnostics.maxPendingKeys,
    deliveredEvents: schedulerDiagnostics.deliveredEvents,
    batchCount: schedulerDiagnostics.batchCount,
    yieldCount: schedulerDiagnostics.yieldCount,
    currentQueueDepth: schedulerDiagnostics.currentQueueDepth,
    maxQueueDepth: schedulerDiagnostics.maxQueueDepth,
    deliveredAtSentinel: deliveredAtSentinel,
    messageCharacters: delivered.whereType<AgentMessageDeltaEvent>().fold<int>(
      0,
      (sum, event) => sum + event.delta.length,
    ),
    reasoningCharacters: delivered
        .whereType<AgentReasoningDeltaEvent>()
        .fold<int>(0, (sum, event) => sum + event.delta.length),
    permissionRequestedCount: delivered
        .whereType<AgentPermissionRequestedEvent>()
        .length,
    permissionResolvedCount: delivered
        .whereType<AgentPermissionResolvedEvent>()
        .length,
    errorCount: delivered.whereType<AgentErrorEvent>().length,
    turnCompletedCount: delivered.whereType<AgentTurnCompletedEvent>().length,
    terminalToolCount: delivered
        .whereType<AgentToolCallEvent>()
        .where((event) => event.toolCall.isTerminalStatus)
        .length,
    lastTokenTotal: delivered
        .whereType<AgentTokenUsageEvent>()
        .last
        .tokenUsage
        .totalTokens!,
    lastContextUsed: delivered
        .whereType<AgentContextWindowUsageEvent>()
        .last
        .usedTokens,
    lastDiff: delivered.whereType<AgentTurnDiffEvent>().last.diff,
    lastEventType: delivered.last.runtimeType.toString(),
  );

  buffer.dispose();
  await scheduler.close(drain: false);
  return snapshot;
}

Future<_ProcessedStormRun> _runProcessedStorm() async {
  final fixture = AgentEventStormFixture();
  final timeline = AgentConversationTimelineStore();
  final stateTarget = _StormStateTarget(timeline: timeline);
  final uiUpdates = _CountingUiUpdatePort();
  final effects = _CountingEffectRunner();
  final criticalEventTypes = <Type>[];
  var acceptedEvents = 0;
  var rejectedEvents = 0;
  final reducer = AgentConversationReducer.live(
    clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
  );
  final processor = AgentConversationEventProcessor(
    reducer: reducer,
    context: () => AgentConversationReducerContext(
      scope: AgentConversationReductionScope.live,
      selectedThreadId: fixture.sessionId,
      requiresResumedSelectedThread: false,
      pendingTurnGroupId: timeline.pendingTurnGroupId,
      hasTurn: timeline.hasTurn,
      isHistoryTurnId: timeline.isHistoryTurnId,
      modelsRefreshing: false,
      activeProviderName: 'Codex',
      activeProviderConfig: AgentProviderConfig.defaultCodex,
      effectScope: AgentConversationEffectScope(
        reductionScope: AgentConversationReductionScope.live,
        providerId: defaultAgentProviderId,
        listenerGeneration: 7,
        runtimeId: 'storm-runtime',
        connectionEpoch: 1,
        providerLifecycleState: 'ready',
        threadId: fixture.sessionId,
      ),
    ),
    timeline: timeline,
    stateTarget: stateTarget,
    uiUpdates: uiUpdates,
    effectRunner: effects,
  );

  final delivery = await _runStorm(
    fixture: fixture,
    onDelivered: (event) {
      final mutation = processor.process(event);
      if (mutation.accepted) {
        acceptedEvents += 1;
      } else {
        rejectedEvents += 1;
      }
      if (AgentConversationReducer.isCriticalDetachedEvent(event)) {
        criticalEventTypes.add(event.runtimeType);
      }
    },
  );
  effects.dispose();

  return _ProcessedStormRun(
    delivery: delivery,
    timeline: timeline,
    stateTarget: stateTarget,
    uiUpdates: uiUpdates,
    effects: effects,
    criticalEventTypes: List<Type>.unmodifiable(criticalEventTypes),
    acceptedEvents: acceptedEvents,
    rejectedEvents: rejectedEvents,
  );
}

final class _ProcessedStormRun {
  const _ProcessedStormRun({
    required this.delivery,
    required this.timeline,
    required this.stateTarget,
    required this.uiUpdates,
    required this.effects,
    required this.criticalEventTypes,
    required this.acceptedEvents,
    required this.rejectedEvents,
  });

  final _StormBaselineSnapshot delivery;
  final AgentConversationTimelineStore timeline;
  final _StormStateTarget stateTarget;
  final _CountingUiUpdatePort uiUpdates;
  final _CountingEffectRunner effects;
  final List<Type> criticalEventTypes;
  final int acceptedEvents;
  final int rejectedEvents;
}

final class _StormStateTarget implements AgentConversationStateMutationTarget {
  _StormStateTarget({required this.timeline});

  final AgentConversationTimelineStore timeline;
  final List<AgentConversationStateChange> appliedChanges =
      <AgentConversationStateChange>[];
  final List<bool> snapshotRefreshRunningStates = <bool>[];

  @override
  AgentConversationStateMutationOutcome apply(
    AgentConversationStateChange change,
  ) {
    appliedChanges.add(change);
    return AgentConversationStateMutationOutcome.none;
  }

  @override
  void requestThreadSnapshotRefresh() {
    snapshotRefreshRunningStates.add(timeline.isTurnRunning);
  }
}

final class _CountingUiUpdatePort implements AgentUiUpdatePort {
  int publishedCount = 0;

  @override
  void publish(AgentUiUpdateRequest request) {
    publishedCount += 1;
  }
}

final class _CountingEffectRunner implements AgentConversationEffectRunner {
  final List<Type> effectTypes = <Type>[];
  int turnCompletedCount = 0;
  int providerErrorCount = 0;
  bool disposed = false;

  @override
  void run(AgentConversationEffect effect) {
    effectTypes.add(effect.runtimeType);
    switch (effect) {
      case AgentTurnCompletedEffect():
        turnCompletedCount += 1;
      case AgentRecordModelCatalogEffect():
        break;
      case AgentLogProviderErrorEffect():
        providerErrorCount += 1;
    }
  }

  @override
  void dispose() {
    disposed = true;
  }
}

final class _StormBaselineSnapshot {
  const _StormBaselineSnapshot({
    required this.fixtureInputEvents,
    required this.receivedEvents,
    required this.coalescedEvents,
    required this.barrierOrDirectPassThroughEvents,
    required this.backpressureFlushes,
    required this.currentPendingKeys,
    required this.maxPendingKeys,
    required this.deliveredEvents,
    required this.batchCount,
    required this.yieldCount,
    required this.currentQueueDepth,
    required this.maxQueueDepth,
    required this.deliveredAtSentinel,
    required this.messageCharacters,
    required this.reasoningCharacters,
    required this.permissionRequestedCount,
    required this.permissionResolvedCount,
    required this.errorCount,
    required this.turnCompletedCount,
    required this.terminalToolCount,
    required this.lastTokenTotal,
    required this.lastContextUsed,
    required this.lastDiff,
    required this.lastEventType,
  });

  final int fixtureInputEvents;
  final int receivedEvents;
  final int coalescedEvents;
  final int barrierOrDirectPassThroughEvents;
  final int backpressureFlushes;
  final int currentPendingKeys;
  final int maxPendingKeys;
  final int deliveredEvents;
  final int batchCount;
  final int yieldCount;
  final int currentQueueDepth;
  final int maxQueueDepth;
  final int deliveredAtSentinel;
  final int messageCharacters;
  final int reasoningCharacters;
  final int permissionRequestedCount;
  final int permissionResolvedCount;
  final int errorCount;
  final int turnCompletedCount;
  final int terminalToolCount;
  final int lastTokenTotal;
  final int lastContextUsed;
  final String lastDiff;
  final String lastEventType;

  @override
  bool operator ==(Object other) {
    return other is _StormBaselineSnapshot &&
        fixtureInputEvents == other.fixtureInputEvents &&
        receivedEvents == other.receivedEvents &&
        coalescedEvents == other.coalescedEvents &&
        barrierOrDirectPassThroughEvents ==
            other.barrierOrDirectPassThroughEvents &&
        backpressureFlushes == other.backpressureFlushes &&
        currentPendingKeys == other.currentPendingKeys &&
        maxPendingKeys == other.maxPendingKeys &&
        deliveredEvents == other.deliveredEvents &&
        batchCount == other.batchCount &&
        yieldCount == other.yieldCount &&
        currentQueueDepth == other.currentQueueDepth &&
        maxQueueDepth == other.maxQueueDepth &&
        deliveredAtSentinel == other.deliveredAtSentinel &&
        messageCharacters == other.messageCharacters &&
        reasoningCharacters == other.reasoningCharacters &&
        permissionRequestedCount == other.permissionRequestedCount &&
        permissionResolvedCount == other.permissionResolvedCount &&
        errorCount == other.errorCount &&
        turnCompletedCount == other.turnCompletedCount &&
        terminalToolCount == other.terminalToolCount &&
        lastTokenTotal == other.lastTokenTotal &&
        lastContextUsed == other.lastContextUsed &&
        lastDiff == other.lastDiff &&
        lastEventType == other.lastEventType;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    fixtureInputEvents,
    receivedEvents,
    coalescedEvents,
    barrierOrDirectPassThroughEvents,
    backpressureFlushes,
    currentPendingKeys,
    maxPendingKeys,
    deliveredEvents,
    batchCount,
    yieldCount,
    currentQueueDepth,
    maxQueueDepth,
    deliveredAtSentinel,
    messageCharacters,
    reasoningCharacters,
    permissionRequestedCount,
    permissionResolvedCount,
    errorCount,
    turnCompletedCount,
    terminalToolCount,
    lastTokenTotal,
    lastContextUsed,
    lastDiff,
    lastEventType,
  ]);

  @override
  String toString() {
    return <String, Object>{
      'fixtureInputEvents': fixtureInputEvents,
      'receivedEvents': receivedEvents,
      'coalescedEvents': coalescedEvents,
      'barrierOrDirectPassThroughEvents': barrierOrDirectPassThroughEvents,
      'backpressureFlushes': backpressureFlushes,
      'currentPendingKeys': currentPendingKeys,
      'maxPendingKeys': maxPendingKeys,
      'deliveredEvents': deliveredEvents,
      'batchCount': batchCount,
      'yieldCount': yieldCount,
      'currentQueueDepth': currentQueueDepth,
      'maxQueueDepth': maxQueueDepth,
      'deliveredAtSentinel': deliveredAtSentinel,
      'messageCharacters': messageCharacters,
      'reasoningCharacters': reasoningCharacters,
      'permissionRequestedCount': permissionRequestedCount,
      'permissionResolvedCount': permissionResolvedCount,
      'errorCount': errorCount,
      'turnCompletedCount': turnCompletedCount,
      'terminalToolCount': terminalToolCount,
      'lastTokenTotal': lastTokenTotal,
      'lastContextUsed': lastContextUsed,
      'lastDiff': lastDiff,
      'lastEventType': lastEventType,
    }.toString();
  }
}
