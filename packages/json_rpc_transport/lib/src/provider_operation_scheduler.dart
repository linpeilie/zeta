import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

/// Access mode for a provider operation.
enum ProviderOperationAccess {
  /// Multiple consecutive reads may run concurrently.
  sharedRead,

  /// The operation runs alone for its resource key.
  exclusive,
}

/// Resource key protected by [ProviderOperationScheduler].
sealed class ProviderOperationKey {
  const ProviderOperationKey();
}

/// Key for an entire provider runtime.
@immutable
final class RuntimeOperationKey extends ProviderOperationKey {
  /// Creates a provider runtime key.
  const RuntimeOperationKey(this.providerId);

  /// Stable provider identifier.
  final String providerId;

  @override
  bool operator ==(Object other) =>
      other is RuntimeOperationKey && other.providerId == providerId;

  @override
  int get hashCode => Object.hash(RuntimeOperationKey, providerId);

  @override
  String toString() => 'runtime:$providerId';
}

/// Key for operations scoped to a provider project.
@immutable
final class ProjectOperationKey extends ProviderOperationKey {
  /// Creates a provider project key.
  const ProjectOperationKey({
    required this.providerId,
    required this.projectPath,
  });

  /// Stable provider identifier.
  final String providerId;

  /// Canonical project path, or null for all projects.
  final String? projectPath;

  @override
  bool operator ==(Object other) =>
      other is ProjectOperationKey &&
      other.providerId == providerId &&
      other.projectPath == projectPath;

  @override
  int get hashCode => Object.hash(ProjectOperationKey, providerId, projectPath);

  @override
  String toString() => 'project:$providerId:${projectPath ?? '<all>'}';
}

/// Key for operations scoped to a provider thread.
@immutable
final class ThreadOperationKey extends ProviderOperationKey {
  /// Creates a provider thread key.
  const ThreadOperationKey({required this.providerId, required this.threadId});

  /// Stable provider identifier.
  final String providerId;

  /// Stable thread identifier.
  final String threadId;

  @override
  bool operator ==(Object other) =>
      other is ThreadOperationKey &&
      other.providerId == providerId &&
      other.threadId == threadId;

  @override
  int get hashCode => Object.hash(ThreadOperationKey, providerId, threadId);

  @override
  String toString() => 'thread:$providerId:$threadId';
}

/// Key for operations scoped to a provider child process.
@immutable
final class ProcessOperationKey extends ProviderOperationKey {
  /// Creates a provider process key.
  const ProcessOperationKey({required this.runtimeId, required this.processId});

  /// Stable runtime identifier.
  final String runtimeId;

  /// Stable process identifier within the runtime.
  final String processId;

  @override
  bool operator ==(Object other) =>
      other is ProcessOperationKey &&
      other.runtimeId == runtimeId &&
      other.processId == processId;

  @override
  int get hashCode => Object.hash(ProcessOperationKey, runtimeId, processId);

  @override
  String toString() => 'process:$runtimeId:$processId';
}

/// Work was submitted after the scheduler began closing.
final class ProviderOperationSchedulerClosedException implements Exception {
  /// Creates a scheduler-closed failure.
  const ProviderOperationSchedulerClosedException();

  @override
  String toString() => 'Provider operation scheduler is closed';
}

/// An operation attempted to reacquire a key it already holds.
final class ProviderOperationReentrancyException implements Exception {
  /// Creates a same-key reentrancy failure.
  const ProviderOperationReentrancyException(this.key);

  /// Key already held by the operation.
  final ProviderOperationKey key;

  @override
  String toString() => 'Provider operation cannot re-enter $key';
}

/// Serializes exclusive work and batches consecutive shared reads per key.
final class ProviderOperationScheduler {
  final Map<ProviderOperationKey, _OperationQueue> _queues =
      <ProviderOperationKey, _OperationQueue>{};
  final Object _zoneKey = Object();

  bool _accepting = true;
  bool _closed = false;
  int _activeOperations = 0;
  Completer<void>? _closeCompleter;

  /// Whether closing has started but active work has not drained.
  bool get isClosing => !_accepting && !_closed;

  /// Whether the scheduler has fully drained.
  bool get isClosed => _closed;

  /// Submits an operation protected by [key].
  Future<T> schedule<T>({
    required ProviderOperationKey key,
    required ProviderOperationAccess access,
    required FutureOr<T> Function() operation,
  }) {
    if (!_accepting) {
      return Future<T>.error(
        const ProviderOperationSchedulerClosedException(),
        StackTrace.current,
      );
    }
    final heldKeys = Zone.current[_zoneKey];
    if (heldKeys is Set<ProviderOperationKey> && heldKeys.contains(key)) {
      return Future<T>.error(
        ProviderOperationReentrancyException(key),
        StackTrace.current,
      );
    }

    final pending = _PendingOperation<T>(access: access, operation: operation);
    final queue = _queues.putIfAbsent(key, _OperationQueue.new);
    queue.pending.add(pending);
    _drain(key, queue);
    return pending.future;
  }

  /// Stops accepting work and cancels operations that have not started.
  void beginClosing() {
    if (!_accepting) {
      return;
    }
    _accepting = false;
    const error = ProviderOperationSchedulerClosedException();
    final stackTrace = StackTrace.current;
    for (final entry in _queues.entries.toList(growable: false)) {
      final queue = entry.value;
      while (queue.pending.isNotEmpty) {
        queue.pending.removeFirst().reject(error, stackTrace);
      }
    }
    _completeCloseIfDrained();
  }

  /// Idempotently closes the scheduler after active work drains.
  Future<void> close() {
    beginClosing();
    if (_closed) {
      return Future<void>.value();
    }
    return (_closeCompleter ??= Completer<void>()).future;
  }

  void _drain(ProviderOperationKey key, _OperationQueue queue) {
    if (queue.exclusiveActive || queue.pending.isEmpty) {
      return;
    }
    if (queue.sharedActive > 0) {
      while (queue.pending.isNotEmpty &&
          queue.pending.first.access == ProviderOperationAccess.sharedRead) {
        _start(key, queue, queue.pending.removeFirst());
      }
      return;
    }
    if (queue.pending.first.access == ProviderOperationAccess.exclusive) {
      _start(key, queue, queue.pending.removeFirst());
      return;
    }
    while (queue.pending.isNotEmpty &&
        queue.pending.first.access == ProviderOperationAccess.sharedRead) {
      _start(key, queue, queue.pending.removeFirst());
    }
  }

  void _start(
    ProviderOperationKey key,
    _OperationQueue queue,
    _PendingOperationBase pending,
  ) {
    switch (pending.access) {
      case ProviderOperationAccess.sharedRead:
        queue.sharedActive += 1;
      case ProviderOperationAccess.exclusive:
        queue.exclusiveActive = true;
    }
    _activeOperations += 1;

    final inheritedKeys = Zone.current[_zoneKey];
    final heldKeys = <ProviderOperationKey>{
      if (inheritedKeys is Set<ProviderOperationKey>) ...inheritedKeys,
      key,
    };
    unawaited(
      pending
          .execute(
            zoneKey: _zoneKey,
            heldKeys: Set<ProviderOperationKey>.unmodifiable(heldKeys),
          )
          .whenComplete(() {
            switch (pending.access) {
              case ProviderOperationAccess.sharedRead:
                queue.sharedActive -= 1;
              case ProviderOperationAccess.exclusive:
                queue.exclusiveActive = false;
            }
            _activeOperations -= 1;
            if (queue.pending.isEmpty && !queue.hasActiveOperations) {
              _queues.remove(key);
            } else {
              _drain(key, queue);
            }
            _completeCloseIfDrained();
          }),
    );
  }

  void _completeCloseIfDrained() {
    if (_accepting || _activeOperations != 0 || _closed) {
      return;
    }
    _closed = true;
    final completer = _closeCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}

final class _OperationQueue {
  final Queue<_PendingOperationBase> pending = Queue<_PendingOperationBase>();
  int sharedActive = 0;
  bool exclusiveActive = false;

  bool get hasActiveOperations => sharedActive > 0 || exclusiveActive;
}

abstract base class _PendingOperationBase {
  const _PendingOperationBase({required this.access});

  final ProviderOperationAccess access;

  Future<void> execute({
    required Object zoneKey,
    required Set<ProviderOperationKey> heldKeys,
  });

  void reject(Object error, StackTrace stackTrace);
}

final class _PendingOperation<T> extends _PendingOperationBase {
  _PendingOperation({required super.access, required this.operation});

  final FutureOr<T> Function() operation;
  final Completer<T> _completer = Completer<T>();

  Future<T> get future => _completer.future;

  @override
  Future<void> execute({
    required Object zoneKey,
    required Set<ProviderOperationKey> heldKeys,
  }) async {
    try {
      final result = await runZoned<Future<T>>(
        () async => operation(),
        zoneValues: <Object, Object>{zoneKey: heldKeys},
      );
      _completer.complete(result);
    } catch (error, stackTrace) {
      _completer.completeError(error, stackTrace);
    }
  }

  @override
  void reject(Object error, StackTrace stackTrace) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
    }
  }
}
