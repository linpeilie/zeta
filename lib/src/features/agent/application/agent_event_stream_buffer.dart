import 'dart:async';

import 'package:zeta/src/features/agent/domain/agent_models.dart';

typedef _AgentEventKey = ({
  String kind,
  String? sessionId,
  String? turnId,
  String itemId,
  String? detail,
});

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

  int get pendingEventCount => _pending.length;

  void add(AgentEvent event) {
    if (_disposed) {
      return;
    }
    final key = _coalescingKey(event);
    if (key == null) {
      flush();
      onEvent(event);
      return;
    }

    final previous = _pending[key];
    _pending[key] = previous == null ? event : _merge(previous, event);
    if (_pending.length >= maxPendingEvents) {
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
      detail: '${event.role.name}:${event.phase?.name}',
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
