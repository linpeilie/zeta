import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/bounded_event_dispatcher.dart';

void main() {
  group('BoundedEventDispatcher', () {
    test('同步入队保持低延迟 microtask 与 FIFO', () async {
      final delivered = <String>[];
      final dispatcher = BoundedEventDispatcher<String>(onEvent: delivered.add);

      dispatcher
        ..add('a')
        ..add('b')
        ..add('c');

      expect(delivered, isEmpty);
      expect(dispatcher.pendingCount, 3);

      await Future<void>.delayed(Duration.zero);
      expect(delivered, <String>['a', 'b', 'c']);
      expect(dispatcher.diagnostics.yieldCount, 0);
    });

    test('默认 continuation 让 event queue sentinel 交错执行', () async {
      final order = <String>[];
      final markerReached = Completer<void>();
      final dispatcher = BoundedEventDispatcher<String>(
        maxEventsPerTurn: 2,
        onEvent: order.add,
      );
      dispatcher
        ..add('1')
        ..add('2')
        ..add('3')
        ..add('4')
        ..add('5');

      Timer.run(() {
        order.add('queued-event');
        markerReached.complete();
      });
      await markerReached.future;

      expect(order, <String>['1', '2', 'queued-event']);
      expect(dispatcher.pendingCount, 3);

      await Future<void>.delayed(Duration.zero);
      expect(order, <String>['1', '2', 'queued-event', '3', '4']);
      await Future<void>.delayed(Duration.zero);
      expect(order, <String>['1', '2', 'queued-event', '3', '4', '5']);
    });

    test('每轮不超过上限且 initial/continuation 可分别注入', () {
      final delivered = <String>[];
      final initial = <void Function()>[];
      final continuations = <void Function()>[];
      final dispatcher = BoundedEventDispatcher<String>(
        maxEventsPerTurn: 2,
        scheduleInitial: initial.add,
        scheduleContinuation: continuations.add,
        onEvent: delivered.add,
      );

      dispatcher
        ..add('1')
        ..add('2')
        ..add('3')
        ..add('4')
        ..add('5');

      final queuedSnapshot = dispatcher.diagnostics;
      expect(initial, hasLength(1));
      expect(continuations, isEmpty);
      expect(queuedSnapshot.currentQueueDepth, 5);
      expect(queuedSnapshot.maxQueueDepth, 5);

      initial.removeAt(0)();
      expect(delivered, <String>['1', '2']);
      expect(continuations, hasLength(1));
      expect(dispatcher.diagnostics.yieldCount, 1);

      continuations.removeAt(0)();
      expect(delivered, <String>['1', '2', '3', '4']);
      expect(continuations, hasLength(1));
      expect(dispatcher.diagnostics.yieldCount, 2);

      continuations.removeAt(0)();
      expect(delivered, <String>['1', '2', '3', '4', '5']);
      expect(dispatcher.diagnostics.currentQueueDepth, 0);
      expect(dispatcher.diagnostics.batchCount, 3);
      expect(queuedSnapshot.currentQueueDepth, 5);
    });

    test('close drain 继续按每轮上限排空后完成', () async {
      final delivered = <String>[];
      final scheduled = <void Function()>[];
      final dispatcher = BoundedEventDispatcher<String>(
        maxEventsPerTurn: 1,
        scheduleInitial: scheduled.add,
        scheduleContinuation: scheduled.add,
        onEvent: delivered.add,
      );
      dispatcher
        ..add('a')
        ..add('b')
        ..add('c');

      var closed = false;
      final closeFuture = dispatcher.close()..then((_) => closed = true);
      expect(closed, isFalse);

      scheduled.removeAt(0)();
      expect(delivered, <String>['a']);
      expect(closed, isFalse);
      scheduled.removeAt(0)();
      expect(delivered, <String>['a', 'b']);
      expect(closed, isFalse);
      scheduled.removeAt(0)();
      await closeFuture;

      expect(delivered, <String>['a', 'b', 'c']);
      expect(closed, isTrue);
      expect(dispatcher.diagnostics.yieldCount, 2);
    });

    test('close clear 与 dispose 均不回调 pending 事件', () async {
      final delivered = <String>[];
      final scheduled = <void Function()>[];
      final dispatcher = BoundedEventDispatcher<String>(
        scheduleInitial: scheduled.add,
        onEvent: delivered.add,
      );
      dispatcher
        ..add('a')
        ..add('b');

      await dispatcher.close(drain: false);
      scheduled.removeAt(0)();
      dispatcher.add('after-close');

      expect(delivered, isEmpty);
      expect(dispatcher.diagnostics.currentQueueDepth, 0);

      final disposed = BoundedEventDispatcher<String>(
        scheduleInitial: scheduled.add,
        onEvent: delivered.add,
      )..add('disposed');
      disposed.dispose();
      scheduled.removeAt(0)();
      expect(delivered, isEmpty);
    });
  });
}
