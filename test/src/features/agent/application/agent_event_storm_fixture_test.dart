import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_event_frame_scheduler.dart';
import 'package:zeta/src/features/agent/application/agent_event_stream_buffer.dart';
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
}

Future<_StormBaselineSnapshot> _runStorm() async {
  final fixture = AgentEventStormFixture();
  final delivered = <AgentEvent>[];
  late final AgentEventFrameScheduler scheduler;
  scheduler = AgentEventFrameScheduler(
    onEvent: delivered.add,
    maxEventsPerTurn: 64,
  );
  final buffer = AgentEventStreamBuffer(onEvent: scheduler.add);

  for (final event in fixture.events) {
    buffer.add(event);
  }
  buffer.flush();

  final sentinel = fixture.createEventQueueSentinel();
  final deliveredAtSentinel = await sentinel.schedule(
    readDeliveredCount: () => scheduler.diagnostics.deliveredEvents,
  );
  while (scheduler.diagnostics.currentQueueDepth > 0) {
    await Future<void>.delayed(Duration.zero);
  }

  final bufferDiagnostics = buffer.diagnostics;
  final schedulerDiagnostics = scheduler.diagnostics;
  final snapshot = _StormBaselineSnapshot(
    fixtureInputEvents: fixture.expectedInputEventCount,
    receivedEvents: bufferDiagnostics.receivedEvents,
    coalescedEvents: bufferDiagnostics.coalescedEvents,
    barrierOrDirectPassThroughEvents:
        bufferDiagnostics.barrierOrDirectPassThroughEvents,
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
  scheduler.dispose();
  return snapshot;
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
