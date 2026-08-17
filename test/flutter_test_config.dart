import 'dart:async';

import 'package:logger/logger.dart';
import 'package:zeta/src/core/logging/app_logging.dart';

/// 普通测试默认只输出 warning 以上日志，避免完整套件被 Trace/Info I/O 拖慢。
///
/// 日志功能测试会显式配置自身需要的级别，不依赖此默认值。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  configureAppLogging(level: Level.warning);
  try {
    await testMain();
  } finally {
    await shutdownAppLogging();
  }
}
