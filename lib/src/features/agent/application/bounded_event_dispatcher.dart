import 'dart:async';
import 'dart:collection';

/// 默认每个 Dart event-loop turn 最多投递的事件数。
const int kDefaultMaxEventsPerTurn = 64;

/// [BoundedEventDispatcher] 的只读诊断快照。
///
/// 快照仅记录吞吐和队列深度，不持有事件或事件内容。
final class BoundedEventDispatcherDiagnostics {
  const BoundedEventDispatcherDiagnostics({
    required this.deliveredEvents,
    required this.batchCount,
    required this.yieldCount,
    required this.currentQueueDepth,
    required this.maxQueueDepth,
  });

  final int deliveredEvents;
  final int batchCount;
  final int yieldCount;
  final int currentQueueDepth;
  final int maxQueueDepth;
}

/// FIFO 有界事件分发器。
///
/// 首批默认使用 microtask 保持低延迟；达到 [maxEventsPerTurn] 后，continuation
/// 默认通过 [Timer.run] 让出 Dart event queue，不依赖 Flutter idle task。
final class BoundedEventDispatcher<E> {
  BoundedEventDispatcher({
    required this.onEvent,
    this.maxEventsPerTurn = kDefaultMaxEventsPerTurn,
    void Function(void Function() callback)? scheduleInitial,
    void Function(void Function() callback)? scheduleContinuation,
  }) : assert(maxEventsPerTurn > 0),
       _scheduleInitial = scheduleInitial ?? scheduleMicrotask,
       _scheduleContinuation = scheduleContinuation ?? _scheduleEventTurn;

  final void Function(E event) onEvent;
  final int maxEventsPerTurn;
  final void Function(void Function() callback) _scheduleInitial;
  final void Function(void Function() callback) _scheduleContinuation;

  final Queue<E> _queue = Queue<E>();
  bool _drainScheduled = false;
  bool _draining = false;
  bool _accepting = true;
  bool _closed = false;
  Completer<void>? _closeCompleter;
  int _yieldCount = 0;
  int _deliveredEvents = 0;
  int _batchCount = 0;
  int _maxQueueDepth = 0;

  int get pendingCount => _queue.length;

  BoundedEventDispatcherDiagnostics get diagnostics =>
      BoundedEventDispatcherDiagnostics(
        deliveredEvents: _deliveredEvents,
        batchCount: _batchCount,
        yieldCount: _yieldCount,
        currentQueueDepth: _queue.length,
        maxQueueDepth: _maxQueueDepth,
      );

  void add(E event) {
    if (!_accepting || _closed) {
      return;
    }
    _queue.add(event);
    if (_queue.length > _maxQueueDepth) {
      _maxQueueDepth = _queue.length;
    }
    _scheduleDrain();
  }

  /// 立即按 FIFO 排空，主要用于显式同步边界和确定性测试。
  void flush() {
    if (_closed) {
      return;
    }
    _drainScheduled = false;
    if (_queue.isNotEmpty) {
      _batchCount += 1;
    }
    while (_queue.isNotEmpty) {
      _deliver(_queue.removeFirst());
    }
    _completeCloseIfReady();
  }

  /// 停止接收新事件，并选择有界 drain 或立即 clear。
  Future<void> close({bool drain = true}) {
    final existing = _closeCompleter;
    if (existing != null) {
      return existing.future;
    }
    final completer = Completer<void>();
    _closeCompleter = completer;
    _accepting = false;
    if (!drain) {
      _queue.clear();
      _finishClose();
      return completer.future;
    }
    if (_queue.isEmpty && !_draining) {
      _finishClose();
      return completer.future;
    }
    _scheduleDrain();
    return completer.future;
  }

  /// 同步停止并清空队列；已排入 scheduler 的回调会安全失效。
  void dispose() {
    unawaited(close(drain: false));
  }

  void _scheduleDrain({bool continuation = false}) {
    if (_closed || _drainScheduled || _draining) {
      return;
    }
    _drainScheduled = true;
    final schedule = continuation ? _scheduleContinuation : _scheduleInitial;
    schedule(() {
      if (_closed) {
        return;
      }
      _drainScheduled = false;
      _drainOneTurn();
    });
  }

  void _drainOneTurn() {
    if (_closed || _draining) {
      return;
    }
    _draining = true;
    try {
      if (_queue.isNotEmpty) {
        _batchCount += 1;
      }
      var delivered = 0;
      while (_queue.isNotEmpty && delivered < maxEventsPerTurn) {
        _deliver(_queue.removeFirst());
        delivered += 1;
      }
    } finally {
      _draining = false;
    }
    if (_queue.isNotEmpty) {
      _yieldCount += 1;
      _scheduleDrain(continuation: true);
      return;
    }
    _completeCloseIfReady();
  }

  void _deliver(E event) {
    _deliveredEvents += 1;
    onEvent(event);
  }

  void _completeCloseIfReady() {
    if (!_accepting && _queue.isEmpty && !_draining) {
      _finishClose();
    }
  }

  void _finishClose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _drainScheduled = false;
    _closeCompleter?.complete();
  }
}

void _scheduleEventTurn(void Function() callback) {
  Timer.run(callback);
}
