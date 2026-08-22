import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart' as logger;

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/core/logging/structured_error_logging.dart';
import 'package:zeta/src/core/security/sensitive_data_redactor.dart';

/// 统一的应用日志器。
///
/// 业务代码不直接依赖第三方 `logger` 实例；日志级别、格式化器、输出和
/// 文件落盘策略都由 [configureAppLogging] 统一配置。每个实例只携带一个
/// 稳定的 scope，方便在默认终端输出和文件日志中定位来源。
final class AppLogger implements ZetaLogger {
  AppLogger._(this.name) : _logger = logger.Logger();

  /// 当前日志器的稳定 scope。
  final String name;
  final logger.Logger _logger;

  /// 记录 trace 级别日志。
  @override
  void t(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.t(
      _messageWithScope(message),
      time: time,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// 记录 debug 级别日志。
  @override
  void d(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.d(
      _messageWithScope(message),
      time: time,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// 记录 info 级别日志。
  @override
  void i(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.i(
      _messageWithScope(message),
      time: time,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// 记录 warning 级别日志。
  @override
  void w(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.w(
      _messageWithScope(message),
      time: time,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// 记录 error 级别日志。
  @override
  void e(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.e(
      _messageWithScope(message),
      time: time,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// 记录 fatal 级别日志。
  void f(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.f(
      _messageWithScope(message),
      time: time,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// 记录指定级别的日志。
  void log(
    logger.Level level,
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.log(
      level,
      _messageWithScope(message),
      time: time,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// 记录带结构化脱敏上下文的失败（[ZetaLogger.failure] 的应用实现）。
  @override
  void failure(
    String message, {
    Map<String, Object?> context = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    logStructuredFailure(
      this,
      message: message,
      context: context,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// 关闭当前 logger 实例。
  Future<void> close() => _logger.close();

  /// 当前实例是否已关闭。
  bool isClosed() => _logger.isClosed();

  String _messageWithScope(dynamic message) {
    final value = message is Function
        ? Function.apply(message, const <Object?>[])
        : message;
    return '[zeta] [$name] $value';
  }
}

ZetaFileLogOutput? _fileLogOutput;
Future<void> _retiredFileLogDrain = Future<void>.value();

/// 确保第三方 logger 的默认组件只在统一入口配置一次。
///
/// 顶层 logger 会惰性初始化，不能依赖 import 副作用；因此由
/// [loggerFor] 和 [configureAppLogging] 显式调用。
bool _loggingDefaultsWired = false;

void ensureLoggingDefaults() {
  if (_loggingDefaultsWired) {
    return;
  }
  _loggingDefaultsWired = true;
  // ConsoleOutput 保持默认；Printer 用无框线、整行按级别着色的控制台格式。
  // Filter 替换 DevelopmentFilter，保证 release 仍按级别输出。
  logger.Logger.defaultFilter = () => _ZetaLogFilter();
  logger.Logger.defaultPrinter = () => ZetaConsolePrinter();
  logger.Logger.addOutputListener(_writeFileLog);
}

/// 配置应用日志。
///
/// 控制台使用 [ZetaConsolePrinter]（无框、整行着色、同样脱敏）；当 [logDirectory]
/// 非空时，同时按本地日期追加脱敏文件日志。未传入 [level] 时，debug/profile
/// 保留全部日志，release 默认只保留 warning 及以上级别。
void configureAppLogging({logger.Level? level, Directory? logDirectory}) {
  ensureLoggingDefaults();
  // 内部 Package 只依赖 zeta_foundation 的日志端口；这里把实现接上去。
  ZetaLogging.install(loggerFor);
  logger.Logger.level =
      level ?? (kReleaseMode ? logger.Level.warning : logger.Level.all);
  _retireFileLogOutput();
  _fileLogOutput = logDirectory == null
      ? null
      : ZetaFileLogOutput(logDirectory, initialBarrier: _retiredFileLogDrain);
}

/// 返回指定 scope 的统一应用日志器。
AppLogger loggerFor(String name) {
  ensureLoggingDefaults();
  return AppLogger._(_normalizeLoggerName(name));
}

/// 等待已经进入文件输出队列的日志完成写入。
Future<void> flushAppLogging() async {
  await _retiredFileLogDrain;
  final output = _fileLogOutput;
  if (output != null) {
    await output.flush();
  }
}

/// 停止文件输出并等待已经排队的日志完成写入。
Future<void> shutdownAppLogging() async {
  _retireFileLogOutput();
  await _retiredFileLogDrain;
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

@visibleForTesting
Future<void> resetAppLoggingForTesting() async {
  await shutdownAppLogging();
  _retiredFileLogDrain = Future<void>.value();
  logger.Logger.level = logger.Level.info;
}

/// 统一的过滤：按 [logger.Logger.level] 过滤，release 模式同样生效。
///
/// `logger` 包的默认 [logger.DevelopmentFilter] 会在 release 下丢弃全部日志，
/// 这里改为仅按统一级别过滤，保证 warning/error 仍能进入正式日志。
class _ZetaLogFilter extends logger.LogFilter {
  @override
  bool shouldLog(logger.LogEvent event) {
    final currentLevel = level;
    if (currentLevel == null) {
      return true;
    }
    return event.level >= currentLevel;
  }
}

/// 无框控制台输出：整行按日志级别着色（不只是级别前缀）。
///
/// **控制台与文件输出使用同一条脱敏链路**：`event.error` 是原始异常对象，
/// `toString()` 里经常带 token、密码或本机路径。早期实现只脱敏文件输出，
/// 控制台把原文直接打出来——同一条日志两种保护强度，等于没有保护。
@visibleForTesting
final class ZetaConsolePrinter extends logger.LogPrinter {
  static const _levelPrefixes = <logger.Level, String>{
    logger.Level.trace: '[T]',
    logger.Level.debug: '[D]',
    logger.Level.info: '[I]',
    logger.Level.warning: '[W]',
    logger.Level.error: '[E]',
    logger.Level.fatal: '[FATAL]',
  };

  static final _levelColors = <logger.Level, logger.AnsiColor>{
    logger.Level.trace: logger.AnsiColor.fg(logger.AnsiColor.grey(0.5)),
    logger.Level.debug: const logger.AnsiColor.none(),
    logger.Level.info: const logger.AnsiColor.fg(12),
    logger.Level.warning: const logger.AnsiColor.fg(208),
    logger.Level.error: const logger.AnsiColor.fg(196),
    logger.Level.fatal: const logger.AnsiColor.fg(199),
  };

  @override
  List<String> log(logger.LogEvent event) {
    final prefix = _levelPrefixes[event.level] ?? '[?]';
    // 类型必须保留（诊断的主要价值），文本必须脱敏（原始异常常带 token/路径）。
    final error = event.error == null
        ? ''
        : '  ERROR: ${event.error.runtimeType}: '
              '${redactSensitiveText(event.error.toString())}';
    final message = redactSensitiveText('${event.message}');
    final line = '$prefix $message$error';
    final color = _levelColors[event.level] ?? const logger.AnsiColor.none();
    return <String>[color(line)];
  }
}

void _writeFileLog(logger.OutputEvent event) {
  _fileLogOutput?.add(event);
}

/// 按天轮转的文本文件输出。
class ZetaFileLogOutput {
  ZetaFileLogOutput(this.logDirectory, {Future<void>? initialBarrier})
    : _writeQueue = initialBarrier ?? Future<void>.value();

  final Directory logDirectory;
  Future<void> _writeQueue;
  bool _isClosed = false;

  void add(logger.OutputEvent event) {
    if (_isClosed) {
      return;
    }
    final fileName = _dailyLogFileName(event.origin.time.toLocal());
    final line = _formatFileLogRecord(event);
    _writeQueue = _writeQueue
        .then((_) => _append(fileName: fileName, line: line))
        .catchError((Object error, StackTrace stackTrace) {
          // 文件日志故障不能再次进入根 logger，否则会递归触发同一个 sink。
          developer.log(
            'Could not write Zeta file log',
            name: 'zeta.logging.file',
            error: error.runtimeType,
            stackTrace: stackTrace,
          );
        });
  }

  Future<void> flush() => _writeQueue;

  Future<void> destroy() async {
    _isClosed = true;
    await _writeQueue;
  }

  Future<void> _append({required String fileName, required String line}) async {
    await logDirectory.create(recursive: true);
    final separator = logDirectory.path.endsWith(Platform.pathSeparator)
        ? ''
        : Platform.pathSeparator;
    final file = File('${logDirectory.path}$separator$fileName');
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
  final rendered = '${_formatLogHeader(origin)} ${origin.message}';
  final message = _escapeLogValue(redactSensitiveText(rendered));
  final buffer = StringBuffer(message);
  final error = origin.error;
  if (error != null) {
    // error.toString() 可能携带 prompt、协议 payload 或凭据，只持久化类型。
    buffer
      ..write(' error=')
      ..write(error.runtimeType);
  }
  final stackTrace = origin.stackTrace;
  if (stackTrace != null) {
    buffer
      ..write(' stack=')
      ..write(_escapeLogValue(redactSensitiveText(stackTrace.toString())));
  }
  return buffer.toString();
}

String _formatLogHeader(logger.LogEvent event) {
  return '${_formatLogTime(event.time)} [${event.level.name}]';
}

String _formatLogTime(DateTime time) {
  final localTime = time.toLocal();
  final year = localTime.year.toString().padLeft(4, '0');
  final month = localTime.month.toString().padLeft(2, '0');
  final day = localTime.day.toString().padLeft(2, '0');
  final hour = localTime.hour.toString().padLeft(2, '0');
  final minute = localTime.minute.toString().padLeft(2, '0');
  final second = localTime.second.toString().padLeft(2, '0');
  final millisecond = localTime.millisecond.toString().padLeft(3, '0');
  return '$year-$month-$day $hour:$minute:$second.$millisecond';
}

String _escapeLogValue(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n');
}

String _normalizeLoggerName(String name) {
  final normalized = name.replaceAll(RegExp(r'[\r\n]'), ' ').trim();
  return normalized.isEmpty ? 'zeta' : normalized;
}
