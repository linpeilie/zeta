import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:zeta/src/core/security/sensitive_data_redactor.dart';

typedef AppLogSink = void Function(LogRecord record);

StreamSubscription<LogRecord>? _rootLogSubscription;
_DailyFileLogSink? _dailyFileLogSink;
Future<void> _retiredFileLogDrain = Future<void>.value();

/// 配置应用根日志。
///
/// 未显式传入 [sink] 时保留 developer 日志，并在 [logDirectory] 非空时同时追加
/// 每日文件日志。测试等调用方显式传入 [sink] 时只向该 sink 转发，沿用原有注入语义。
void configureAppLogging({
  Level? level,
  AppLogSink? sink,
  Directory? logDirectory,
}) {
  final previousSubscription = _rootLogSubscription;
  _rootLogSubscription = null;
  unawaited(previousSubscription?.cancel());
  _retireDailyFileLogSink();

  Logger.root.level = level ?? (kReleaseMode ? Level.WARNING : Level.ALL);
  if (sink != null) {
    _rootLogSubscription = Logger.root.onRecord.listen(sink);
    return;
  }

  final dailyFileLogSink = logDirectory == null
      ? null
      : _DailyFileLogSink(logDirectory, initialBarrier: _retiredFileLogDrain);
  _dailyFileLogSink = dailyFileLogSink;
  _rootLogSubscription = Logger.root.onRecord.listen((record) {
    _writeDeveloperLog(record);
    dailyFileLogSink?.add(record);
  });
}

/// 返回指定名称的应用日志器。
Logger loggerFor(String name) => Logger(name);

/// 等待已经进入文件 sink 的日志完成写入。
///
/// 此方法不会停止接收新记录；应用退出应使用 [shutdownAppLogging]。
Future<void> flushAppLogging() async {
  await _retiredFileLogDrain;
  await _dailyFileLogSink?.flush();
}

/// 停止接收新的根日志，并排空当前文件写入队列。
///
/// 仅用于应用正常退出；完成后需重新调用 [configureAppLogging] 才会恢复记录。
Future<void> shutdownAppLogging() async {
  final previousSubscription = _rootLogSubscription;
  _rootLogSubscription = null;
  await previousSubscription?.cancel();
  _retireDailyFileLogSink();
  await _retiredFileLogDrain;
}

void _writeDeveloperLog(LogRecord record) {
  developer.log(
    record.message,
    time: record.time,
    sequenceNumber: record.sequenceNumber,
    level: record.level.value,
    name: record.loggerName,
    error: record.error,
    stackTrace: record.stackTrace,
  );
}

void _retireDailyFileLogSink() {
  final previousSink = _dailyFileLogSink;
  _dailyFileLogSink = null;
  if (previousSink == null) {
    return;
  }
  final previousDrain = _retiredFileLogDrain;
  _retiredFileLogDrain = Future.wait<void>(<Future<void>>[
    previousDrain,
    previousSink.close(),
  ]);
}

@visibleForTesting
Future<void> resetAppLoggingForTesting() async {
  await shutdownAppLogging();
  _retiredFileLogDrain = Future<void>.value();
  Logger.root.level = Level.INFO;
}

class _DailyFileLogSink {
  _DailyFileLogSink(this.logDirectory, {Future<void>? initialBarrier})
    : _writeQueue = initialBarrier ?? Future<void>.value();

  final Directory logDirectory;
  Future<void> _writeQueue;
  bool _isClosed = false;

  void add(LogRecord record) {
    if (_isClosed) {
      return;
    }
    final fileName = _dailyLogFileName(record.time.toLocal());
    final line = _formatFileLogRecord(record);
    _writeQueue = _writeQueue
        .then((_) => _append(fileName: fileName, line: line))
        .catchError((Object error, StackTrace stackTrace) {
          // 文件日志故障不能再次进入根 Logger，否则会递归触发同一个 sink。
          developer.log(
            'Could not write Zeta file log',
            name: 'zeta.logging.file',
            error: error.runtimeType,
            stackTrace: stackTrace,
          );
        });
  }

  Future<void> close() async {
    _isClosed = true;
    await _writeQueue;
  }

  Future<void> flush() => _writeQueue;

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

String _formatFileLogRecord(LogRecord record) {
  final localTime = record.time.toLocal().toIso8601String();
  final message = _escapeLogValue(redactSensitiveText(record.message));
  final buffer = StringBuffer()
    ..write(localTime)
    ..write(' [')
    ..write(record.level.name)
    ..write('] [')
    ..write(record.loggerName)
    ..write('] ')
    ..write(message);
  final error = record.error;
  if (error != null) {
    // error.toString() 可能携带 prompt、协议 payload 或凭据，只持久化类型。
    buffer
      ..write(' error=')
      ..write(error.runtimeType);
  }
  final stackTrace = record.stackTrace;
  if (stackTrace != null) {
    buffer
      ..write(' stack=')
      ..write(_escapeLogValue(redactSensitiveText(stackTrace.toString())));
  }
  return buffer.toString();
}

String _escapeLogValue(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n');
}
