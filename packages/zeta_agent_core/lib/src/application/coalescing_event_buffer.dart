import 'dart:async';

/// 事件合并业务策略。
///
/// 通用缓冲器只负责保持首次到达顺序、容量上限与调度；key、merge 和 barrier
/// 语义由具体 feature 提供。
abstract interface class EventCoalescingPolicy<E, K> {
  K? keyOf(E event);

  bool isBarrier(E event);

  E merge(E previous, E next);
}

/// [CoalescingEventBuffer] 的只读诊断快照。
///
/// 快照只包含计数和队列深度，不持有事件内容或业务 identity。
final class CoalescingEventBufferDiagnostics {
  const CoalescingEventBufferDiagnostics({
    required this.receivedEvents,
    required this.coalescedEvents,
    required this.barrierEvents,
    required this.directPassThroughEvents,
    required this.backpressureFlushes,
    required this.currentPendingKeys,
    required this.maxPendingKeys,
  });

  final int receivedEvents;
  final int coalescedEvents;
  final int barrierEvents;
  final int directPassThroughEvents;
  final int backpressureFlushes;
  final int currentPendingKeys;
  final int maxPendingKeys;
}

/// 保持首次到达顺序的通用 keyed coalescing 缓冲器。
final class CoalescingEventBuffer<E, K> {
  CoalescingEventBuffer({
    required this.policy,
    required this.onEmit,
    this.maxPendingKeys = 512,
    this.onBackpressure,
    void Function(void Function() callback)? scheduleFlush,
  }) : assert(maxPendingKeys > 0),
       _scheduleFlushCallback = scheduleFlush ?? scheduleMicrotask;

  final EventCoalescingPolicy<E, K> policy;
  final void Function(E event) onEmit;
  final int maxPendingKeys;

  /// 达到 pending key 上限时只上报数量，不暴露事件内容。
  final void Function(int pendingKeyCount)? onBackpressure;

  final void Function(void Function() callback) _scheduleFlushCallback;
  final Map<K, E> _pending = <K, E>{};
  bool _flushScheduled = false;
  bool _disposed = false;
  int _receivedEvents = 0;
  int _coalescedEvents = 0;
  int _barrierEvents = 0;
  int _directPassThroughEvents = 0;
  int _backpressureFlushes = 0;
  int _maxPendingKeys = 0;

  int get pendingKeyCount => _pending.length;

  CoalescingEventBufferDiagnostics get diagnostics =>
      CoalescingEventBufferDiagnostics(
        receivedEvents: _receivedEvents,
        coalescedEvents: _coalescedEvents,
        barrierEvents: _barrierEvents,
        directPassThroughEvents: _directPassThroughEvents,
        backpressureFlushes: _backpressureFlushes,
        currentPendingKeys: _pending.length,
        maxPendingKeys: _maxPendingKeys,
      );

  void add(E event) {
    if (_disposed) {
      return;
    }
    _receivedEvents += 1;
    final key = policy.keyOf(event);
    final isBarrier = policy.isBarrier(event);
    if (isBarrier || key == null) {
      if (isBarrier) {
        _barrierEvents += 1;
      } else {
        _directPassThroughEvents += 1;
      }
      flush();
      onEmit(event);
      return;
    }

    final hasPrevious = _pending.containsKey(key);
    final previous = _pending[key];
    if (hasPrevious) {
      _coalescedEvents += 1;
    }
    _pending[key] = hasPrevious ? policy.merge(previous as E, event) : event;
    if (_pending.length > _maxPendingKeys) {
      _maxPendingKeys = _pending.length;
    }
    if (_pending.length >= maxPendingKeys) {
      _backpressureFlushes += 1;
      onBackpressure?.call(_pending.length);
      flush();
      return;
    }
    _scheduleFlush();
  }

  /// 立即按每个 key 首次到达的顺序发布当前批次。
  void flush() {
    if (_disposed || _pending.isEmpty) {
      _flushScheduled = false;
      return;
    }
    final events = _pending.values.toList(growable: false);
    _pending.clear();
    _flushScheduled = false;
    for (final event in events) {
      onEmit(event);
    }
  }

  /// 丢弃当前批次，但允许后续继续接收事件。
  void clear() {
    if (_disposed) {
      return;
    }
    _pending.clear();
    _flushScheduled = false;
  }

  /// 停止缓冲器；默认丢弃尚未发布的普通事件。
  void dispose({bool flushPending = false}) {
    if (_disposed) {
      return;
    }
    if (flushPending) {
      flush();
    } else {
      clear();
    }
    _disposed = true;
  }

  void _scheduleFlush() {
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    _scheduleFlushCallback(() {
      if (!_disposed && _flushScheduled) {
        flush();
      }
    });
  }
}
