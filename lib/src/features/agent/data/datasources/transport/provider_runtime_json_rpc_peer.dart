import 'dart:async';

import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/domain/agent_runtime_models.dart';

/// Provider 已进入关闭阶段或请求属于旧连接。
class ProviderConnectionClosedException implements Exception {
  const ProviderConnectionClosedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 在 JSON-RPC 边界实现 Provider 生命周期门控、连接作用域与 in-flight 排空。
///
/// 裸 transport 仍只负责 JSONL、请求关联和进程退出；本类负责 Provider 语义上的
/// `stopped → starting → initializing → ready → closing → closed`。
class ProviderRuntimeJsonRpcPeer implements JsonRpcPeer {
  ProviderRuntimeJsonRpcPeer(
    this._delegate, {
    required String providerId,
    String? runtimeId,
  }) : _runtimeId = runtimeId ?? _nextRuntimeId(providerId);

  static int _runtimeSequence = 0;

  final JsonRpcPeer _delegate;
  final String _runtimeId;
  final Set<_RuntimeOperationLease> _inFlight = <_RuntimeOperationLease>{};

  AgentProviderLifecycleState _lifecycleState =
      AgentProviderLifecycleState.stopped;
  AgentRuntimeScope? _runtimeScope;
  Completer<void>? _drainCompleter;
  Future<void>? _startOperation;
  Future<void>? _closeOperation;
  int _connectionEpoch = 0;

  AgentProviderLifecycleState get lifecycleState => _lifecycleState;

  AgentRuntimeScope? get runtimeScope => _runtimeScope;

  @override
  Stream<JsonRpcNotification>
  get notifications => _delegate.notifications.transform(
    StreamTransformer<JsonRpcNotification, JsonRpcNotification>.fromHandlers(
      handleData: (notification, sink) {
        sink.add(notification.withRuntimeScope(_requireRuntimeScope()));
      },
      handleDone: (sink) {
        markFailed();
        sink.close();
      },
    ),
  );

  @override
  Stream<JsonRpcRequest> get serverRequests => _delegate.serverRequests.map(
    (request) => request.withRuntimeScope(_requireRuntimeScope()),
  );

  @override
  Stream<String> get stderrLines => _delegate.stderrLines;

  @override
  Stream<JsonRpcProtocolException> get protocolErrors =>
      _delegate.protocolErrors;

  @override
  Future<void> start() async {
    final existing = _startOperation;
    if (existing != null) {
      await existing;
      return;
    }
    if (_lifecycleState != AgentProviderLifecycleState.stopped) {
      if (_lifecycleState == AgentProviderLifecycleState.initializing ||
          _lifecycleState == AgentProviderLifecycleState.ready) {
        return;
      }
      throw _closedError('start');
    }

    _connectionEpoch += 1;
    final scope = AgentRuntimeScope(
      runtimeId: _runtimeId,
      connectionEpoch: _connectionEpoch,
    );
    _runtimeScope = scope;
    _lifecycleState = AgentProviderLifecycleState.starting;
    final operation = _startOnce(scope);
    _startOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_startOperation, operation)) {
        _startOperation = null;
      }
    }
  }

  Future<void> _startOnce(AgentRuntimeScope scope) async {
    try {
      await _delegate.start();
      if (_isCurrent(scope) &&
          _lifecycleState == AgentProviderLifecycleState.starting) {
        _lifecycleState = AgentProviderLifecycleState.initializing;
      }
    } catch (_) {
      markFailed(scope);
      rethrow;
    }
  }

  /// 握手与身份校验完成后开放正常 RPC。
  void markReady() {
    final scope = _requireRuntimeScope();
    if (!_isCurrent(scope) ||
        _lifecycleState != AgentProviderLifecycleState.initializing) {
      throw StateError(
        'Cannot mark Provider ready from ${_lifecycleState.name}',
      );
    }
    _lifecycleState = AgentProviderLifecycleState.ready;
  }

  /// 记录当前连接启动或握手失败；关闭竞态中不覆盖 closing 状态。
  void markFailed([AgentRuntimeScope? scope]) {
    final resolved = scope ?? _runtimeScope;
    if (resolved == null || !_isCurrent(resolved)) {
      return;
    }
    if (_lifecycleState == AgentProviderLifecycleState.closing ||
        _lifecycleState == AgentProviderLifecycleState.closed) {
      return;
    }
    _lifecycleState = AgentProviderLifecycleState.failed;
  }

  /// 原子进入 closing，调用方可先取消挂起交互，再执行 [close]。
  void beginClosing() {
    if (_lifecycleState == AgentProviderLifecycleState.closed ||
        _lifecycleState == AgentProviderLifecycleState.closing) {
      return;
    }
    _lifecycleState = AgentProviderLifecycleState.closing;
  }

  @override
  Future<Object?> sendRequest(
    String method, {
    Object? params,
    Duration timeout = const Duration(seconds: 30),
  }) {
    return _runTracked<Object?>(
      'request $method',
      () => _delegate.sendRequest(method, params: params, timeout: timeout),
    );
  }

  @override
  void sendNotification(String method, {Object? params}) {
    _ensureRpcAllowed('notification $method');
    _delegate.sendNotification(method, params: params);
  }

  @override
  Future<void> sendResponse(Object id, {Object? result, JsonRpcError? error}) {
    return _runTracked<void>(
      'server response',
      () => _delegate.sendResponse(id, result: result, error: error),
      allowClosing: true,
    );
  }

  /// 回应带 connection scope 的服务端请求，旧 epoch 的响应会被明确拒绝。
  Future<void> sendScopedResponse(
    Object id, {
    required AgentRuntimeScope? runtimeScope,
    Object? result,
    JsonRpcError? error,
  }) {
    if (runtimeScope == null || !_isCurrent(runtimeScope)) {
      return Future<void>.error(
        const ProviderConnectionClosedException(
          'Server request belongs to a closed Provider connection',
        ),
      );
    }
    return _runTracked<void>(
      'scoped server response',
      () => _delegate.sendResponse(id, result: result, error: error),
      allowClosing: true,
    );
  }

  /// 追踪一个反向请求 handler；关闭后不再接纳新 handler。
  Future<void> handleServerRequest(
    JsonRpcRequest request,
    FutureOr<void> Function(JsonRpcRequest request) handler,
  ) {
    final scope = request.runtimeScope;
    if (scope == null || !_isCurrent(scope)) {
      return Future<void>.error(
        const ProviderConnectionClosedException(
          'Server request belongs to a closed Provider connection',
        ),
      );
    }
    return _runTracked<void>(
      'server request ${request.method}',
      () async => handler(request),
    );
  }

  @override
  Future<void> close() {
    final existing = _closeOperation;
    if (existing != null) {
      return existing;
    }
    beginClosing();
    final operation = _closeOnce();
    _closeOperation = operation;
    return operation;
  }

  Future<void> _closeOnce() async {
    Object? closeError;
    StackTrace? closeStackTrace;
    try {
      // transport close 会让所有等待中的 client request 以 connectionClosed 结束。
      await _delegate.close();
    } catch (error, stackTrace) {
      closeError = error;
      closeStackTrace = stackTrace;
    }

    final startOperation = _startOperation;
    if (startOperation != null) {
      try {
        await startOperation;
      } catch (_) {
        // close 已成为权威结果；启动失败只用于释放 initialization waiter。
      }
    }

    await _waitForDrain();
    _lifecycleState = AgentProviderLifecycleState.closed;
    if (closeError != null) {
      Error.throwWithStackTrace(closeError, closeStackTrace!);
    }
  }

  Future<T> _runTracked<T>(
    String operationName,
    FutureOr<T> Function() operation, {
    bool allowClosing = false,
  }) async {
    _ensureRpcAllowed(operationName, allowClosing: allowClosing);
    final lease = _RuntimeOperationLease();
    _inFlight.add(lease);
    try {
      return await operation();
    } finally {
      _inFlight.remove(lease);
      if (_inFlight.isEmpty) {
        _drainCompleter?.complete();
        _drainCompleter = null;
      }
    }
  }

  void _ensureRpcAllowed(String operationName, {bool allowClosing = false}) {
    final allowed = switch (_lifecycleState) {
      AgentProviderLifecycleState.initializing ||
      AgentProviderLifecycleState.ready => true,
      AgentProviderLifecycleState.closing => allowClosing,
      _ => false,
    };
    if (!allowed) {
      throw _closedError(operationName);
    }
  }

  Future<void> _waitForDrain() {
    if (_inFlight.isEmpty) {
      return Future<void>.value();
    }
    return (_drainCompleter ??= Completer<void>()).future;
  }

  bool _isCurrent(AgentRuntimeScope scope) => scope == _runtimeScope;

  AgentRuntimeScope _requireRuntimeScope() {
    final scope = _runtimeScope;
    if (scope == null) {
      throw const ProviderConnectionClosedException(
        'Provider connection has not started',
      );
    }
    return scope;
  }

  ProviderConnectionClosedException _closedError(String operationName) {
    return ProviderConnectionClosedException(
      'Cannot start $operationName while Provider is ${_lifecycleState.name}',
    );
  }

  static String _nextRuntimeId(String providerId) {
    _runtimeSequence += 1;
    return '$providerId-runtime-$_runtimeSequence';
  }
}

final class _RuntimeOperationLease {}
