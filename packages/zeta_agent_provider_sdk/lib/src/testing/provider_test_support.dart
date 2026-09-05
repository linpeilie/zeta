import 'dart:async';
import 'dart:io';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// 测试用 Provider 配置仓库；调用方显式传入初始设置，不猜内置厂商。
class MemoryAgentProviderConfigStore implements AgentProviderConfigStore {
  MemoryAgentProviderConfigStore(AgentProviderSettings settings)
    : _settings = settings;

  AgentProviderSettings _settings;

  @override
  Future<AgentProviderSettings> load() async => _settings;

  @override
  Future<void> save(AgentProviderSettings settings) async {
    _settings = settings;
  }
}

/// 测试用模型目录缓存。
class MemoryAgentModelCatalogCacheStore implements AgentModelCatalogCacheStore {
  MemoryAgentModelCatalogCacheStore([
    List<AgentModelCatalogSnapshot> snapshots =
        const <AgentModelCatalogSnapshot>[],
  ]) : _snapshots = List<AgentModelCatalogSnapshot>.from(snapshots);

  List<AgentModelCatalogSnapshot> _snapshots;

  @override
  Future<List<AgentModelCatalogSnapshot>> load() async =>
      List<AgentModelCatalogSnapshot>.unmodifiable(_snapshots);

  @override
  Future<void> save(List<AgentModelCatalogSnapshot> snapshots) async {
    _snapshots = List<AgentModelCatalogSnapshot>.from(snapshots);
  }
}

/// 测试专用文件存储，保留生产实现的串行写入与同目录原子替换语义。
final class FileTestStorageService implements StorageService {
  FileTestStorageService(this.file);

  final File file;
  Future<void> _writeTail = Future<void>.value();

  @override
  Future<String?> read() async {
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String value) {
    final operation = _writeTail.then((_) => _writeAtomically(value));
    _writeTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _writeAtomically(String value) async {
    await file.parent.create(recursive: true);
    final temporaryFile = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporaryFile.writeAsString(value, flush: true);
      await temporaryFile.rename(file.path);
    } finally {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }
}

/// 一条不含 payload 正文的测试日志记录。
final class RecordedZetaLog {
  const RecordedZetaLog({
    required this.scope,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final String scope;
  final String level;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
}

/// 可安装到 [ZetaLogging] 的内存日志工厂。
final class RecordingZetaLoggerFactory {
  RecordingZetaLoggerFactory([List<RecordedZetaLog>? records])
    : records = records ?? <RecordedZetaLog>[];

  final List<RecordedZetaLog> records;

  ZetaLogger call(String scope) => _RecordingZetaLogger(scope, records);
}

final class _RecordingZetaLogger implements ZetaLogger {
  const _RecordingZetaLogger(this.scope, this.records);

  final String scope;
  final List<RecordedZetaLog> records;

  void _record(
    String level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    records.add(
      RecordedZetaLog(
        scope: scope,
        level: level,
        message: message,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  void t(String message, {Object? error, StackTrace? stackTrace}) =>
      _record('trace', message, error: error, stackTrace: stackTrace);

  @override
  void d(String message, {Object? error, StackTrace? stackTrace}) =>
      _record('debug', message, error: error, stackTrace: stackTrace);

  @override
  void i(String message, {Object? error, StackTrace? stackTrace}) =>
      _record('info', message, error: error, stackTrace: stackTrace);

  @override
  void w(String message, {Object? error, StackTrace? stackTrace}) =>
      _record('warning', message, error: error, stackTrace: stackTrace);

  @override
  void e(String message, {Object? error, StackTrace? stackTrace}) =>
      _record('error', message, error: error, stackTrace: stackTrace);

  @override
  void failure(
    String message, {
    Map<String, Object?> context = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) => _record('failure', message, error: error, stackTrace: stackTrace);
}
