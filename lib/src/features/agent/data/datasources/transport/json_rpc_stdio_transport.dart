import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/domain/agent_runtime_models.dart';

final _log = loggerFor('zeta.agent.json_rpc_stdio');

/// 启动子进程的函数类型。
///
/// 测试可以注入 fake starter；生产环境默认使用 [Process.start]。
typedef ProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    });

/// 基于 JSON-RPC 的双向通信端点。
///
/// Codex app-server 通过 stdout/stdin 交换 JSONL；未来 ACP stdio provider 也可以复用
/// 这个抽象。
abstract class JsonRpcPeer {
  /// 服务端主动发出的无 id 通知。
  Stream<JsonRpcNotification> get notifications;

  /// 服务端主动发出的带 id 请求，需要客户端用 [sendResponse] 回写。
  Stream<JsonRpcRequest> get serverRequests;

  /// 子进程 stderr 行。
  Stream<String> get stderrLines;

  /// JSON 解析失败、未知消息形状等协议层警告。
  Stream<JsonRpcProtocolException> get protocolErrors;

  /// 启动底层通信资源。
  Future<void> start();

  /// 发送 JSON-RPC 请求，并等待匹配 id 的响应。
  Future<Object?> sendRequest(
    String method, {
    Object? params,
    Duration timeout,
  });

  /// 发送无需响应的 JSON-RPC 通知。
  void sendNotification(String method, {Object? params});

  /// 响应服务端请求。
  Future<void> sendResponse(Object id, {Object? result, JsonRpcError? error});

  /// 关闭通信并清理所有待处理请求。
  Future<void> close();
}

/// 服务端通知消息。
class JsonRpcNotification {
  const JsonRpcNotification({
    required this.method,
    required this.params,
    required this.raw,
    this.runtimeScope,
  });

  final String method;
  final Map<String, Object?> params;
  final Map<String, Object?> raw;

  /// 由 Provider runtime gate 注入；裸 transport 消息可以为空。
  final AgentRuntimeScope? runtimeScope;

  JsonRpcNotification withRuntimeScope(AgentRuntimeScope scope) {
    return JsonRpcNotification(
      method: method,
      params: params,
      raw: raw,
      runtimeScope: scope,
    );
  }
}

/// 服务端请求消息。
class JsonRpcRequest {
  const JsonRpcRequest({
    required this.id,
    required this.method,
    required this.params,
    required this.raw,
    this.runtimeScope,
  });

  final Object id;
  final String method;
  final Map<String, Object?> params;
  final Map<String, Object?> raw;

  /// 由 Provider runtime gate 注入，用于约束反向请求的响应连接。
  final AgentRuntimeScope? runtimeScope;

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

/// JSON-RPC error object。
class JsonRpcError {
  const JsonRpcError({required this.code, required this.message, this.data});

  final int code;
  final String message;
  final Object? data;

  /// 转成 JSON-RPC error 字段。
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'code': code,
      'message': message,
      if (data != null) 'data': data,
    };
  }
}

/// JSON-RPC 错误响应。
class JsonRpcException implements Exception {
  const JsonRpcException(this.error);

  final JsonRpcError error;

  @override
  String toString() => 'JSON-RPC error ${error.code}: ${error.message}';
}

/// 协议层异常。
///
/// 这类异常通常不会直接关闭连接，而是通过 [JsonRpcPeer.protocolErrors] 暴露给上层。
class JsonRpcProtocolException implements Exception {
  const JsonRpcProtocolException(this.message, {this.line, this.cause});

  final String message;
  final String? line;
  final Object? cause;

  @override
  String toString() {
    final suffix = line == null ? '' : ' Line: $line';
    return 'JSON-RPC protocol error: $message$suffix';
  }
}

/// 连接已关闭或子进程退出。
class JsonRpcTransportClosedException implements Exception {
  const JsonRpcTransportClosedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// stdio + JSONL 的 JSON-RPC transport。
///
/// 每一行 stdout 都应是一条 JSON-RPC 消息；stdin 每次写入一行 JSON。
class JsonRpcStdioTransport implements JsonRpcPeer {
  JsonRpcStdioTransport({
    required this.command,
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
    this.workingDirectory,
    this.processStarter = Process.start,
  });

  final String command;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;
  final ProcessStarter processStarter;

  final StreamController<JsonRpcNotification> _notifications =
      StreamController<JsonRpcNotification>.broadcast();
  final StreamController<JsonRpcRequest> _serverRequests =
      StreamController<JsonRpcRequest>.broadcast();
  final StreamController<String> _stderrLines =
      StreamController<String>.broadcast();
  final StreamController<JsonRpcProtocolException> _protocolErrors =
      StreamController<JsonRpcProtocolException>.broadcast();
  final Map<Object, Completer<Object?>> _pending =
      <Object, Completer<Object?>>{};

  /// 每个待响应请求都有独立计时器，避免 CLI 无响应时 UI 永久挂起。
  final Map<Object, Timer> _pendingTimers = <Object, Timer>{};

  Process? _process;
  Future<void> _writeQueue = Future<void>.value();
  Future<void>? _startOperation;
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
  Stream<JsonRpcProtocolException> get protocolErrors => _protocolErrors.stream;

  @override
  Future<void> start() async {
    if (_started) {
      return;
    }
    if (_closing) {
      throw const JsonRpcTransportClosedException(
        'JSON-RPC transport is not open',
      );
    }
    final inFlightStart = _startOperation;
    if (inFlightStart != null) {
      await inFlightStart;
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
    _log.info(
      'Starting JSON-RPC process $command with ${arguments.length} arguments',
    );

    final mergedEnvironment = environment.isEmpty
        ? null
        : Map<String, String>.from(environment);
    final process = await processStarter(
      command,
      arguments,
      workingDirectory: workingDirectory,
      environment: mergedEnvironment,
    );
    if (_closing) {
      await process.stdin.close();
      process.kill();
      throw const JsonRpcTransportClosedException(
        'JSON-RPC transport is not open',
      );
    }
    _process = process;
    _log.info('JSON-RPC process started with pid ${process.pid}');

    // Windows 启动器和本地化诊断偶尔会夹带非 UTF-8 字节。若使用严格
    // 解码，单个受损字符会终止整条订阅，进而让子进程因管道断开退出。
    // 这里仅替换无法解码的字符；损坏 JSON 结构仍由 _handleStdoutLine 报错。
    const processOutputDecoder = Utf8Decoder(allowMalformed: true);
    // stdout 是协议通道；stderr 只作为诊断信息上报，不参与 JSON-RPC 匹配。
    process.stdout
        .transform(processOutputDecoder)
        .transform(const LineSplitter())
        .listen(_handleStdoutLine, onError: _handleStreamError);
    process.stderr
        .transform(processOutputDecoder)
        .transform(const LineSplitter())
        .listen(_handleStderrLine, onError: _handleStreamError);
    unawaited(_watchExit(process));
    _started = true;
  }

  @override
  Future<Object?> sendRequest(
    String method, {
    Object? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _ensureOpen();

    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    // 请求 id 与响应 id 一一对应；超时后移除 pending，防止迟到响应污染状态。
    _pendingTimers[id] = Timer(timeout, () {
      final pending = _pending.remove(id);
      _pendingTimers.remove(id);
      _log.warning('JSON-RPC request timed out: $method');
      pending?.completeError(
        TimeoutException('JSON-RPC request timed out: $method', timeout),
      );
    });

    try {
      await _write(<String, Object?>{
        'id': id,
        'method': method,
        'params': params ?? const <String, Object?>{},
      }, description: 'JSON-RPC request $method with id $id');
    } catch (error) {
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
      _write(<String, Object?>{
        'method': method,
        'params': params ?? const <String, Object?>{},
      }, description: 'JSON-RPC notification $method').catchError((
        Object error,
        StackTrace stackTrace,
      ) {
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
    if (error != null) {
      await _write(<String, Object?>{
        'id': id,
        'error': error.toJson(),
      }, description: 'JSON-RPC error response for id type ${id.runtimeType}');
    } else {
      await _write(<String, Object?>{
        'id': id,
        'result': result,
      }, description: 'JSON-RPC response for id type ${id.runtimeType}');
    }
  }

  @override
  Future<void> close() async {
    if (_closing) {
      return;
    }
    _log.fine('Closing JSON-RPC transport');
    _closing = true;
    // 关闭时主动完成所有 pending future，调用方不会无限等待。
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    _pendingTimers.clear();
    for (final pending in _pending.values) {
      pending.completeError(
        const JsonRpcTransportClosedException('JSON-RPC transport closed'),
      );
    }
    _pending.clear();

    final process = _process;
    if (process != null) {
      try {
        await _writeQueue;
      } catch (_) {
        // 关闭流程里只需要尽力等待正在进行的写入；失败会通过 pending future 暴露。
      }
      await process.stdin.close();
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        // 包装器或其子进程未及时退出时再升级为强制终止，避免长期占用 workspace。
        process.kill(ProcessSignal.sigkill);
      }
    }
    await _closeControllers();
  }

  void _handleStdoutLine(String line) {
    if (line.trim().isEmpty) {
      return;
    }
    final payloadLength = line.length;

    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (error, stackTrace) {
      _log.warning('Invalid JSON-RPC stdout line', error, stackTrace);
      _protocolErrors.add(
        JsonRpcProtocolException(
          'Invalid JSON on stdout',
          line: line,
          cause: error,
        ),
      );
      return;
    }

    final raw = _objectMap(decoded);
    if (raw == null) {
      _log.warning('JSON-RPC stdout message was not an object');
      _protocolErrors.add(
        JsonRpcProtocolException(
          'JSON-RPC message must be an object',
          line: line,
        ),
      );
      return;
    }

    final method = raw['method'];
    final id = raw['id'];
    // JSON-RPC 响应：带 id 且包含 result 或 error。
    if (id != null && (raw.containsKey('result') || raw.containsKey('error'))) {
      _log.fine(
        'Received JSON-RPC response idType=${id.runtimeType} '
        '($payloadLength characters)',
      );
      _handleResponse(id, raw);
      return;
    }

    // 服务端请求：带 id 和 method，需要客户端稍后 sendResponse。
    if (method is String && id != null) {
      _log.fine(
        'Received JSON-RPC server request $method '
        'idType=${id.runtimeType} ($payloadLength characters)',
      );
      _serverRequests.add(
        JsonRpcRequest(
          id: id,
          method: method,
          params: _paramsMap(raw['params']),
          raw: raw,
        ),
      );
      return;
    }

    // 服务端通知：只有 method，不需要响应。
    if (method is String) {
      _notifications.add(
        JsonRpcNotification(
          method: method,
          params: _paramsMap(raw['params']),
          raw: raw,
        ),
      );
      return;
    }

    _log.warning('Unknown JSON-RPC message shape');
    _protocolErrors.add(
      JsonRpcProtocolException('Unknown JSON-RPC message shape', line: line),
    );
  }

  void _handleResponse(Object id, Map<String, Object?> raw) {
    final completer = _pending.remove(id);
    _pendingTimers.remove(id)?.cancel();
    if (completer == null) {
      _log.warning(
        'JSON-RPC response for unknown request id (${id.runtimeType})',
      );
      _protocolErrors.add(
        JsonRpcProtocolException('Response for unknown request id: $id'),
      );
      return;
    }

    final error = raw['error'];
    if (error != null) {
      final decodedError = _decodeError(error);
      _log.warning('JSON-RPC error response code=${decodedError.code}');
      completer.completeError(JsonRpcException(decodedError));
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
    _log.warning('JSON-RPC process exited with code $exitCode');
    final error = JsonRpcTransportClosedException(
      'JSON-RPC process exited with code $exitCode',
    );
    // 子进程意外退出时，把所有等待中的请求统一置为关闭错误。
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    _pendingTimers.clear();
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
    await _closeControllers();
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    _log.warning('JSON-RPC process stream error', error, stackTrace);
    _protocolErrors.add(
      JsonRpcProtocolException('Process stream error', cause: error),
    );
  }

  void _handleStderrLine(String line) {
    if (line.trim().isEmpty) {
      return;
    }
    // stderr 可能包含本地路径、账号或凭证诊断；上层可消费脱敏后的内容，
    // transport 日志只记录长度，避免把原文复制到应用日志。
    _log.fine('Received JSON-RPC stderr line (${line.length} characters)');
    _stderrLines.add(line);
  }

  Future<void> _write(
    Map<String, Object?> message, {
    required String description,
  }) {
    final encoded = jsonEncode(message);
    // 请求参数可能包含 prompt、文件内容或认证信息；协议日志不得记录 payload。
    _log.fine('Sending $description (${encoded.length} characters)');
    // IOSink 在 flush/addStream 期间不允许并发写入；所有 JSONL 输出都走同一条队列。
    final operation = _writeQueue.then((_) async {
      final process = _process;
      if (_closing || process == null) {
        throw const JsonRpcTransportClosedException(
          'JSON-RPC transport is not open',
        );
      }
      process.stdin.writeln(encoded);
      // stdio 管道可能缓冲，主动 flush 可以让交互式 CLI 更快收到请求。
      await process.stdin.flush();
    });
    _writeQueue = operation.catchError((Object error, StackTrace stackTrace) {
      _log.warning('JSON-RPC stdin write failed', error, stackTrace);
    });
    return operation;
  }

  void _ensureOpen() {
    if (!_started || _closing || _process == null) {
      _log.warning('JSON-RPC transport is not open');
      throw const JsonRpcTransportClosedException(
        'JSON-RPC transport is not open',
      );
    }
  }

  Future<void> _closeControllers() async {
    await Future.wait(<Future<void>>[
      _notifications.close(),
      _serverRequests.close(),
      _stderrLines.close(),
      _protocolErrors.close(),
    ]);
  }
}

Map<String, Object?> _paramsMap(Object? value) {
  return _objectMap(value) ?? const <String, Object?>{};
}

/// 宽容解析 JSON-RPC error。
///
/// 如果服务端返回了非标准 error，也尽量转成可显示的通用错误。
JsonRpcError _decodeError(Object? value) {
  final error = _objectMap(value);
  if (error != null) {
    final code = error['code'];
    final message = error['message'];
    return JsonRpcError(
      code: code is int ? code : -32000,
      message: message is String ? message : 'Unknown JSON-RPC error',
      data: error['data'],
    );
  }
  return const JsonRpcError(code: -32000, message: 'Unknown JSON-RPC error');
}

/// 将 jsonDecode 得到的 Map 转成 `Map<String, Object?>`。
///
/// Dart 运行时常见类型是 `Map<String, dynamic>`，直接类型判断会过窄；这里显式
/// 复制字符串 key，忽略非字符串 key。
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
