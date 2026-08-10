import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/codex_usage_log_scanner.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/grok_usage_log_scanner.dart';

/// 多 Provider 分区的使用统计派生索引版本。
const int usageStatisticsIndexVersion = 3;

/// 兼容读取的旧版（仅 Codex 顶层 sessions）版本号。
const int usageStatisticsIndexLegacyVersion = 2;

/// 使用统计派生索引的旧版 shared_preferences key。
const String usageStatisticsIndexStorageKey = 'usage_statistics.index.v2';

/// 多 Provider 使用统计派生索引快照。
///
/// Codex / Grok 分区各自以 `sourceId` 为键；序列化时不写 session 文件路径。
class UsageStatisticsIndexSnapshot {
  const UsageStatisticsIndexSnapshot({
    this.codexSessions = const <String, CodexUsageSessionSnapshot>{},
    this.grokSessions = const <String, GrokUsageIndexedSession>{},
  });

  /// Codex 分区；key 为 [usageSourceId]（内存中可能短暂为 path）。
  final Map<String, CodexUsageSessionSnapshot> codexSessions;

  /// Grok 分区；key 为 [usageSourceId]（内存中可能短暂为 path）。
  final Map<String, GrokUsageIndexedSession> grokSessions;

  /// 兼容旧调用点：等同 [codexSessions]。
  Map<String, CodexUsageSessionSnapshot> get sessions => codexSessions;

  UsageStatisticsIndexSnapshot copyWith({
    Map<String, CodexUsageSessionSnapshot>? codexSessions,
    Map<String, GrokUsageIndexedSession>? grokSessions,
  }) {
    return UsageStatisticsIndexSnapshot(
      codexSessions: codexSessions ?? this.codexSessions,
      grokSessions: grokSessions ?? this.grokSessions,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': usageStatisticsIndexVersion,
    'providers': <String, Object?>{
      'codex': <String, Object?>{
        'sessions': codexSessions.values
            .map((session) => session.toJson())
            .toList(),
      },
      'grok': <String, Object?>{
        'sessions': grokSessions.values
            .map((session) => session.toJson())
            .toList(),
      },
    },
  };

  static UsageStatisticsIndexSnapshot tryDecode(Object? value) {
    final map = _objectMap(value);
    final version = _int(map['version']);
    if (version == usageStatisticsIndexLegacyVersion) {
      return _decodeLegacyV2(map);
    }
    if (version != usageStatisticsIndexVersion) {
      return const UsageStatisticsIndexSnapshot();
    }
    final providers = _objectMap(map['providers']);
    return UsageStatisticsIndexSnapshot(
      codexSessions: _decodeCodexSessions(_objectMap(providers['codex'])),
      grokSessions: _decodeGrokSessions(_objectMap(providers['grok'])),
    );
  }

  static UsageStatisticsIndexSnapshot _decodeLegacyV2(
    Map<String, Object?> map,
  ) {
    return UsageStatisticsIndexSnapshot(
      codexSessions: _decodeCodexSessionList(map['sessions']),
    );
  }

  static Map<String, CodexUsageSessionSnapshot> _decodeCodexSessions(
    Map<String, Object?> partition,
  ) {
    return _decodeCodexSessionList(partition['sessions']);
  }

  static Map<String, CodexUsageSessionSnapshot> _decodeCodexSessionList(
    Object? rawSessions,
  ) {
    final sessions = <String, CodexUsageSessionSnapshot>{};
    if (rawSessions is List) {
      for (final rawSession in rawSessions) {
        final session = CodexUsageSessionSnapshot.tryDecode(rawSession);
        if (session != null) {
          sessions[session.sourceId] = session;
        }
      }
    }
    return Map<String, CodexUsageSessionSnapshot>.unmodifiable(sessions);
  }

  static Map<String, GrokUsageIndexedSession> _decodeGrokSessions(
    Map<String, Object?> partition,
  ) {
    final sessions = <String, GrokUsageIndexedSession>{};
    final rawSessions = partition['sessions'];
    if (rawSessions is List) {
      for (final rawSession in rawSessions) {
        final session = GrokUsageIndexedSession.tryDecode(rawSession);
        if (session != null) {
          sessions[session.sourceId] = session;
        }
      }
    }
    return Map<String, GrokUsageIndexedSession>.unmodifiable(sessions);
  }
}

abstract class UsageStatisticsIndexStore {
  Future<UsageStatisticsIndexSnapshot> load();

  Future<void> save(UsageStatisticsIndexSnapshot snapshot);

  /// 按 Provider 分区合并写回，避免并行 refresh 互相覆盖。
  Future<void> mergeSave({
    Map<String, CodexUsageSessionSnapshot>? codexSessions,
    Map<String, GrokUsageIndexedSession>? grokSessions,
  });
}

/// 基于 JSON 文件的生产统计索引仓库。
class FileUsageStatisticsIndexStore implements UsageStatisticsIndexStore {
  FileUsageStatisticsIndexStore({required File file})
    : _storage = AtomicTextFile(file);

  final AtomicTextFile _storage;
  final _AsyncMutex _mutex = _AsyncMutex();

  @override
  Future<UsageStatisticsIndexSnapshot> load() async {
    try {
      final encoded = await _storage.read();
      if (encoded == null || encoded.trim().isEmpty) {
        return const UsageStatisticsIndexSnapshot();
      }
      return UsageStatisticsIndexSnapshot.tryDecode(jsonDecode(encoded));
    } on FormatException {
      // 索引损坏不能阻止应用启动；下一次加载会从 Provider 历史重建。
      return const UsageStatisticsIndexSnapshot();
    } on IOException {
      // 索引文件不可读时同样回退重建，不阻断统计页或应用启动。
      return const UsageStatisticsIndexSnapshot();
    } catch (_) {
      // 合法 JSON 也可能包含越界时间戳等损坏字段，统一视为可重建索引。
      return const UsageStatisticsIndexSnapshot();
    }
  }

  @override
  Future<void> save(UsageStatisticsIndexSnapshot snapshot) async {
    await _storage.write(jsonEncode(snapshot.toJson()));
  }

  @override
  Future<void> mergeSave({
    Map<String, CodexUsageSessionSnapshot>? codexSessions,
    Map<String, GrokUsageIndexedSession>? grokSessions,
  }) {
    return _mutex.synchronized(() async {
      final current = await load();
      await save(
        UsageStatisticsIndexSnapshot(
          codexSessions: codexSessions ?? current.codexSessions,
          grokSessions: grokSessions ?? current.grokSessions,
        ),
      );
    });
  }
}

class MemoryUsageStatisticsIndexStore implements UsageStatisticsIndexStore {
  UsageStatisticsIndexSnapshot snapshot = const UsageStatisticsIndexSnapshot();
  final _AsyncMutex _mutex = _AsyncMutex();

  @override
  Future<UsageStatisticsIndexSnapshot> load() async => snapshot;

  @override
  Future<void> save(UsageStatisticsIndexSnapshot value) async {
    snapshot = value;
  }

  @override
  Future<void> mergeSave({
    Map<String, CodexUsageSessionSnapshot>? codexSessions,
    Map<String, GrokUsageIndexedSession>? grokSessions,
  }) {
    return _mutex.synchronized(() async {
      final current = await load();
      snapshot = UsageStatisticsIndexSnapshot(
        codexSessions: codexSessions ?? current.codexSessions,
        grokSessions: grokSessions ?? current.grokSessions,
      );
    });
  }
}

/// 进程内串行化异步临界区，保证 index 的 read-modify-write 不交错。
class _AsyncMutex {
  Future<void> _tail = Future<void>.value();

  Future<T> synchronized<T>(Future<T> Function() action) {
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    return previous.catchError((_) {}).then((_) => action()).whenComplete(() {
      if (!gate.isCompleted) {
        gate.complete();
      }
    });
  }
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

int? _int(Object? value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  String() => int.tryParse(value),
  _ => null,
};
