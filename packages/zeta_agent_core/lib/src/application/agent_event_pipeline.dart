import 'dart:async';

import 'package:zeta_agent_core/src/application/agent_event_coalescing_policy.dart';
import 'package:zeta_agent_core/src/application/agent_provider_event_listener_gate.dart';
import 'package:zeta_agent_core/src/application/bounded_event_dispatcher.dart';
import 'package:zeta_agent_core/src/application/coalescing_event_buffer.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

/// Pipeline 选择 drain 或 clear 时使用的非敏感关闭原因。
enum AgentEventPipelineCloseReason {
  replaced,
  threadSwitch,
  sourceDone,
  disposed,
}

/// Pipeline 的脱敏只读诊断。
///
/// 仅包含计数、队列深度和关闭原因；不记录正文、raw payload、凭证或源码内容。
final class AgentEventPipelineDiagnostics {
  const AgentEventPipelineDiagnostics({
    required this.receivedEvents,
    required this.acceptedEvents,
    required this.rejectedStaleEvents,
    required this.sourceErrorCount,
    required this.sourceDoneCount,
    required this.buffer,
    required this.dispatcher,
    required this.closeReason,
  });

  final int receivedEvents;
  final int acceptedEvents;
  final int rejectedStaleEvents;
  final int sourceErrorCount;
  final int sourceDoneCount;
  final CoalescingEventBufferDiagnostics buffer;
  final BoundedEventDispatcherDiagnostics dispatcher;
  final AgentEventPipelineCloseReason? closeReason;
}

/// Agent Provider 事件资源的唯一所有者。
///
/// 每个实例拥有 subscription、listener scope、coalescing buffer 和 bounded
/// dispatcher。替换实例共享同一个 gate，并先激活新 generation，再关闭旧资源。
final class AgentEventPipeline {
  factory AgentEventPipeline({
    required Stream<AgentEvent> source,
    required String providerId,
    required String? threadId,
    required AgentRuntimeScope? runtimeScope,
    required AgentRuntimeScope? Function() currentRuntimeScope,
    required bool Function(AgentEvent event) allowDetachedEvent,
    required void Function(AgentEvent event) processEvent,
    required void Function(Object error, StackTrace stackTrace) onSourceError,
    required void Function() onDone,
    AgentEventPipeline? replaces,
    EventCoalescingPolicy<AgentEvent, AgentEventKey> policy =
        const AgentEventCoalescingPolicy(),
    int maxPendingKeys = 512,
    int maxEventsPerTurn = kDefaultMaxEventsPerTurn,
    void Function(int pendingKeyCount)? onBackpressure,
    void Function(void Function() callback)? scheduleBufferFlush,
    void Function(void Function() callback)? scheduleInitialDispatch,
    void Function(void Function() callback)? scheduleContinuationDispatch,
  }) {
    return AgentEventPipeline._(
      source: source,
      providerId: providerId,
      threadId: threadId,
      runtimeScope: runtimeScope,
      currentRuntimeScope: currentRuntimeScope,
      allowDetachedEvent: allowDetachedEvent,
      processEvent: processEvent,
      onSourceError: onSourceError,
      onDone: onDone,
      replaces: replaces,
      listenerGate: replaces?._listenerGate ?? AgentProviderEventListenerGate(),
      policy: policy,
      maxPendingKeys: maxPendingKeys,
      maxEventsPerTurn: maxEventsPerTurn,
      onBackpressure: onBackpressure,
      scheduleBufferFlush: scheduleBufferFlush,
      scheduleInitialDispatch: scheduleInitialDispatch,
      scheduleContinuationDispatch: scheduleContinuationDispatch,
    );
  }

  AgentEventPipeline._({
    required Stream<AgentEvent> source,
    required String providerId,
    required String? threadId,
    required AgentRuntimeScope? runtimeScope,
    required this._currentRuntimeScope,
    required this._allowDetachedEvent,
    required this._processEvent,
    required this._onSourceError,
    required this._onDone,
    required this._listenerGate,
    required EventCoalescingPolicy<AgentEvent, AgentEventKey> policy,
    required int maxPendingKeys,
    required int maxEventsPerTurn,
    required void Function(int pendingKeyCount)? onBackpressure,
    required void Function(void Function() callback)? scheduleBufferFlush,
    required void Function(void Function() callback)? scheduleInitialDispatch,
    required void Function(void Function() callback)?
    scheduleContinuationDispatch,
    required AgentEventPipeline? replaces,
  }) {
    _listenerScope = _listenerGate.activate(
      providerId: providerId,
      threadId: threadId,
      runtimeScope: runtimeScope,
    );
    _dispatcher = BoundedEventDispatcher<AgentEvent>(
      onEvent: _dispatch,
      maxEventsPerTurn: maxEventsPerTurn,
      scheduleInitial: scheduleInitialDispatch,
      scheduleContinuation: scheduleContinuationDispatch,
    );
    _buffer = CoalescingEventBuffer<AgentEvent, AgentEventKey>(
      policy: policy,
      onEmit: _dispatcher.add,
      maxPendingKeys: maxPendingKeys,
      onBackpressure: onBackpressure,
      scheduleFlush: scheduleBufferFlush,
    );
    _subscription = source.listen(
      _handleSourceEvent,
      onError: _handleSourceError,
      onDone: _handleSourceDone,
    );

    // activate 已使旧 scope 失效；旧 cancel 无需阻塞新事件入口。
    if (replaces != null) {
      unawaited(replaces.close(reason: AgentEventPipelineCloseReason.replaced));
    }
  }

  final AgentProviderEventListenerGate _listenerGate;
  late final AgentProviderEventListenerScope _listenerScope;
  final AgentRuntimeScope? Function() _currentRuntimeScope;
  final bool Function(AgentEvent event) _allowDetachedEvent;
  final void Function(AgentEvent event) _processEvent;
  final void Function(Object error, StackTrace stackTrace) _onSourceError;
  final void Function() _onDone;
  final Completer<void> _doneCompleter = Completer<void>();

  late final CoalescingEventBuffer<AgentEvent, AgentEventKey> _buffer;
  late final BoundedEventDispatcher<AgentEvent> _dispatcher;
  StreamSubscription<AgentEvent>? _subscription;
  Completer<void>? _closeCompleter;
  AgentEventPipelineCloseReason? _closeReason;
  bool _accepting = true;
  bool _disposed = false;
  bool _sourceDoneMayNotify = false;
  int _receivedEvents = 0;
  int _acceptedEvents = 0;
  int _rejectedStaleEvents = 0;
  int _sourceErrorCount = 0;
  int _sourceDoneCount = 0;

  /// 当前可用于 event/effect 处理的 listener scope。
  ///
  /// 自然 onDone 已使 gate 失效，但有界 drain 期间仍向已接受事件提供原 scope；
  /// 一旦出现新 generation 或完成 dispose，立即返回 null。
  AgentProviderEventListenerScope? get currentListenerScope {
    final isActive = _accepting && _listenerGate.isCurrent(_listenerScope);
    final isCurrentSourceDrain =
        !_disposed &&
        _closeReason == AgentEventPipelineCloseReason.sourceDone &&
        _sourceDoneMayNotify &&
        _listenerGate.isLatestGeneration(_listenerScope);
    if (!isActive && !isCurrentSourceDrain) {
      return null;
    }
    return _listenerScope;
  }

  /// Pipeline 完成 close/drain/dispose 的 Future。
  Future<void> get done => _doneCompleter.future;

  AgentEventPipelineDiagnostics get diagnostics =>
      AgentEventPipelineDiagnostics(
        receivedEvents: _receivedEvents,
        acceptedEvents: _acceptedEvents,
        rejectedStaleEvents: _rejectedStaleEvents,
        sourceErrorCount: _sourceErrorCount,
        sourceDoneCount: _sourceDoneCount,
        buffer: _buffer.diagnostics,
        dispatcher: _dispatcher.diagnostics,
        closeReason: _closeReason,
      );

  /// 判断该实例是否仍绑定指定 Provider/thread/runtime。
  bool matches({
    required String providerId,
    required String? threadId,
    required AgentRuntimeScope? runtimeScope,
  }) {
    if (!_accepting ||
        !_listenerGate.isCurrent(_listenerScope) ||
        _listenerScope.providerId != providerId ||
        _listenerScope.threadId != threadId) {
      return false;
    }
    final expectedRuntime = _listenerScope.runtimeScope;
    return expectedRuntime == null || expectedRuntime == runtimeScope;
  }

  /// 集中关闭事件资源。
  ///
  /// scope 会同步先失效，然后停止接收并发起 source cancel。Thread 切换/替换/
  /// dispose 清空旧普通事件；只有当前 generation 的自然 onDone 会有界 drain。
  Future<void> close({
    AgentEventPipelineCloseReason reason =
        AgentEventPipelineCloseReason.disposed,
  }) {
    final existing = _closeCompleter;
    if (existing != null) {
      return existing.future;
    }
    final completer = Completer<void>();
    _closeCompleter = completer;
    _closeReason = reason;

    final mayFinishSource =
        reason == AgentEventPipelineCloseReason.sourceDone &&
        _accepting &&
        _listenerGate.accepts(
          _listenerScope,
          currentRuntimeScope: _currentRuntimeScope(),
          allowDetachedRuntime: true,
        );
    final releasedCurrentScope = _listenerGate.release(_listenerScope);
    _sourceDoneMayNotify = mayFinishSource && releasedCurrentScope;
    _accepting = false;

    final subscription = _subscription;
    _subscription = null;
    Future<void> cancelFuture;
    try {
      cancelFuture = subscription?.cancel() ?? Future<void>.value();
    } catch (error, stackTrace) {
      _reportSourceError(error, stackTrace);
      cancelFuture = Future<void>.value();
    }

    final dispatcherClose = _sourceDoneMayNotify
        ? _closeWithDrain()
        : _closeWithClear();
    unawaited(_finishClose(cancelFuture, dispatcherClose, completer));
    return completer.future;
  }

  Future<void> _closeWithDrain() {
    _buffer.dispose(flushPending: true);
    return _dispatcher.close();
  }

  Future<void> _closeWithClear() {
    _buffer.dispose();
    return _dispatcher.close(drain: false);
  }

  Future<void> _finishClose(
    Future<void> cancelFuture,
    Future<void> dispatcherClose,
    Completer<void> completer,
  ) async {
    try {
      await cancelFuture;
    } catch (error, stackTrace) {
      _reportSourceError(error, stackTrace);
    }
    await dispatcherClose;
    _disposed = true;

    final notifyDone =
        _sourceDoneMayNotify &&
        _listenerGate.isLatestGeneration(_listenerScope);
    if (notifyDone) {
      _onDone();
    }
    if (!completer.isCompleted) {
      completer.complete();
    }
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  void _handleSourceEvent(AgentEvent event) {
    _receivedEvents += 1;
    if (!_accepting || !_accepts(event)) {
      _rejectedStaleEvents += 1;
      return;
    }
    _buffer.add(event);
  }

  void _dispatch(AgentEvent event) {
    if (_disposed) {
      return;
    }
    if (_closeReason == AgentEventPipelineCloseReason.sourceDone) {
      if (!_sourceDoneMayNotify ||
          !_listenerGate.isLatestGeneration(_listenerScope)) {
        _rejectedStaleEvents += 1;
        return;
      }
    } else if (!_accepting || !_accepts(event)) {
      _rejectedStaleEvents += 1;
      return;
    }
    _acceptedEvents += 1;
    _processEvent(event);
  }

  bool _accepts(AgentEvent event) {
    return _listenerGate.accepts(
      _listenerScope,
      currentRuntimeScope: _currentRuntimeScope(),
      allowDetachedRuntime: _allowDetachedEvent(event),
    );
  }

  void _handleSourceError(Object error, StackTrace stackTrace) {
    if (!_accepting ||
        !_listenerGate.accepts(
          _listenerScope,
          currentRuntimeScope: _currentRuntimeScope(),
          allowDetachedRuntime: true,
        )) {
      return;
    }
    _reportSourceError(error, stackTrace);
  }

  void _reportSourceError(Object error, StackTrace stackTrace) {
    _sourceErrorCount += 1;
    _onSourceError(error, stackTrace);
  }

  void _handleSourceDone() {
    _sourceDoneCount += 1;
    unawaited(close(reason: AgentEventPipelineCloseReason.sourceDone));
  }
}
