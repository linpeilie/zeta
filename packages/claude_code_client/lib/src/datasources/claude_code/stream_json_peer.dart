import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:json_rpc_transport/json_rpc_transport.dart' show ProcessStarter;
import 'package:zeta_logging/zeta_logging.dart';

/// 默认单行 JSON 上限（约 4 MiB），防止极端 tool_result 撑爆内存。
const int kStreamJsonDefaultMaxLineBytes = 4 * 1024 * 1024;

/// Creates a stream-JSON peer from fully resolved process inputs.
typedef StreamJsonPeerBuilder = StreamJsonPeer Function({
  required String command,
  required List<String> arguments,
  required String? workingDirectory,
  required Map<String, String> environment,
  required ProcessStarter processStarter,
  required AppLogger logger,
});

/// Claude Code stream-json 的一行事件。
class StreamJsonEvent {
  /// Creates a [StreamJsonEvent].
  const StreamJsonEvent({required this.type, required this.raw, this.subtype});

  /// The `type` value.
  final String type;

  /// The `subtype` value.
  final String? subtype;

  /// The `raw` value.
  final Map<String, Object?> raw;
}

/// 行解析 / 尺寸等协议层警告（不含 payload 原文）。
class StreamJsonProtocolException implements Exception {
  /// Creates a [StreamJsonProtocolException].
  const StreamJsonProtocolException(
    this.message, {
    this.payloadLength,
    this.causeType,
  });

  /// The `message` value.
  final String message;

  /// The `payloadLength` value.
  final int? payloadLength;

  /// The `causeType` value.
  final String? causeType;

  @override
  String toString() {
    final parts = <String>[message];
    if (payloadLength != null) {
      parts.add('payloadLength=$payloadLength');
    }
    if (causeType != null) {
      parts.add('causeType=$causeType');
    }
    return parts.join(' ');
  }
}

/// 传输已关闭或尚未 start。
class StreamJsonTransportClosedException implements Exception {
  /// Creates a [StreamJsonTransportClosedException].
  const StreamJsonTransportClosedException(this.message);

  /// The `message` value.
  final String message;

  @override
  String toString() => message;
}

/// Claude Code stream-json 行分隔 peer。
///
/// 与 JSON-RPC peer 不同：每行是独立 `type` 事件，无 id 相关请求—响应匹配。
class StreamJsonPeer {
  /// Creates a [StreamJsonPeer].
  StreamJsonPeer({
    required this.command,
    this.arguments = const <String>[],
    this.workingDirectory,
    this.environment = const <String, String>{},
    ProcessStarter? processStarter,
    AppLogger? logger,
    this.maxLineBytes = kStreamJsonDefaultMaxLineBytes,
    this.exitTimeout = const Duration(seconds: 5),
  }) : processStarter = processStarter ?? Process.start,
       _log = logger ?? loggerFor('zeta.agent.claude_code.stream_json');

  /// The `command` value.
  final String command;

  /// The `arguments` value.
  final List<String> arguments;

  /// The `workingDirectory` value.
  final String? workingDirectory;

  /// The `environment` value.
  final Map<String, String> environment;

  /// The `processStarter` value.
  final ProcessStarter processStarter;

  /// The `maxLineBytes` value.
  final int maxLineBytes;

  /// Maximum graceful process-exit wait during [close].
  final Duration exitTimeout;
  final AppLogger _log;

  final StreamController<StreamJsonEvent> _events =
      StreamController<StreamJsonEvent>.broadcast();
  final StreamController<String> _stderrLines =
      StreamController<String>.broadcast();
  final StreamController<StreamJsonProtocolException> _protocolErrors =
      StreamController<StreamJsonProtocolException>.broadcast();

  Process? _process;
  Future<void> _writeQueue = Future<void>.value();
  Future<void>? _startOperation;
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  final _LineAccumulator _stdoutLines = _LineAccumulator();
  final _LineAccumulator _stderrLinesAcc = _LineAccumulator();
  bool _closing = false;
  bool _started = false;

  /// The `events` value.
  Stream<StreamJsonEvent> get events => _events.stream;

  /// The `stderrLines` value.
  Stream<String> get stderrLines => _stderrLines.stream;

  /// The `protocolErrors` value.
  Stream<StreamJsonProtocolException> get protocolErrors =>
      _protocolErrors.stream;

  /// Runs `start`.
  Future<void> start() async {
    if (_started) {
      return;
    }
    if (_closing) {
      throw const StreamJsonTransportClosedException(
        'Stream-json transport is not open',
      );
    }
    final inFlight = _startOperation;
    if (inFlight != null) {
      await inFlight;
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
    _log.i('Starting stream-json process with ${arguments.length} arguments');
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
      throw const StreamJsonTransportClosedException(
        'Stream-json transport is not open',
      );
    }
    _process = process;
    _log.i('Stream-json process started with pid ${process.pid}');

    // Windows / 本地化诊断可能夹带非 UTF-8；损坏字符替换后继续读，坏 JSON
    // 由单行解析记入 protocolErrors，不断流。
    const decoder = Utf8Decoder(allowMalformed: true);
    _stdoutSubscription = process.stdout.listen(
      (chunk) => _onStdoutBytes(decoder.convert(chunk)),
      onError: _handleStreamError,
      onDone: _handleStdoutDone,
      cancelOnError: false,
    );
    _stderrSubscription = process.stderr.listen(
      (chunk) => _onStderrBytes(decoder.convert(chunk)),
      onError: _handleStreamError,
      onDone: _handleStderrDone,
      cancelOnError: false,
    );
    unawaited(_watchExit(process));
    _started = true;
  }

  /// 写出任意一行 JSON 对象（user / control / control_response 等）。
  Future<void> send(Map<String, Object?> message) {
    _ensureOpen();
    final encoded = jsonEncode(message);
    _log.t('Sending stream-json line (${encoded.length} characters)');
    final operation = _writeQueue.then((_) async {
      final process = _process;
      if (_closing || process == null) {
        throw const StreamJsonTransportClosedException(
          'Stream-json transport is not open',
        );
      }
      process.stdin.writeln(encoded);
      await process.stdin.flush();
    });
    _writeQueue = operation.catchError((Object error, StackTrace _) {
      _log.w('Stream-json stdin write failed (${error.runtimeType})');
    });
    return operation;
  }

  /// Runs `sendUserMessage`.
  Future<void> sendUserMessage(Map<String, Object?> message) => send(message);

  /// Runs `sendControl`.
  Future<void> sendControl(Map<String, Object?> control) => send(control);

  /// Runs `close`.
  Future<void> close() async {
    if (_closing) {
      return;
    }
    _log.t('Closing stream-json transport');
    _closing = true;
    final process = _process;
    if (process != null) {
      try {
        await _writeQueue;
      } on Object catch (_) {
        // 关闭时尽力等待进行中的写入。
      }
      try {
        await process.stdin.close();
      } on Object catch (_) {}
      process.kill();
      try {
        await process.exitCode.timeout(exitTimeout);
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    await _closeControllers();
  }

  void _onStdoutBytes(String chunk) {
    if (_closing) {
      return;
    }
    final result = _stdoutLines.push(chunk, maxLineBytes: maxLineBytes);
    for (final oversize in result.oversizeLengths) {
      _emitProtocolError(
        StreamJsonProtocolException(
          'Stream-json stdout line exceeds max size',
          payloadLength: oversize,
        ),
      );
    }
    result.lines.forEach(_handleStdoutLine);
  }

  void _onStderrBytes(String chunk) {
    if (_closing) {
      return;
    }
    final result = _stderrLinesAcc.push(chunk, maxLineBytes: maxLineBytes);
    for (final oversize in result.oversizeLengths) {
      _emitProtocolError(
        StreamJsonProtocolException(
          'Stream-json stderr line exceeds max size',
          payloadLength: oversize,
        ),
      );
    }
    for (final line in result.lines) {
      if (line.trim().isEmpty) {
        continue;
      }
      _log.t('Received stream-json stderr line (${line.length} characters)');
      if (!_stderrLines.isClosed) {
        _stderrLines.add(line);
      }
    }
  }

  void _handleStdoutLine(String line) {
    if (line.trim().isEmpty) {
      return;
    }
    final payloadLength = line.length;
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on Object catch (error) {
      _log.w(
        'Invalid stream-json stdout line '
        '(${error.runtimeType}, $payloadLength characters)',
      );
      _emitProtocolError(
        StreamJsonProtocolException(
          'Invalid JSON on stdout',
          payloadLength: payloadLength,
          causeType: error.runtimeType.toString(),
        ),
      );
      return;
    }
    if (decoded is! Map) {
      _emitProtocolError(
        StreamJsonProtocolException(
          'Stream-json stdout message was not an object',
          payloadLength: payloadLength,
        ),
      );
      return;
    }
    final raw = <String, Object?>{
      for (final entry in decoded.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    final type = raw['type'];
    if (type is! String || type.isEmpty) {
      _emitProtocolError(
        StreamJsonProtocolException(
          'Stream-json stdout missing type',
          payloadLength: payloadLength,
        ),
      );
      return;
    }
    final subtype = raw['subtype'];
    if (!_events.isClosed) {
      _events.add(
        StreamJsonEvent(
          type: type,
          subtype: subtype is String ? subtype : null,
          raw: raw,
        ),
      );
    }
  }

  void _emitProtocolError(StreamJsonProtocolException error) {
    if (!_protocolErrors.isClosed) {
      _protocolErrors.add(error);
    }
  }

  void _handleStdoutDone() {
    final trailing = _stdoutLines.flushTrailing();
    if (trailing != null) {
      _handleStdoutLine(trailing);
    }
  }

  void _handleStderrDone() {
    final trailing = _stderrLinesAcc.flushTrailing();
    if (trailing != null &&
        trailing.trim().isNotEmpty &&
        !_stderrLines.isClosed) {
      _stderrLines.add(trailing);
    }
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    _log.w('Stream-json IO error (${error.runtimeType})');
    _emitProtocolError(
      StreamJsonProtocolException(
        'Stream-json IO error',
        causeType: error.runtimeType.toString(),
      ),
    );
  }

  Future<void> _watchExit(Process process) async {
    final code = await process.exitCode;
    _log.i('Stream-json process exited with code $code');
    if (!_closing) {
      _closing = true;
      await _stdoutSubscription?.cancel();
      await _stderrSubscription?.cancel();
      await _closeControllers();
    }
  }

  void _ensureOpen() {
    if (!_started || _closing || _process == null) {
      throw const StreamJsonTransportClosedException(
        'Stream-json transport is not open',
      );
    }
  }

  Future<void> _closeControllers() async {
    await Future.wait(<Future<void>>[
      if (!_events.isClosed) _events.close(),
      if (!_stderrLines.isClosed) _stderrLines.close(),
      if (!_protocolErrors.isClosed) _protocolErrors.close(),
    ]);
  }
}

class _LinePushResult {
  const _LinePushResult({required this.lines, required this.oversizeLengths});

  final List<String> lines;
  final List<int> oversizeLengths;
}

/// 跨 chunk 拼行，并在超过 `maxLineBytes` 时丢弃该行并上报长度。
class _LineAccumulator {
  final StringBuffer _buffer = StringBuffer();
  bool _dropping = false;
  int _droppedLength = 0;

  _LinePushResult push(String chunk, {required int maxLineBytes}) {
    final lines = <String>[];
    final oversize = <int>[];
    for (var i = 0; i < chunk.length; i++) {
      final ch = chunk[i];
      if (ch == '\n') {
        if (_dropping) {
          oversize.add(_droppedLength);
          _dropping = false;
          _droppedLength = 0;
          _buffer.clear();
        } else {
          var line = _buffer.toString();
          _buffer.clear();
          if (line.endsWith('\r')) {
            line = line.substring(0, line.length - 1);
          }
          lines.add(line);
        }
        continue;
      }
      if (_dropping) {
        _droppedLength += 1;
        continue;
      }
      _buffer.write(ch);
      if (_buffer.length > maxLineBytes) {
        _dropping = true;
        _droppedLength = _buffer.length;
        _buffer.clear();
      }
    }
    return _LinePushResult(lines: lines, oversizeLengths: oversize);
  }

  /// 流结束时若缓冲非空且未在丢弃，返回最后半行。
  String? flushTrailing() {
    if (_dropping) {
      _dropping = false;
      _droppedLength = 0;
      _buffer.clear();
      return null;
    }
    if (_buffer.isEmpty) {
      return null;
    }
    var line = _buffer.toString();
    _buffer.clear();
    if (line.endsWith('\r')) {
      line = line.substring(0, line.length - 1);
    }
    return line;
  }
}
