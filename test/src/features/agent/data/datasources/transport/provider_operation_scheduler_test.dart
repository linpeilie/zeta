import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

void main() {
  group('ProviderOperationScheduler', () {
    const threadKey = ThreadOperationKey(
      providerId: 'codex',
      threadId: 'thread-1',
    );

    test('runs exclusive operations FIFO for the same key', () async {
      final scheduler = ProviderOperationScheduler();
      addTearDown(scheduler.close);
      final firstGate = Completer<void>();
      final order = <String>[];

      final first = scheduler.schedule<void>(
        key: threadKey,
        access: ProviderOperationAccess.exclusive,
        operation: () async {
          order.add('first:start');
          await firstGate.future;
          order.add('first:end');
        },
      );
      final second = scheduler.schedule<void>(
        key: threadKey,
        access: ProviderOperationAccess.exclusive,
        operation: () {
          order.add('second');
        },
      );

      expect(order, <String>['first:start']);
      firstGate.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(order, <String>['first:start', 'first:end', 'second']);
    });

    test(
      'runs consecutive reads together and preserves exclusive barrier',
      () async {
        final scheduler = ProviderOperationScheduler();
        addTearDown(scheduler.close);
        final firstReadGate = Completer<void>();
        final secondReadGate = Completer<void>();
        final writeGate = Completer<void>();
        final order = <String>[];

        final firstRead = scheduler.schedule<void>(
          key: threadKey,
          access: ProviderOperationAccess.sharedRead,
          operation: () async {
            order.add('read-1:start');
            await firstReadGate.future;
          },
        );
        final secondRead = scheduler.schedule<void>(
          key: threadKey,
          access: ProviderOperationAccess.sharedRead,
          operation: () async {
            order.add('read-2:start');
            await secondReadGate.future;
          },
        );
        final write = scheduler.schedule<void>(
          key: threadKey,
          access: ProviderOperationAccess.exclusive,
          operation: () async {
            order.add('write:start');
            await writeGate.future;
            order.add('write:end');
          },
        );
        final trailingRead = scheduler.schedule<void>(
          key: threadKey,
          access: ProviderOperationAccess.sharedRead,
          operation: () {
            order.add('read-3');
          },
        );

        expect(order, <String>['read-1:start', 'read-2:start']);
        firstReadGate.complete();
        await firstRead;
        expect(order, isNot(contains('write:start')));

        secondReadGate.complete();
        await secondRead;
        await _flushMicrotasks();
        expect(order.last, 'write:start');
        expect(order, isNot(contains('read-3')));

        writeGate.complete();
        await Future.wait(<Future<void>>[write, trailingRead]);
        expect(order, <String>[
          'read-1:start',
          'read-2:start',
          'write:start',
          'write:end',
          'read-3',
        ]);
      },
    );

    test('runs different resource keys concurrently', () async {
      final scheduler = ProviderOperationScheduler();
      addTearDown(scheduler.close);
      final firstGate = Completer<void>();
      final secondGate = Completer<void>();
      final started = <String>[];

      final first = scheduler.schedule<void>(
        key: threadKey,
        access: ProviderOperationAccess.exclusive,
        operation: () async {
          started.add('thread-1');
          await firstGate.future;
        },
      );
      final second = scheduler.schedule<void>(
        key: const ThreadOperationKey(
          providerId: 'codex',
          threadId: 'thread-2',
        ),
        access: ProviderOperationAccess.exclusive,
        operation: () async {
          started.add('thread-2');
          await secondGate.future;
        },
      );

      expect(started, <String>['thread-1', 'thread-2']);
      firstGate.complete();
      secondGate.complete();
      await Future.wait(<Future<void>>[first, second]);
    });

    test('releases an exclusive key after operation failure', () async {
      final scheduler = ProviderOperationScheduler();
      addTearDown(scheduler.close);
      final order = <String>[];

      final failed = scheduler.schedule<void>(
        key: threadKey,
        access: ProviderOperationAccess.exclusive,
        operation: () {
          order.add('failed');
          throw StateError('boom');
        },
      );
      final next = scheduler.schedule<void>(
        key: threadKey,
        access: ProviderOperationAccess.exclusive,
        operation: () {
          order.add('next');
        },
      );

      await expectLater(failed, throwsStateError);
      await next;
      expect(order, <String>['failed', 'next']);
    });

    test('rejects same-key reentrancy instead of deadlocking', () async {
      final scheduler = ProviderOperationScheduler();
      addTearDown(scheduler.close);

      final operation = scheduler.schedule<void>(
        key: threadKey,
        access: ProviderOperationAccess.exclusive,
        operation: () async {
          await scheduler.schedule<void>(
            key: threadKey,
            access: ProviderOperationAccess.sharedRead,
            operation: () {},
          );
        },
      );

      await expectLater(
        operation,
        throwsA(isA<ProviderOperationReentrancyException>()),
      );
    });

    test('close rejects queued and new work then drains active work', () async {
      final scheduler = ProviderOperationScheduler();
      final activeGate = Completer<void>();
      var closeCompleted = false;

      final active = scheduler.schedule<void>(
        key: threadKey,
        access: ProviderOperationAccess.exclusive,
        operation: () => activeGate.future,
      );
      final queued = scheduler.schedule<void>(
        key: threadKey,
        access: ProviderOperationAccess.exclusive,
        operation: () {},
      );
      final queuedExpectation = expectLater(
        queued,
        throwsA(isA<ProviderOperationSchedulerClosedException>()),
      );

      final close = scheduler.close().whenComplete(() {
        closeCompleted = true;
      });
      await queuedExpectation;
      await expectLater(
        scheduler.schedule<void>(
          key: threadKey,
          access: ProviderOperationAccess.sharedRead,
          operation: () {},
        ),
        throwsA(isA<ProviderOperationSchedulerClosedException>()),
      );
      expect(closeCompleted, isFalse);
      expect(scheduler.isClosing, isTrue);

      activeGate.complete();
      await active;
      await close;
      expect(scheduler.isClosed, isTrue);
      await scheduler.close();
    });
  });
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);
