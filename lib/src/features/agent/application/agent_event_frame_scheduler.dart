import 'dart:async';
import 'dart:collection';

import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 默认每 event-loop turn 最多 apply 的已合并事件数。
///
/// 事件已经过 [AgentEventStreamBuffer] 合并，默认值兼顾批量吞吐与界面响应。
const int kAgentEventMaxPerTurn = 64;

/// [AgentEventFrameScheduler] 的只读诊断快照。
///
/// 快照仅记录吞吐和队列深度，不持有事件或任何事件内容。
final class AgentEventFrameSchedulerDiagnostics {
  const AgentEventFrameSchedulerDiagnostics({
    required this.deliveredEvents,
    required this.batchCount,
    required this.yieldCount,
    required this.currentQueueDepth,
    required this.maxQueueDepth,
  });

  /// 已调用下游 [AgentEventFrameScheduler.onEvent] 的事件数。
  final int deliveredEvents;

  /// 实际投递过至少一个事件的 drain/flush 批次数。
  final int batchCount;

  /// 有界批次结束后仍有排队事件、因此续排下一 event-loop turn 的次数。
  final int yieldCount;

  /// 获取快照时尚未投递的事件数。
  final int currentQueueDepth;

  /// 本实例生命周期内观察到的最大队列深度。
  final int maxQueueDepth;
}

/// Application 层的有界事件 drain 调度器。
///
/// 位于 EventBuffer → ViewModel 之间：
/// - [add] 只入队，并在当前同步栈结束后用 microtask 开首批 drain（使
///   `EventBuffer.flush` 的 for 循环先把整批入队再投递）。
/// - 每个 event-loop turn 最多 [maxEventsPerTurn] 条；超额续排下一条 event
///   消息，让输入、Timer 和绘制事件有机会在批次之间执行。
/// - 顺序 FIFO，不重排、不合并。
/// - [flush] 立即排空（忽略 per-turn 上限）。
final class AgentEventFrameScheduler {
  AgentEventFrameScheduler({
    required this.onEvent,
    this.maxEventsPerTurn = kAgentEventMaxPerTurn,
    void Function(void Function() callback)? scheduleTurn,
  }) : assert(maxEventsPerTurn > 0),
       _scheduleInitialTurn = scheduleTurn ?? scheduleMicrotask,
       _scheduleContinuationTurn = scheduleTurn ?? _scheduleEventTurn;

  /// 下游消费者（通常为 ViewModel._handleEvent）。
  final void Function(AgentEvent event) onEvent;

  /// 每个 event-loop turn 最多投递的事件数。
  final int maxEventsPerTurn;

  final void Function(void Function() callback) _scheduleInitialTurn;
  final void Function(void Function() callback) _scheduleContinuationTurn;

  final Queue<AgentEvent> _queue = Queue<AgentEvent>();
  bool _drainScheduled = false;
  bool _draining = false;
  bool _disposed = false;
  int _yieldCount = 0;
  int _deliveredEvents = 0;
  int _batchCount = 0;
  int _maxQueueDepth = 0;

  /// 当前排队未投递事件数（诊断用）。
  int get pendingCount => _queue.length;

  /// 诊断：触发「跨 turn 续 drain」的次数。
  int get debugYieldCount => _yieldCount;

  /// 诊断：实际调用 [onEvent] 的次数。
  int get debugDeliveredCount => _deliveredEvents;

  /// 返回与可变队列隔离的诊断快照。
  AgentEventFrameSchedulerDiagnostics get diagnostics =>
      AgentEventFrameSchedulerDiagnostics(
        deliveredEvents: _deliveredEvents,
        batchCount: _batchCount,
        yieldCount: _yieldCount,
        currentQueueDepth: _queue.length,
        maxQueueDepth: _maxQueueDepth,
      );

  void add(AgentEvent event) {
    if (_disposed) {
      return;
    }
    _queue.add(event);
    if (_queue.length > _maxQueueDepth) {
      _maxQueueDepth = _queue.length;
    }
    _scheduleDrain();
  }

  /// 立即按 FIFO 投递全部排队事件（忽略 per-turn 上限）。
  void flush() {
    if (_disposed) {
      return;
    }
    _drainScheduled = false;
    if (_queue.isNotEmpty) {
      _batchCount += 1;
    }
    while (_queue.isNotEmpty) {
      _deliver(_queue.removeFirst());
    }
  }

  /// 停止调度器。
  ///
  /// [flushPending] 为 true 时先投递剩余事件；listener 切换场景应传 false
  /// 以丢弃旧代数增量（与 EventBuffer.dispose 一致）。
  void dispose({bool flushPending = false}) {
    if (_disposed) {
      return;
    }
    if (flushPending) {
      flush();
    } else {
      _queue.clear();
    }
    _drainScheduled = false;
    _disposed = true;
  }

  void _scheduleDrain({bool continuation = false}) {
    if (_disposed || _drainScheduled || _draining) {
      return;
    }
    _drainScheduled = true;
    final schedule = continuation
        ? _scheduleContinuationTurn
        : _scheduleInitialTurn;
    schedule(() {
      if (_disposed) {
        return;
      }
      _drainScheduled = false;
      _drainOneTurn();
    });
  }

  void _drainOneTurn() {
    if (_disposed || _draining) {
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
    }
  }

  void _deliver(AgentEvent event) {
    _deliveredEvents += 1;
    onEvent(event);
  }
}

void _scheduleEventTurn(void Function() callback) {
  Timer.run(callback);
}
