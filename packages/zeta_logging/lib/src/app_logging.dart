import 'dart:developer' as developer;
import 'dart:io';

import 'package:logger/logger.dart' as logger;
import 'package:zeta_logging/src/sensitive_data_redactor.dart';

const _isProductMode = bool.fromEnvironment('dart.vm.product');

/// A scoped logger that sanitizes every event before it reaches any sink.
final class AppLogger {
  AppLogger._(this.name) : _logger = logger.Logger();

  /// The normalized diagnostic scope.
  final String name;
  final logger.Logger _logger;

  /// Writes a trace event.
  void t(
    Object? message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) => _emit(
    logger.Level.trace,
    message,
    time: time,
    error: error,
    stackTrace: stackTrace,
  );

  /// Writes a debug event.
  void d(
    Object? message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) => _emit(
    logger.Level.debug,
    message,
    time: time,
    error: error,
    stackTrace: stackTrace,
  );

  /// Writes an info event.
  void i(
    Object? message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) => _emit(
    logger.Level.info,
    message,
    time: time,
    error: error,
    stackTrace: stackTrace,
  );

  /// Writes a warning event.
  void w(
    Object? message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) => _emit(
    logger.Level.warning,
    message,
    time: time,
    error: error,
    stackTrace: stackTrace,
  );

  /// Writes an error event.
  void e(
    Object? message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) => _emit(
    logger.Level.error,
    message,
    time: time,
    error: error,
    stackTrace: stackTrace,
  );

  /// Writes a fatal event.
  void f(
    Object? message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) => _emit(
    logger.Level.fatal,
    message,
    time: time,
    error: error,
    stackTrace: stackTrace,
  );

  /// Writes an event at [level].
  void log(
    logger.Level level,
    Object? message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) => _emit(
    level,
    message,
    time: time,
    error: error,
    stackTrace: stackTrace,
  );

  /// Closes this logger instance.
  Future<void> close() => _logger.close();

  /// Whether this logger instance is closed.
  bool get isClosed => _logger.isClosed();

  void _emit(
    logger.Level level,
    Object? message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.log(
      level,
      _messageWithScope(message),
      time: time,
      error: error == null ? null : _safeErrorLabel(error),
      stackTrace: stackTrace == null
          ? null
          : StackTrace.fromString(redactSensitiveText(stackTrace.toString())),
    );
  }

  String _messageWithScope(Object? message) {
    Object? value;
    try {
      value = message is Function
          ? Function.apply(message, const <Object?>[])
          : message;
    } on Object {
      value = '<message callback failed>';
    }
    return redactSensitiveText('[zeta] [$name] $value');
  }
}

_ZetaFileLogOutput? _fileLogOutput;
Future<void> _retiredFileLogDrain = Future<void>.value();
bool _loggingDefaultsWired = false;

/// Ensures the package-owned filter, printer, and file listener are installed.
void ensureLoggingDefaults() {
  if (_loggingDefaultsWired) {
    return;
  }
  _loggingDefaultsWired = true;
  logger.Logger.defaultFilter = _ZetaLogFilter.new;
  logger.Logger.defaultPrinter = _ZetaConsolePrinter.new;
  logger.Logger.addOutputListener(_writeFileLog);
}

/// Configures the global log level and optional daily file sink.
void configureAppLogging({
  logger.Level? level,
  Directory? logDirectory,
}) {
  ensureLoggingDefaults();
  logger.Logger.level =
      level ?? (_isProductMode ? logger.Level.warning : logger.Level.all);
  _retireFileLogOutput();
  _fileLogOutput = logDirectory == null
      ? null
      : _ZetaFileLogOutput(logDirectory, initialBarrier: _retiredFileLogDrain);
}

/// Creates a scoped application logger.
AppLogger loggerFor(String name) {
  ensureLoggingDefaults();
  return AppLogger._(_normalizeLoggerName(name));
}

/// Waits for all file records already accepted by the sink.
Future<void> flushAppLogging() async {
  await _retiredFileLogDrain;
  await _fileLogOutput?.flush();
}

/// Closes the file sink and waits for accepted records.
Future<void> shutdownAppLogging() async {
  _retireFileLogOutput();
  await _retiredFileLogDrain;
}

/// Resets mutable logging state for an isolated test.
Future<void> resetAppLoggingForTesting() async {
  await shutdownAppLogging();
  _retiredFileLogDrain = Future<void>.value();
  logger.Logger.level = logger.Level.info;
}

void _retireFileLogOutput() {
  final previous = _fileLogOutput;
  _fileLogOutput = null;
  if (previous == null) {
    return;
  }
  final previousDrain = _retiredFileLogDrain;
  _retiredFileLogDrain = Future.wait<void>(<Future<void>>[
    previousDrain,
    previous.destroy(),
  ]);
}

final class _ZetaLogFilter extends logger.LogFilter {
  @override
  bool shouldLog(logger.LogEvent event) {
    final currentLevel = level;
    return currentLevel == null || event.level >= currentLevel;
  }
}

final class _ZetaConsolePrinter extends logger.LogPrinter {
  static const _levelPrefixes = <logger.Level, String>{
    logger.Level.trace: '[T]',
    logger.Level.debug: '[D]',
    logger.Level.info: '[I]',
    logger.Level.warning: '[W]',
    logger.Level.error: '[E]',
    logger.Level.fatal: '[FATAL]',
  };

  @override
  List<String> log(logger.LogEvent event) {
    final prefix = _levelPrefixes[event.level] ?? '[?]';
    final error = event.error == null
        ? ''
        : ' ERROR: ${_safeErrorLabel(event.error!)}';
    return <String>[redactSensitiveText('$prefix ${event.message}$error')];
  }
}

void _writeFileLog(logger.OutputEvent event) {
  _fileLogOutput?.add(event);
}

final class _ZetaFileLogOutput {
  _ZetaFileLogOutput(
    this.logDirectory, {
    required Future<void> initialBarrier,
  }) : _writeQueue = initialBarrier;

  final Directory logDirectory;
  Future<void> _writeQueue;

  void add(logger.OutputEvent event) {
    final fileName = _dailyLogFileName(event.origin.time.toLocal());
    final line = _formatFileLogRecord(event);
    _writeQueue = _writeQueue
        .then((_) => _append(fileName: fileName, line: line))
        .catchError((Object error, StackTrace stackTrace) {
          developer.log(
            'Could not write Zeta file log',
            name: 'zeta.logging.file',
            error: _safeErrorCategory(error),
            stackTrace: StackTrace.fromString(
              redactSensitiveText(stackTrace.toString()),
            ),
          );
        });
  }

  Future<void> flush() => _writeQueue;

  Future<void> destroy() => _writeQueue;

  Future<void> _append({required String fileName, required String line}) async {
    await logDirectory.create(recursive: true);
    final file = File('${logDirectory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }
}

String _dailyLogFileName(DateTime localTime) {
  final month = localTime.month.toString().padLeft(2, '0');
  final day = localTime.day.toString().padLeft(2, '0');
  return 'zeta-${localTime.year}-$month-$day.log';
}

String _formatFileLogRecord(logger.OutputEvent event) {
  final origin = event.origin;
  final rendered =
      '${_formatLogTime(origin.time)} [${origin.level.name}] '
      '${origin.message}';
  final buffer = StringBuffer(_escapeLogValue(redactSensitiveText(rendered)));
  if (origin.error != null) {
    buffer.write(' error=${_safeErrorLabel(origin.error!)}');
  }
  if (origin.stackTrace case final stackTrace?) {
    buffer.write(
      ' stack=${_escapeLogValue(redactSensitiveText(stackTrace.toString()))}',
    );
  }
  return buffer.toString();
}

String _formatLogTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final millis = local.millisecond.toString().padLeft(3, '0');
  return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-'
      '${two(local.day)} ${two(local.hour)}:${two(local.minute)}:'
      '${two(local.second)}.$millis';
}

String _escapeLogValue(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n');
}

String _normalizeLoggerName(String name) {
  final normalized = redactSensitiveText(
    name.replaceAll(RegExp(r'[\r\n]'), ' ').trim(),
  );
  return normalized.isEmpty ? 'zeta' : normalized;
}

String _safeErrorCategory(Object error) {
  if (error is Error) {
    return 'Error';
  }
  if (error is Exception) {
    return 'Exception';
  }
  return 'Object';
}

String _safeErrorLabel(Object error) {
  if (error is String &&
      const <String>{'Error', 'Exception', 'Object'}.contains(error)) {
    return error;
  }
  return _safeErrorCategory(error);
}
