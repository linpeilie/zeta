import 'dart:async';

import 'package:zeta/src/features/agent/domain/agent_models.dart';

typedef _AgentEventKey = ({
  String kind,
  String? sessionId,
  String? turnId,
  String itemId,
  String? detail,
});

/// [AgentEventStreamBuffer] 的只读诊断快照。
///
/// 快照只包含计数和队列深度，不保留事件、正文、Provider payload 或 scope 标识。
final class AgentEventStreamBufferDiagnostics {
  const AgentEventStreamBufferDiagnostics({
    required this.receivedEvents,
    required this.coalescedEvents,
    required this.barrierOrDirectPassThroughEvents,
    required this.backpressureFlushes,
    required this.currentPendingKeys,
    required this.maxPendingKeys,
  });

  /// 进入缓冲器处理的事件数；dispose 后被忽略的调用不计入。
  final int receivedEvents;

  /// 与同一规范化 key 的待处理事件合并或替换的输入事件数。
  final int coalescedEvents;

  /// 走现有非合并分支、先 flush 再直接透传的事件数。
  final int barrierOrDirectPassThroughEvents;

  /// 达到 [AgentEventStreamBuffer.maxPendingEvents] 后触发 flush 的次数。
  final int backpressureFlushes;

  /// 获取快照时尚未发布的合并 key 数。
  final int currentPendingKeys;

  /// 本实例生命周期内同时存在过的最大待处理 key 数。
  final int maxPendingKeys;
}

/// Application 层的 Provider 高频事件合并器。
///
/// Transport 和 Provider mapper 仍逐条消费全部协议消息；只有进入 UI 投影前，才按
/// `(threadId, turnId, itemId, eventKind)` 合并可替代事件。任何非合并事件都会先
/// flush 已缓存增量，因此终态、审批、错误和连接状态不会越过此前流式内容。
final class AgentEventStreamBuffer {
  AgentEventStreamBuffer({
    required this.onEvent,
    this.maxPendingEvents = 512,
    this.onBackpressure,
  }) : assert(maxPendingEvents > 0);

  /// 合并后事件的下游消费者。
  final void Function(AgentEvent event) onEvent;
  final int maxPendingEvents;

  /// 缓冲键数量达到上限时触发；只暴露计数，不包含消息正文。
  final void Function(int pendingEventCount)? onBackpressure;

  final Map<_AgentEventKey, AgentEvent> _pending =
      <_AgentEventKey, AgentEvent>{};
  bool _flushScheduled = false;
  bool _disposed = false;
  int _receivedEvents = 0;
  int _coalescedEvents = 0;
  int _barrierOrDirectPassThroughEvents = 0;
  int _backpressureFlushes = 0;
  int _maxPendingKeys = 0;

  int get pendingEventCount => _pending.length;

  /// 返回与可变缓冲状态隔离的诊断快照。
  AgentEventStreamBufferDiagnostics get diagnostics =>
      AgentEventStreamBufferDiagnostics(
        receivedEvents: _receivedEvents,
        coalescedEvents: _coalescedEvents,
        barrierOrDirectPassThroughEvents: _barrierOrDirectPassThroughEvents,
        backpressureFlushes: _backpressureFlushes,
        currentPendingKeys: _pending.length,
        maxPendingKeys: _maxPendingKeys,
      );

  void add(AgentEvent event) {
    if (_disposed) {
      return;
    }
    _receivedEvents += 1;
    final key = _coalescingKey(event);
    if (key == null) {
      _barrierOrDirectPassThroughEvents += 1;
      flush();
      onEvent(event);
      return;
    }

    final previous = _pending[key];
    if (previous != null) {
      _coalescedEvents += 1;
    }
    _pending[key] = previous == null ? event : _merge(previous, event);
    if (_pending.length > _maxPendingKeys) {
      _maxPendingKeys = _pending.length;
    }
    if (_pending.length >= maxPendingEvents) {
      _backpressureFlushes += 1;
      onBackpressure?.call(_pending.length);
      flush();
      return;
    }
    _scheduleFlush();
  }

  /// 立即按首次到达顺序发布当前批次。
  void flush() {
    if (_disposed || _pending.isEmpty) {
      _flushScheduled = false;
      return;
    }
    final events = _pending.values.toList(growable: false);
    _pending.clear();
    _flushScheduled = false;
    for (final event in events) {
      onEvent(event);
    }
  }

  /// 停止缓冲器；listener 切换默认丢弃旧代数尚未发布的增量。
  void dispose({bool flushPending = false}) {
    if (_disposed) {
      return;
    }
    if (flushPending) {
      flush();
    } else {
      _pending.clear();
    }
    _flushScheduled = false;
    _disposed = true;
  }

  void _scheduleFlush() {
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    scheduleMicrotask(() {
      if (!_disposed && _flushScheduled) {
        flush();
      }
    });
  }
}

_AgentEventKey? _coalescingKey(AgentEvent event) {
  return switch (event) {
    AgentMessageDeltaEvent() => (
      kind: 'messageDelta',
      sessionId: event.sessionId,
      turnId: event.turnId,
      itemId: event.messageId,
      detail: '${event.role.name}:${event.kind.name}:${event.phase?.name}',
    ),
    AgentReasoningDeltaEvent() => (
      kind: 'reasoningDelta',
      sessionId: event.sessionId,
      turnId: event.turnId,
      itemId: event.itemId,
      detail: '${event.kind.name}:${event.contentIndex}:${event.summaryIndex}',
    ),
    AgentTokenUsageEvent() => (
      kind: 'tokenSnapshot',
      sessionId: event.sessionId,
      turnId: event.turnId,
      itemId: '<turn>',
      detail: event.isSessionCumulative.toString(),
    ),
    AgentContextWindowUsageEvent() => (
      kind: 'contextWindowSnapshot',
      sessionId: event.sessionId,
      turnId: event.turnId,
      itemId: '<turn>',
      detail: null,
    ),
    AgentTurnDiffEvent() => (
      kind: 'diffSnapshot',
      sessionId: event.sessionId,
      turnId: event.turnId,
      itemId: '<turn>',
      detail: null,
    ),
    AgentToolCallEvent() when !event.toolCall.isTerminalStatus => (
      kind: 'toolProgress',
      sessionId: event.toolCall.sessionId,
      turnId: event.toolCall.turnId,
      itemId: event.toolCall.id,
      detail: null,
    ),
    _ => null,
  };
}

AgentEvent _merge(AgentEvent previous, AgentEvent next) {
  return switch ((previous, next)) {
    (AgentMessageDeltaEvent previous, AgentMessageDeltaEvent next) =>
      AgentMessageDeltaEvent(
        messageId: next.messageId,
        sourceMessageId: next.sourceMessageId ?? previous.sourceMessageId,
        kind: next.kind,
        delta: '${previous.delta}${next.delta}',
        role: next.role,
        phase: next.phase ?? previous.phase,
        status: next.status ?? previous.status,
        duration: next.duration ?? previous.duration,
        raw: next.raw,
        sessionId: next.sessionId ?? previous.sessionId,
        turnId: next.turnId ?? previous.turnId,
      ),
    (AgentReasoningDeltaEvent previous, AgentReasoningDeltaEvent next) =>
      AgentReasoningDeltaEvent(
        itemId: next.itemId,
        sourceItemId: next.sourceItemId ?? previous.sourceItemId,
        kind: next.kind,
        delta: '${previous.delta}${next.delta}',
        contentIndex: next.contentIndex ?? previous.contentIndex,
        summaryIndex: next.summaryIndex ?? previous.summaryIndex,
        sessionId: next.sessionId ?? previous.sessionId,
        turnId: next.turnId ?? previous.turnId,
        raw: next.raw,
      ),
    (AgentToolCallEvent previous, AgentToolCallEvent next) =>
      _mergeToolProgress(previous, next),
    _ => next,
  };
}

AgentToolCallEvent _mergeToolProgress(
  AgentToolCallEvent previous,
  AgentToolCallEvent next,
) {
  final previousCall = previous.toolCall;
  final nextCall = next.toolCall;
  final shouldAppend =
      previousCall.raw['_progressAppend'] == true &&
      nextCall.raw['_progressAppend'] == true;
  if (!shouldAppend) {
    return next;
  }
  return AgentToolCallEvent(
    nextCall.copyWith(
      content: _appendProgress(previousCall.content, nextCall.content),
      raw: <String, Object?>{...previousCall.raw, ...nextCall.raw},
    ),
  );
}

String? _appendProgress(String? previous, String? next) {
  if (next == null || next.isEmpty) {
    return previous;
  }
  if (previous == null || previous.isEmpty) {
    return next;
  }
  if (previous == next ||
      previous.endsWith('\n$next') ||
      previous.endsWith(next)) {
    return previous;
  }
  return '$previous\n$next';
}
