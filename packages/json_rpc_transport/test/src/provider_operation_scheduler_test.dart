import 'dart:async';

import 'package:json_rpc_transport/json_rpc_transport.dart';
import 'package:test/test.dart';

void main() {
  group('operation keys', () {
    test('provide value equality and stable diagnostics', () {
      expect(
        const RuntimeOperationKey('codex'),
        const RuntimeOperationKey('codex'),
      );
      expect(const RuntimeOperationKey('codex').toString(), 'runtime:codex');
      expect(
        const RuntimeOperationKey('codex').hashCode,
        const RuntimeOperationKey('codex').hashCode,
      );

      const project = ProjectOperationKey(
        providerId: 'codex',
        projectPath: null,
      );
      expect(
        project,
        const ProjectOperationKey(providerId: 'codex', projectPath: null),
      );
      expect(project.toString(), 'project:codex:<all>');
      expect(
        project.hashCode,
        const ProjectOperationKey(
          providerId: 'codex',
          projectPath: null,
        ).hashCode,
      );

      const thread = ThreadOperationKey(
        providerId: 'codex',
        threadId: 'thread-1',
      );
      expect(
        thread,
        const ThreadOperationKey(providerId: 'codex', threadId: 'thread-1'),
      );
      expect(thread.toString(), 'thread:codex:thread-1');

      const process = ProcessOperationKey(runtimeId: 'runtime', processId: '1');
      expect(
        process,
        const ProcessOperationKey(runtimeId: 'runtime', processId: '1'),
      );
      expect(process.toString(), 'process:runtime:1');
      expect(
        process,
        isNot(const ProcessOperationKey(runtimeId: 'other', processId: '1')),
      );
      expect(
        process.hashCode,
        const ProcessOperationKey(
          runtimeId: 'runtime',
          processId: '1',
        ).hashCode,
      );
    });

    test('typed scheduler failures render without payloads', () {
      const key = RuntimeOperationKey('codex');
      expect(
        const ProviderOperationSchedulerClosedException().toString(),
        'Provider operation scheduler is closed',
      );
      expect(
        const ProviderOperationReentrancyException(key).toString(),
        'Provider operation cannot re-enter runtime:codex',
      );
    });
  });

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
        operation: () => order.add('second'),
      );

      expect(order, <String>['first:start']);
      firstGate.complete();
      await Future.wait(<Future<void>>[first, second]);
      expect(order, <String>['first:start', 'first:end', 'second']);
    });

    test('runs reads together and preserves an exclusive barrier', () async {
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
          order.add('read-1');
          await firstReadGate.future;
        },
      );
      final secondRead = scheduler.schedule<void>(
        key: threadKey,
        access: ProviderOperationAccess.sharedRead,
        operation: () async {
          order.add('read-2');
          await secondReadGate.future;
        },
      );
      final write = scheduler.schedule<void>(
        key: threadKey,
        access: ProviderOperationAccess.exclusive,
        operation: () async {
          order.add('write');
          await writeGate.future;
        },
      );
      final trailingRead = scheduler.schedule<void>(
        key: threadKey,
        access: ProviderOperationAccess.sharedRead,
        operation: () => order.add('read-3'),
      );

      expect(order, <String>['read-1', 'read-2']);
      firstReadGate.complete();
      await firstRead;
      expect(order, isNot(contains('write')));
      secondReadGate.complete();
      await secondRead;
      await _flushMicrotasks();
      expect(order.last, 'write');
      expect(order, isNot(contains('read-3')));
      writeGate.complete();
      await Future.wait(<Future<void>>[write, trailingRead]);
      expect(order, <String>['read-1', 'read-2', 'write', 'read-3']);
    });

    test('runs different keys concurrently', () async {
      final scheduler = ProviderOperationScheduler();
      addTearDown(scheduler.close);
      final firstGate = Completer<void>();
      final secondGate = Completer<void>();
      final started = <String>[];

      final first = scheduler.schedule<void>(
        key: threadKey,
        access: ProviderOperationAccess.exclusive,
        operation: () async {
          started.add('one');
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
          started.add('two');
          await secondGate.future;
        },
      );

      expect(started, <String>['one', 'two']);
      firstGate.complete();
      secondGate.complete();
      await Future.wait(<Future<void>>[first, second]);
    });

    test('releases an exclusive key after failure', () async {
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
        operation: () => order.add('next'),
      );

      await expectLater(failed, throwsStateError);
      await next;
      expect(order, <String>['failed', 'next']);
    });

    test('rejects same-key reentrancy', () async {
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

    test('close cancels queued work and drains active work', () async {
      final scheduler = ProviderOperationScheduler();
      final activeGate = Completer<void>();
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
      final close = scheduler.close();
      scheduler.beginClosing();
      await queuedExpectation;
      await expectLater(
        scheduler.schedule<void>(
          key: threadKey,
          access: ProviderOperationAccess.sharedRead,
          operation: () {},
        ),
        throwsA(isA<ProviderOperationSchedulerClosedException>()),
      );
      expect(scheduler.isClosing, isTrue);
      activeGate.complete();
      await active;
      await close;
      expect(scheduler.isClosed, isTrue);
      await scheduler.close();
    });

    test('closes immediately when no work exists', () async {
      final scheduler = ProviderOperationScheduler();
      await scheduler.close();
      expect(scheduler.isClosed, isTrue);
    });
  });
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);
