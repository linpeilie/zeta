import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_event_frame_scheduler.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentEventFrameScheduler', () {
    test('batches sync adds into one turn via scheduleTurn', () async {
      final delivered = <String>[];
      final scheduler = AgentEventFrameScheduler(
        onEvent: (event) {
          delivered.add((event as AgentMessageDeltaEvent).messageId);
        },
      );

      scheduler
        ..add(_delta('a'))
        ..add(_delta('b'))
        ..add(_delta('c'));

      // 入队在同步栈；首批投递在 microtask。
      expect(delivered, isEmpty);
      expect(scheduler.pendingCount, 3);

      await Future<void>.delayed(Duration.zero);
      expect(delivered, <String>['a', 'b', 'c']);
      expect(scheduler.debugYieldCount, 0);
    });

    test(
      'default scheduler yields to queued event before next batch',
      () async {
        // Arrange
        final order = <String>[];
        final markerReached = Completer<void>();
        final scheduler = AgentEventFrameScheduler(
          maxEventsPerTurn: 2,
          onEvent: (event) {
            order.add((event as AgentMessageDeltaEvent).messageId);
          },
        );
        scheduler
          ..add(_delta('1'))
          ..add(_delta('2'))
          ..add(_delta('3'))
          ..add(_delta('4'))
          ..add(_delta('5'));

        // Act
        Timer.run(() {
          order.add('queued-event');
          markerReached.complete();
        });
        await markerReached.future;

        // Assert
        expect(order, <String>['1', '2', 'queued-event']);
        expect(scheduler.pendingCount, 3);

        await Future<void>.delayed(Duration.zero);
        expect(order, <String>['1', '2', 'queued-event', '3', '4']);
        expect(scheduler.pendingCount, 1);

        await Future<void>.delayed(Duration.zero);
        expect(order, <String>['1', '2', 'queued-event', '3', '4', '5']);
        expect(scheduler.pendingCount, 0);
      },
    );

    test('yields after maxEventsPerTurn and continues next turn', () async {
      final delivered = <String>[];
      final scheduled = <void Function()>[];
      final scheduler = AgentEventFrameScheduler(
        maxEventsPerTurn: 2,
        scheduleTurn: scheduled.add,
        onEvent: (event) {
          delivered.add((event as AgentMessageDeltaEvent).messageId);
        },
      );

      scheduler
        ..add(_delta('1'))
        ..add(_delta('2'))
        ..add(_delta('3'))
        ..add(_delta('4'))
        ..add(_delta('5'));

      expect(delivered, isEmpty);
      expect(scheduled, hasLength(1));
      final queuedSnapshot = scheduler.diagnostics;
      expect(queuedSnapshot.deliveredEvents, 0);
      expect(queuedSnapshot.batchCount, 0);
      expect(queuedSnapshot.yieldCount, 0);
      expect(queuedSnapshot.currentQueueDepth, 5);
      expect(queuedSnapshot.maxQueueDepth, 5);

      scheduled.removeAt(0)();
      expect(delivered, <String>['1', '2']);
      expect(scheduler.debugYieldCount, 1);
      expect(scheduler.pendingCount, 3);
      expect(scheduler.diagnostics.deliveredEvents, 2);
      expect(scheduler.diagnostics.batchCount, 1);
      expect(scheduler.diagnostics.yieldCount, 1);
      expect(scheduler.diagnostics.currentQueueDepth, 3);
      expect(scheduler.diagnostics.maxQueueDepth, 5);

      expect(scheduled, hasLength(1));
      scheduled.removeAt(0)();
      expect(delivered, <String>['1', '2', '3', '4']);
      expect(scheduler.debugYieldCount, 2);
      expect(scheduler.diagnostics.deliveredEvents, 4);
      expect(scheduler.diagnostics.batchCount, 2);
      expect(scheduler.diagnostics.yieldCount, 2);
      expect(scheduler.diagnostics.currentQueueDepth, 1);

      expect(scheduled, hasLength(1));
      scheduled.removeAt(0)();
      expect(delivered, <String>['1', '2', '3', '4', '5']);
      expect(scheduler.pendingCount, 0);
      expect(scheduler.diagnostics.deliveredEvents, 5);
      expect(scheduler.diagnostics.batchCount, 3);
      expect(scheduler.diagnostics.yieldCount, 2);
      expect(scheduler.diagnostics.currentQueueDepth, 0);
      expect(scheduler.diagnostics.maxQueueDepth, 5);
      // 先前取得的对象是值快照，不随内部 Queue 后续变化。
      expect(queuedSnapshot.currentQueueDepth, 5);
    });

    test('flush drains remaining ignoring per-turn budget', () {
      final delivered = <String>[];
      final scheduled = <void Function()>[];
      final scheduler = AgentEventFrameScheduler(
        maxEventsPerTurn: 1,
        scheduleTurn: scheduled.add,
        onEvent: (event) {
          delivered.add((event as AgentMessageDeltaEvent).messageId);
        },
      );

      scheduler
        ..add(_delta('a'))
        ..add(_delta('b'))
        ..add(_delta('c'));
      expect(delivered, isEmpty);

      scheduler.flush();
      expect(delivered, <String>['a', 'b', 'c']);
      expect(scheduler.diagnostics.deliveredEvents, 3);
      expect(scheduler.diagnostics.batchCount, 1);
      expect(scheduler.diagnostics.yieldCount, 0);
      expect(scheduler.diagnostics.currentQueueDepth, 0);
      expect(scheduler.diagnostics.maxQueueDepth, 3);
    });

    test('dispose without flush drops pending', () {
      final delivered = <String>[];
      final scheduled = <void Function()>[];
      final scheduler = AgentEventFrameScheduler(
        maxEventsPerTurn: 1,
        scheduleTurn: scheduled.add,
        onEvent: (event) {
          delivered.add((event as AgentMessageDeltaEvent).messageId);
        },
      );

      scheduler
        ..add(_delta('a'))
        ..add(_delta('b'));
      expect(delivered, isEmpty);

      scheduler.dispose();
      if (scheduled.isNotEmpty) {
        scheduled.removeAt(0)();
      }
      expect(delivered, isEmpty);
    });
  });
}

AgentMessageDeltaEvent _delta(String id) {
  return AgentMessageDeltaEvent(
    messageId: id,
    delta: id,
    role: AgentMessageRole.agent,
  );
}
