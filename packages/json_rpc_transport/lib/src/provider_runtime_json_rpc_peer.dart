import 'dart:async';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:json_rpc_transport/src/json_rpc_stdio_transport.dart';
import 'package:json_rpc_transport/src/transport_exception.dart';

/// Adds provider lifecycle gates and runtime scoping to a [JsonRpcPeer].
final class ProviderRuntimeJsonRpcPeer implements JsonRpcPeer {
  /// Creates a lifecycle gate for [delegate].
  ProviderRuntimeJsonRpcPeer(
    JsonRpcPeer delegate, {
    required String providerId,
    String? runtimeId,
  }) : _delegate = delegate,
       _runtimeId = runtimeId ?? _nextRuntimeId(providerId);

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

  /// Current provider lifecycle state.
  AgentProviderLifecycleState get lifecycleState => _lifecycleState;

  /// Scope of the active connection, when started.
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
  Stream<TransportException> get protocolErrors => _delegate.protocolErrors;

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
    } on Object {
      markFailed(scope);
      rethrow;
    }
  }

  /// Opens normal RPC after handshake and identity validation.
  void markReady() {
    final scope = _requireRuntimeScope();
    if (!_isCurrent(scope) ||
        _lifecycleState != AgentProviderLifecycleState.initializing) {
      throw StateError(
        'Cannot mark provider ready from ${_lifecycleState.name}',
      );
    }
    _lifecycleState = AgentProviderLifecycleState.ready;
  }

  /// Records a failure for the current connection.
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

  /// Atomically enters closing and stops accepting new client RPC.
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

  /// Responds only when [runtimeScope] belongs to the active connection.
  Future<void> sendScopedResponse(
    Object id, {
    required AgentRuntimeScope? runtimeScope,
    Object? result,
    JsonRpcError? error,
  }) {
    if (runtimeScope == null || !_isCurrent(runtimeScope)) {
      return Future<void>.error(
        const TransportClosed(
          'Server request belongs to a closed provider connection',
        ),
      );
    }
    return _runTracked<void>(
      'scoped server response',
      () => _delegate.sendResponse(id, result: result, error: error),
      allowClosing: true,
    );
  }

  /// Tracks a reverse-request handler so close can await it.
  Future<void> handleServerRequest(
    JsonRpcRequest request,
    FutureOr<void> Function(JsonRpcRequest request) handler,
  ) {
    final scope = request.runtimeScope;
    if (scope == null || !_isCurrent(scope)) {
      return Future<void>.error(
        const TransportClosed(
          'Server request belongs to a closed provider connection',
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
      await _delegate.close();
    } on Object catch (error, stackTrace) {
      closeError = error;
      closeStackTrace = stackTrace;
    }

    final startOperation = _startOperation;
    if (startOperation != null) {
      try {
        await startOperation;
      } on Object {
        // Close owns the terminal result and still drains tracked operations.
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
      throw const TransportClosed('Provider connection has not started');
    }
    return scope;
  }

  TransportClosed _closedError(String operationName) {
    return TransportClosed(
      'Cannot start $operationName while provider is ${_lifecycleState.name}',
    );
  }

  static String _nextRuntimeId(String providerId) {
    _runtimeSequence += 1;
    return '$providerId-runtime-$_runtimeSequence';
  }
}

final class _RuntimeOperationLease {}
