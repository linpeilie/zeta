import 'dart:async';
import 'dart:collection';

// Package-internal pipeline API; subscription ownership is released by close().
// ignore_for_file: cancel_subscriptions, prefer_initializing_formals
// ignore_for_file: public_member_api_docs

import 'package:agent_provider_contracts/agent_provider_contracts.dart';

typedef _EventKey = ({
  String kind,
  String? sessionId,
  String? turnId,
  String itemId,
  String? detail,
});

final class EventPipelineDiagnostics {
  const EventPipelineDiagnostics({
    required this.receivedEvents,
    required this.acceptedEvents,
    required this.coalescedEvents,
    required this.rejectedStaleEvents,
    required this.backpressureFlushes,
    required this.maxQueueDepth,
  });

  final int receivedEvents;
  final int acceptedEvents;
  final int coalescedEvents;
  final int rejectedStaleEvents;
  final int backpressureFlushes;
  final int maxQueueDepth;
}

/// Provider-event pipeline with keyed coalescing and bounded event-loop turns.
final class ConversationEventPipeline {
  ConversationEventPipeline({
    required Stream<AgentEvent> source,
    required bool Function() isCurrent,
    required void Function(AgentEvent event) onEvent,
    required void Function(Object error, StackTrace stackTrace) onError,
    void Function()? onDone,
    this.maxPendingKeys = 512,
    this.maxEventsPerTurn = 64,
  }) : assert(maxPendingKeys > 0, 'maxPendingKeys must be positive'),
       assert(maxEventsPerTurn > 0, 'maxEventsPerTurn must be positive'),
       _isCurrent = isCurrent,
       _onEvent = onEvent,
       _onError = onError,
       _onDone = onDone {
    _subscription = source.listen(
      _receive,
      onError: _sourceError,
      onDone: _sourceDone,
    );
  }

  final int maxPendingKeys;
  final int maxEventsPerTurn;
  final bool Function() _isCurrent;
  final void Function(AgentEvent event) _onEvent;
  final void Function(Object error, StackTrace stackTrace) _onError;
  final void Function()? _onDone;
  final LinkedHashMap<_EventKey, AgentEvent> _pending =
      LinkedHashMap<_EventKey, AgentEvent>();
  final Queue<AgentEvent> _queue = Queue<AgentEvent>();

  StreamSubscription<AgentEvent>? _subscription;
  Completer<void>? _closeCompleter;
  bool _flushScheduled = false;
  bool _drainScheduled = false;
  bool _draining = false;
  bool _accepting = true;
  bool _closed = false;
  int _receivedEvents = 0;
  int _acceptedEvents = 0;
  int _coalescedEvents = 0;
  int _rejectedStaleEvents = 0;
  int _backpressureFlushes = 0;
  int _maxQueueDepth = 0;

  EventPipelineDiagnostics get diagnostics => EventPipelineDiagnostics(
    receivedEvents: _receivedEvents,
    acceptedEvents: _acceptedEvents,
    coalescedEvents: _coalescedEvents,
    rejectedStaleEvents: _rejectedStaleEvents,
    backpressureFlushes: _backpressureFlushes,
    maxQueueDepth: _maxQueueDepth,
  );

  void _receive(AgentEvent event) {
    _receivedEvents += 1;
    if (!_accepting || !_isCurrent()) {
      _rejectedStaleEvents += 1;
      return;
    }
    final key = _keyOf(event);
    if (key == null) {
      _flushPending();
      _enqueue(event);
      return;
    }
    final previous = _pending[key];
    if (previous != null) {
      _coalescedEvents += 1;
      _pending[key] = _merge(previous, event);
    } else {
      _pending[key] = event;
    }
    if (_pending.length >= maxPendingKeys) {
      _backpressureFlushes += 1;
      _flushPending();
      return;
    }
    if (!_flushScheduled) {
      _flushScheduled = true;
      scheduleMicrotask(_flushPending);
    }
  }

  void _flushPending() {
    _flushScheduled = false;
    if (_closed || _pending.isEmpty) {
      return;
    }
    final events = _pending.values.toList(growable: false);
    _pending.clear();
    events.forEach(_enqueue);
  }

  void _enqueue(AgentEvent event) {
    if (_closed) {
      return;
    }
    _queue.add(event);
    if (_queue.length > _maxQueueDepth) {
      _maxQueueDepth = _queue.length;
    }
    _scheduleDrain();
  }

  void _scheduleDrain({bool continuation = false}) {
    if (_closed || _drainScheduled || _draining) {
      return;
    }
    _drainScheduled = true;
    void callback() {
      _drainScheduled = false;
      _drainOneTurn();
    }

    if (continuation) {
      Timer.run(callback);
    } else {
      scheduleMicrotask(callback);
    }
  }

  void _drainOneTurn() {
    if (_closed || _draining) {
      return;
    }
    _draining = true;
    var delivered = 0;
    try {
      while (_queue.isNotEmpty && delivered < maxEventsPerTurn) {
        final event = _queue.removeFirst();
        if (!_isCurrent()) {
          _rejectedStaleEvents += 1;
        } else {
          _acceptedEvents += 1;
          _onEvent(event);
        }
        delivered += 1;
      }
    } finally {
      _draining = false;
    }
    if (_queue.isNotEmpty) {
      _scheduleDrain(continuation: true);
    } else {
      _finishCloseIfReady();
    }
  }

  void _sourceError(Object error, StackTrace stackTrace) {
    if (_accepting && _isCurrent()) {
      _onError(error, stackTrace);
    }
  }

  void _sourceDone() {
    final notify = _isCurrent();
    unawaited(
      close(drain: notify).whenComplete(() {
        if (notify && _isCurrent()) {
          _onDone?.call();
        }
      }),
    );
  }

  Future<void> close({bool drain = false}) {
    final existing = _closeCompleter;
    if (existing != null) {
      return existing.future;
    }
    final completer = Completer<void>();
    _closeCompleter = completer;
    _accepting = false;
    final subscription = _subscription;
    _subscription = null;
    Future<void> cancel;
    try {
      cancel = subscription?.cancel() ?? Future<void>.value();
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
      cancel = Future<void>.value();
    }
    if (drain) {
      _flushPending();
    } else {
      _pending.clear();
      _queue.clear();
    }
    unawaited(_finishClose(cancel));
    return completer.future;
  }

  Future<void> _finishClose(Future<void> cancel) async {
    try {
      await cancel;
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
    _finishCloseIfReady();
  }

  void _finishCloseIfReady() {
    if (_closed || _accepting || _queue.isNotEmpty || _draining) {
      return;
    }
    _closed = true;
    _closeCompleter?.complete();
  }
}

_EventKey? _keyOf(AgentEvent event) {
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
      kind: 'tokenUsage',
      sessionId: event.sessionId,
      turnId: event.turnId,
      itemId: '<turn>',
      detail: event.isSessionCumulative.toString(),
    ),
    AgentContextWindowUsageEvent() => (
      kind: 'contextWindow',
      sessionId: event.sessionId,
      turnId: event.turnId,
      itemId: '<turn>',
      detail: null,
    ),
    AgentTurnFileChangesEvent() => (
      kind: 'fileChanges',
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
    (
      final AgentMessageDeltaEvent previous,
      final AgentMessageDeltaEvent next,
    ) =>
      AgentMessageDeltaEvent(
        messageId: next.messageId,
        delta: '${previous.delta}${next.delta}',
        role: next.role,
        sourceMessageId: next.sourceMessageId ?? previous.sourceMessageId,
        kind: next.kind,
        phase: next.phase ?? previous.phase,
        status: next.status ?? previous.status,
        duration: next.duration ?? previous.duration,
        sessionId: next.sessionId ?? previous.sessionId,
        turnId: next.turnId ?? previous.turnId,
        raw: next.raw,
      ),
    (
      final AgentReasoningDeltaEvent previous,
      final AgentReasoningDeltaEvent next,
    ) =>
      AgentReasoningDeltaEvent(
        itemId: next.itemId,
        kind: next.kind,
        sourceItemId: next.sourceItemId ?? previous.sourceItemId,
        delta: '${previous.delta}${next.delta}',
        contentIndex: next.contentIndex ?? previous.contentIndex,
        summaryIndex: next.summaryIndex ?? previous.summaryIndex,
        sessionId: next.sessionId ?? previous.sessionId,
        turnId: next.turnId ?? previous.turnId,
        raw: next.raw,
      ),
    (final AgentToolCallEvent previous, final AgentToolCallEvent next) =>
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
  if (previousCall.raw['_progressAppend'] != true ||
      nextCall.raw['_progressAppend'] != true) {
    return next;
  }
  final previousContent = previousCall.content;
  final nextContent = nextCall.content;
  String? content;
  if (nextContent == null || nextContent.isEmpty) {
    content = previousContent;
  } else if (previousContent == null || previousContent.isEmpty) {
    content = nextContent;
  } else if (previousContent == nextContent ||
      previousContent.endsWith('\n$nextContent') ||
      previousContent.endsWith(nextContent)) {
    content = previousContent;
  } else {
    content = '$previousContent\n$nextContent';
  }
  return AgentToolCallEvent(
    nextCall.copyWith(
      content: content,
      raw: <String, Object?>{...previousCall.raw, ...nextCall.raw},
    ),
  );
}
