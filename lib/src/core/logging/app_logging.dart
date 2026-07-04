import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

typedef AppLogSink = void Function(LogRecord record);

StreamSubscription<LogRecord>? _rootLogSubscription;

void configureAppLogging({Level? level, AppLogSink? sink}) {
  final previousSubscription = _rootLogSubscription;
  _rootLogSubscription = null;
  unawaited(previousSubscription?.cancel());

  Logger.root.level = level ?? (kReleaseMode ? Level.WARNING : Level.ALL);
  _rootLogSubscription = Logger.root.onRecord.listen(
    sink ?? _writeDeveloperLog,
  );
}

Logger loggerFor(String name) => Logger(name);

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

@visibleForTesting
Future<void> resetAppLoggingForTesting() async {
  final previousSubscription = _rootLogSubscription;
  _rootLogSubscription = null;
  await previousSubscription?.cancel();
  Logger.root.level = Level.INFO;
}
