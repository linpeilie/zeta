import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:clock/clock.dart';
import 'package:json_rpc_transport/src/transport_exception.dart';
import 'package:zeta_logging/zeta_logging.dart';

/// Starts a child process for a JSON-RPC peer.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

/// Bidirectional JSON-RPC endpoint used by provider clients.
abstract interface class JsonRpcPeer {
  /// Server notifications without an id.
  Stream<JsonRpcNotification> get notifications;

  /// Server requests that require a client response.
  Stream<JsonRpcRequest> get serverRequests;

  /// Sanitized child-process stderr lines.
  Stream<String> get stderrLines;

  /// Non-fatal frame and stream diagnostics.
  Stream<TransportException> get protocolErrors;

  /// Starts the underlying communication resource.
  Future<void> start();

  /// Sends a request and waits for the matching response.
  Future<Object?> sendRequest(
    String method, {
    Object? params,
    Duration timeout,
  });

  /// Sends a notification that does not require a response.
  void sendNotification(String method, {Object? params});

  /// Responds to a server request.
  Future<void> sendResponse(Object id, {Object? result, JsonRpcError? error});

  /// Closes the endpoint and cancels pending requests.
  Future<void> close();
}

/// A server notification.
final class JsonRpcNotification {
  /// Creates a server notification with immutable top-level maps.
  JsonRpcNotification({
    required this.method,
    required Map<String, Object?> params,
    required Map<String, Object?> raw,
    this.runtimeScope,
  }) : params = Map<String, Object?>.unmodifiable(params),
       raw = Map<String, Object?>.unmodifiable(raw);

  /// JSON-RPC method name.
  final String method;

  /// Decoded params, or an empty map when absent or malformed.
  final Map<String, Object?> params;

  /// Complete decoded message.
  final Map<String, Object?> raw;

  /// Runtime scope attached by the provider runtime gate.
  final AgentRuntimeScope? runtimeScope;

  /// Returns the message associated with [scope].
  JsonRpcNotification withRuntimeScope(AgentRuntimeScope scope) {
    return JsonRpcNotification(
      method: method,
      params: params,
      raw: raw,
      runtimeScope: scope,
    );
  }
}

/// A server request.
final class JsonRpcRequest {
  /// Creates a server request with immutable top-level maps.
  JsonRpcRequest({
    required this.id,
    required this.method,
    required Map<String, Object?> params,
    required Map<String, Object?> raw,
    this.runtimeScope,
  }) : params = Map<String, Object?>.unmodifiable(params),
       raw = Map<String, Object?>.unmodifiable(raw);

  /// Request identifier supplied by the server.
  final Object id;

  /// JSON-RPC method name.
  final String method;

  /// Decoded params, or an empty map when absent or malformed.
  final Map<String, Object?> params;

  /// Complete decoded message.
  final Map<String, Object?> raw;

  /// Runtime scope attached by the provider runtime gate.
  final AgentRuntimeScope? runtimeScope;

  /// Returns the request associated with [scope].
  JsonRpcRequest withRuntimeScope(AgentRuntimeScope scope) {
    return JsonRpcRequest(
      id: id,
      method: method,
      params: params,
      raw: raw,
      runtimeScope: scope,
    );
  }
}

/// JSON-RPC error object.
final class JsonRpcError {
  /// Creates a JSON-RPC error object.
  const JsonRpcError({required this.code, required this.message, this.data});

  /// Protocol error code.
  final int code;

  /// Protocol error message.
  final String message;

  /// Optional protocol error data.
  final Object? data;

  /// Encodes this error for the wire.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    if (data != null) 'data': data,
  };
}

/// A valid JSON-RPC error response.
final class JsonRpcException implements Exception, StructuredLogDiagnostic {
  /// Creates an exception for [error].
  const JsonRpcException(this.error);

  /// Error returned by the peer.
  final JsonRpcError error;

  @override
  Map<String, Object?> get logDiagnostic => <String, Object?>{
    'jsonRpcError': error.toJson(),
  };

  @override
  String toString() => 'JSON-RPC error ${error.code}: ${error.message}';
}

/// A bounded JSONL transport over a child process's stdio streams.
final class JsonRpcStdioTransport implements JsonRpcPeer {
  /// Creates an injectable stdio transport.
  JsonRpcStdioTransport({
    required this.command,
    required this.processStarter,
    required this.logger,
    this.clock = const Clock(),
    List<String> arguments = const <String>[],
    Map<String, String> environment = const <String, String>{},
    this.workingDirectory,
    this.maximumLineLength = 1024 * 1024,
    this.processExitTimeout = const Duration(seconds: 5),
  }) : arguments = List<String>.unmodifiable(arguments),
       environment = Map<String, String>.unmodifiable(environment) {
    if (maximumLineLength <= 0) {
      throw ArgumentError.value(
        maximumLineLength,
        'maximumLineLength',
        'must be positive',
      );
    }
    if (processExitTimeout.isNegative) {
      throw ArgumentError.value(
        processExitTimeout,
        'processExitTimeout',
        'must not be negative',
      );
    }
  }

  /// Executable passed to [processStarter].
  final String command;

  /// Immutable process arguments.
  final List<String> arguments;

  /// Immutable process environment additions.
  final Map<String, String> environment;

  /// Optional process working directory.
  final String? workingDirectory;

  /// Injected process boundary.
  final ProcessStarter processStarter;

  /// Injected clock used for diagnostics and timeout metadata.
  final Clock clock;

  /// Injected sanitizing logger.
  final AppLogger logger;

  /// Maximum number of decoded characters accepted for one JSONL frame.
  final int maximumLineLength;

  /// Grace period before escalating child-process termination.
  final Duration processExitTimeout;

  final StreamController<JsonRpcNotification> _notifications =
      StreamController<JsonRpcNotification>.broadcast();
  final StreamController<JsonRpcRequest> _serverRequests =
      StreamController<JsonRpcRequest>.broadcast();
  final StreamController<String> _stderrLines =
      StreamController<String>.broadcast();
  final StreamController<TransportException> _protocolErrors =
      StreamController<TransportException>.broadcast();
  final Map<Object, Completer<Object?>> _pending =
      <Object, Completer<Object?>>{};
  final Map<Object, Timer> _pendingTimers = <Object, Timer>{};

  Process? _process;
  Future<void> _writeQueue = Future<void>.value();
  Future<void>? _startOperation;
  Future<void>? _closeOperation;
  Future<void>? _controllersCloseOperation;
  int _nextId = 1;
  bool _closing = false;
  bool _started = false;

  @override
  Stream<JsonRpcNotification> get notifications => _notifications.stream;

  @override
  Stream<JsonRpcRequest> get serverRequests => _serverRequests.stream;

  @override
  Stream<String> get stderrLines => _stderrLines.stream;

  @override
  Stream<TransportException> get protocolErrors => _protocolErrors.stream;

  @override
  Future<void> start() async {
    if (_started) {
      return;
    }
    if (_closing) {
      throw const TransportClosed();
    }
    final existing = _startOperation;
    if (existing != null) {
      await existing;
      return;
    }
    final operation = _startProcess();
    _startOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_startOperation, operation)) {
        _startOperation = null;
      }
    }
  }

  Future<void> _startProcess() async {
    logger.i(
      'Starting JSON-RPC process with ${arguments.length} arguments',
      time: clock.now(),
    );
    final Process process;
    try {
      process = await processStarter(
        command,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment.isEmpty
            ? null
            : Map<String, String>.from(environment),
      );
    } on Object catch (error) {
      logger.e(
        'JSON-RPC process could not be started',
        time: clock.now(),
        error: error,
      );
      throw TransportProcessExited(
        message: 'JSON-RPC process could not be started',
        causeType: error.runtimeType.toString(),
      );
    }
    if (_closing) {
      await process.stdin.close();
      process.kill();
      throw const TransportClosed();
    }

    _process = process;
    _started = true;
    logger.i('JSON-RPC process started', time: clock.now());

    const decoder = Utf8Decoder(allowMalformed: true);
    final stdoutLines = _BoundedLineDecoder(
      maximumLength: maximumLineLength,
      onLine: _handleStdoutLine,
      onTooLong: _handleLineTooLong,
    );
    final stderrLines = _BoundedLineDecoder(
      maximumLength: maximumLineLength,
      onLine: _handleStderrLine,
      onTooLong: _handleLineTooLong,
    );
    process.stdout
        .transform(decoder)
        .listen(
          stdoutLines.add,
          onError: _handleStreamError,
          onDone: stdoutLines.close,
        );
    process.stderr
        .transform(decoder)
        .listen(
          stderrLines.add,
          onError: _handleStreamError,
          onDone: stderrLines.close,
        );
    unawaited(_watchExit(process));
  }

  @override
  Future<Object?> sendRequest(
    String method, {
    Object? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _ensureOpen();
    if (timeout.isNegative) {
      throw ArgumentError.value(timeout, 'timeout', 'must not be negative');
    }

    final id = _nextId++;
    final startedAt = clock.now();
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _pendingTimers[id] = Timer(timeout, () {
      final pending = _pending.remove(id);
      _pendingTimers.remove(id);
      logger.w('JSON-RPC request timed out: $method', time: clock.now());
      pending?.completeError(
        TransportTimeout(
          method: method,
          timeout: timeout,
          startedAt: startedAt,
        ),
      );
    });

    try {
      await _write(
        <String, Object?>{
          'id': id,
          'method': method,
          'params': params ?? const <String, Object?>{},
        },
        description: 'JSON-RPC request $method with id $id',
      );
    } on Object {
      _pending.remove(id);
      _pendingTimers.remove(id)?.cancel();
      rethrow;
    }
    return completer.future;
  }

  @override
  void sendNotification(String method, {Object? params}) {
    _ensureOpen();
    unawaited(
      _write(
        <String, Object?>{
          'method': method,
          'params': params ?? const <String, Object?>{},
        },
        description: 'JSON-RPC notification $method',
      ).catchError((Object error, StackTrace stackTrace) {
        _handleStreamError(error, stackTrace);
      }),
    );
  }

  @override
  Future<void> sendResponse(
    Object id, {
    Object? result,
    JsonRpcError? error,
  }) async {
    _ensureOpen();
    await _write(
      error == null
          ? <String, Object?>{'id': id, 'result': result}
          : <String, Object?>{'id': id, 'error': error.toJson()},
      description: error == null
          ? 'JSON-RPC response for id type ${id.runtimeType}'
          : 'JSON-RPC error response for id type ${id.runtimeType}',
    );
  }

  @override
  Future<void> close() => _closeOperation ??= _closeOnce();

  Future<void> _closeOnce() async {
    logger.t('Closing JSON-RPC transport', time: clock.now());
    _closing = true;
    _cancelPending(const TransportClosed());

    final startOperation = _startOperation;
    if (startOperation != null) {
      try {
        await startOperation;
      } on TransportException {
        // Close owns the terminal outcome and still releases every resource.
      }
    }

    final process = _process;
    if (process != null) {
      try {
        await _writeQueue;
      } on Object {
        // The request future already observes the typed write failure.
      }
      try {
        await process.stdin.close();
      } on Object {
        // The child may already have closed its input stream.
      }
      process.kill();
      try {
        await process.exitCode.timeout(processExitTimeout);
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }
    await _closeControllers();
  }

  void _handleStdoutLine(String line) {
    if (line.trim().isEmpty || _protocolErrors.isClosed) {
      return;
    }
    final payloadLength = line.length;
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on Object catch (error) {
      logger.w(
        'Invalid JSON-RPC stdout frame '
        '(${error.runtimeType}, $payloadLength characters)',
        time: clock.now(),
      );
      _addProtocolError(
        TransportMalformedFrame(
          message: 'Invalid JSON on stdout',
          payloadLength: payloadLength,
          causeType: error.runtimeType.toString(),
        ),
      );
      return;
    }

    final raw = _objectMap(decoded);
    if (raw == null) {
      _addProtocolError(
        TransportMalformedFrame(
          message: 'JSON-RPC message must be an object',
          payloadLength: payloadLength,
        ),
      );
      return;
    }

    final method = raw['method'];
    final id = raw['id'];
    if (id != null && (raw.containsKey('result') || raw.containsKey('error'))) {
      _handleResponse(id, raw);
      return;
    }
    if (method is String && id != null) {
      if (!_serverRequests.isClosed) {
        _serverRequests.add(
          JsonRpcRequest(
            id: id,
            method: method,
            params: _paramsMap(raw['params']),
            raw: raw,
          ),
        );
      }
      return;
    }
    if (method is String) {
      if (!_notifications.isClosed) {
        _notifications.add(
          JsonRpcNotification(
            method: method,
            params: _paramsMap(raw['params']),
            raw: raw,
          ),
        );
      }
      return;
    }
    _addProtocolError(
      TransportMalformedFrame(
        message: 'Unknown JSON-RPC message shape',
        payloadLength: payloadLength,
      ),
    );
  }

  void _handleResponse(Object id, Map<String, Object?> raw) {
    var matchedId = id;
    var completer = _pending.remove(matchedId);
    if (completer == null && id is String) {
      final numericId = int.tryParse(id);
      if (numericId != null) {
        matchedId = numericId;
        completer = _pending.remove(matchedId);
      }
    }
    if (completer == null) {
      _addProtocolError(
        const TransportMalformedFrame(
          message: 'Response for unknown request id',
          payloadLength: 0,
        ),
      );
      return;
    }
    _pendingTimers.remove(matchedId)?.cancel();

    final error = raw['error'];
    if (error != null) {
      completer.completeError(JsonRpcException(_decodeError(error)));
      return;
    }
    completer.complete(raw['result']);
  }

  Future<void> _watchExit(Process process) async {
    final exitCode = await process.exitCode;
    if (_closing) {
      return;
    }
    _closing = true;
    logger.w('JSON-RPC process exited with code $exitCode', time: clock.now());
    _cancelPending(
      TransportProcessExited(
        message: 'JSON-RPC process exited unexpectedly',
        exitCode: exitCode,
      ),
    );
    await _closeControllers();
  }

  void _handleStreamError(Object error, [StackTrace? stackTrace]) {
    logger.w(
      'JSON-RPC process stream failed (${error.runtimeType})',
      time: clock.now(),
      error: error,
      stackTrace: stackTrace,
    );
    _addProtocolError(
      TransportMalformedFrame(
        message: 'Process stream failed',
        payloadLength: 0,
        causeType: error.runtimeType.toString(),
      ),
    );
  }

  void _handleStderrLine(String line) {
    if (line.trim().isEmpty || _stderrLines.isClosed) {
      return;
    }
    logger.t(
      'Received JSON-RPC stderr line (${line.length} characters)',
      time: clock.now(),
    );
    _stderrLines.add(redactSensitiveText(line));
  }

  void _handleLineTooLong(int observedLength) {
    _addProtocolError(
      TransportLineTooLong(
        maximumLength: maximumLineLength,
        observedLength: observedLength,
      ),
    );
  }

  Future<void> _write(
    Map<String, Object?> message, {
    required String description,
  }) {
    final encoded = jsonEncode(message);
    logger.t(
      'Sending $description (${encoded.length} characters)',
      time: clock.now(),
    );
    final operation = _writeQueue.then((_) async {
      final process = _process;
      if (_closing || process == null) {
        throw const TransportClosed();
      }
      try {
        process.stdin.writeln(encoded);
        await process.stdin.flush();
      } on Object catch (error) {
        logger.w(
          'JSON-RPC stdin write failed (${error.runtimeType})',
          time: clock.now(),
          error: error,
        );
        throw const TransportClosed('JSON-RPC stdin write failed');
      }
    });
    _writeQueue = operation.catchError((Object _, StackTrace _) {});
    return operation;
  }

  void _ensureOpen() {
    if (!_started || _closing || _process == null) {
      throw const TransportClosed();
    }
  }

  void _cancelPending(TransportException error) {
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    _pendingTimers.clear();
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(error);
      }
    }
    _pending.clear();
  }

  void _addProtocolError(TransportException error) {
    if (!_protocolErrors.isClosed) {
      _protocolErrors.add(error);
    }
  }

  Future<void> _closeControllers() {
    return _controllersCloseOperation ??= Future.wait<void>(<Future<void>>[
      _notifications.close(),
      _serverRequests.close(),
      _stderrLines.close(),
      _protocolErrors.close(),
    ]);
  }
}

final class _BoundedLineDecoder {
  _BoundedLineDecoder({
    required this.maximumLength,
    required this.onLine,
    required this.onTooLong,
  });

  final int maximumLength;
  final void Function(String line) onLine;
  final void Function(int observedLength) onTooLong;

  final StringBuffer _buffer = StringBuffer();
  bool _dropping = false;
  int _observedLength = 0;

  void add(String chunk) {
    for (final codeUnit in chunk.codeUnits) {
      if (codeUnit == 10) {
        _emitLine();
      } else if (_dropping) {
        _observedLength += 1;
      } else if (_buffer.length == maximumLength) {
        _dropping = true;
        _observedLength = maximumLength + 1;
        _buffer.clear();
      } else {
        _buffer.writeCharCode(codeUnit);
      }
    }
  }

  void close() {
    if (_dropping || _buffer.isNotEmpty) {
      _emitLine();
    }
  }

  void _emitLine() {
    if (_dropping) {
      onTooLong(_observedLength);
    } else {
      var line = _buffer.toString();
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      onLine(line);
    }
    _buffer.clear();
    _dropping = false;
    _observedLength = 0;
  }
}

Map<String, Object?> _paramsMap(Object? value) {
  return _objectMap(value) ?? const <String, Object?>{};
}

JsonRpcError _decodeError(Object? value) {
  final error = _objectMap(value);
  if (error == null) {
    return const JsonRpcError(code: -32000, message: 'Unknown JSON-RPC error');
  }
  final code = error['code'];
  final message = error['message'];
  return JsonRpcError(
    code: code is int ? code : -32000,
    message: message is String ? message : 'Unknown JSON-RPC error',
    data: error['data'],
  );
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) {
      result[key] = entry.value;
    }
  }
  return result;
}
