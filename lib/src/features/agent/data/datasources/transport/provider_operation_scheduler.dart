import 'dart:async';
import 'dart:collection';

/// Provider 操作访问模式。
enum ProviderOperationAccess { sharedRead, exclusive }

/// Provider 操作使用的资源键。
sealed class ProviderOperationKey {
  const ProviderOperationKey();
}

/// 整个 Provider 运行时的资源键。
final class RuntimeOperationKey extends ProviderOperationKey {
  const RuntimeOperationKey(this.providerId);

  final String providerId;

  @override
  bool operator ==(Object other) =>
      other is RuntimeOperationKey && other.providerId == providerId;

  @override
  int get hashCode => Object.hash(RuntimeOperationKey, providerId);

  @override
  String toString() => 'runtime:$providerId';
}

/// Provider 项目范围的资源键。
final class ProjectOperationKey extends ProviderOperationKey {
  const ProjectOperationKey({
    required this.providerId,
    required this.projectPath,
  });

  final String providerId;
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

/// Provider Thread 范围的资源键。
final class ThreadOperationKey extends ProviderOperationKey {
  const ThreadOperationKey({required this.providerId, required this.threadId});

  final String providerId;
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

/// Provider 子进程范围的资源键。
final class ProcessOperationKey extends ProviderOperationKey {
  const ProcessOperationKey({required this.runtimeId, required this.processId});

  final String runtimeId;
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

/// 调度器关闭后仍尝试提交操作。
final class ProviderOperationSchedulerClosedException implements Exception {
  const ProviderOperationSchedulerClosedException();

  @override
  String toString() => 'Provider operation scheduler is closed';
}

/// 操作持有资源键时再次调度同键，若等待会形成死锁。
final class ProviderOperationReentrancyException implements Exception {
  const ProviderOperationReentrancyException(this.key);

  final ProviderOperationKey key;

  @override
  String toString() => 'Provider operation cannot re-enter $key';
}

/// 按资源键调度 Provider 操作。
///
/// 同一资源键保持提交顺序：连续的 [ProviderOperationAccess.sharedRead] 可并发，
/// [ProviderOperationAccess.exclusive] 等待此前任务并阻塞后续任务。不同资源键互不
/// 阻塞。关闭时取消尚未入场的任务，并等待已入场任务完成。
final class ProviderOperationScheduler {
  final Map<ProviderOperationKey, _OperationQueue> _queues =
      <ProviderOperationKey, _OperationQueue>{};
  final Object _zoneKey = Object();

  bool _accepting = true;
  bool _closed = false;
  int _activeOperations = 0;
  Completer<void>? _closeCompleter;

  bool get isClosing => !_accepting && !_closed;

  bool get isClosed => _closed;

  /// 提交一个受资源键保护的操作。
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

  /// 停止接收新任务，并取消尚未开始的任务。
  void beginClosing() {
    if (!_accepting) {
      return;
    }
    _accepting = false;
    final error = const ProviderOperationSchedulerClosedException();
    final stackTrace = StackTrace.current;
    for (final entry in _queues.entries.toList(growable: false)) {
      final queue = entry.value;
      while (queue.pending.isNotEmpty) {
        queue.pending.removeFirst().reject(error, stackTrace);
      }
      if (!queue.hasActiveOperations) {
        _queues.remove(entry.key);
      }
    }
    _completeCloseIfDrained();
  }

  /// 幂等关闭调度器，并等待已经开始的任务完成。
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
