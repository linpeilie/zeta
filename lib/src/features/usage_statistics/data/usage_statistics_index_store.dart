import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/codex_usage_log_scanner.dart';

const int usageStatisticsIndexVersion = 2;

/// 使用统计派生索引的旧版 shared_preferences key。
const String usageStatisticsIndexStorageKey = 'usage_statistics.index.v2';

class UsageStatisticsIndexSnapshot {
  const UsageStatisticsIndexSnapshot({
    this.sessions = const <String, CodexUsageSessionSnapshot>{},
  });

  final Map<String, CodexUsageSessionSnapshot> sessions;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': usageStatisticsIndexVersion,
    'sessions': sessions.values.map((session) => session.toJson()).toList(),
  };

  static UsageStatisticsIndexSnapshot tryDecode(Object? value) {
    final map = _objectMap(value);
    if (_int(map['version']) != usageStatisticsIndexVersion) {
      return const UsageStatisticsIndexSnapshot();
    }
    final sessions = <String, CodexUsageSessionSnapshot>{};
    final rawSessions = map['sessions'];
    if (rawSessions is List) {
      for (final rawSession in rawSessions) {
        final session = CodexUsageSessionSnapshot.tryDecode(rawSession);
        if (session != null) {
          sessions[session.sourceId] = session;
        }
      }
    }
    return UsageStatisticsIndexSnapshot(
      sessions: Map<String, CodexUsageSessionSnapshot>.unmodifiable(sessions),
    );
  }
}

abstract class UsageStatisticsIndexStore {
  Future<UsageStatisticsIndexSnapshot> load();

  Future<void> save(UsageStatisticsIndexSnapshot snapshot);
}

/// 基于 JSON 文件的生产统计索引仓库。
class FileUsageStatisticsIndexStore implements UsageStatisticsIndexStore {
  FileUsageStatisticsIndexStore({required File file})
    : _storage = AtomicTextFile(file);

  final AtomicTextFile _storage;

  @override
  Future<UsageStatisticsIndexSnapshot> load() async {
    try {
      final encoded = await _storage.read();
      if (encoded == null || encoded.trim().isEmpty) {
        return const UsageStatisticsIndexSnapshot();
      }
      return UsageStatisticsIndexSnapshot.tryDecode(jsonDecode(encoded));
    } on FormatException {
      // 索引损坏不能阻止应用启动；下一次加载会从 Codex 历史重建。
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
}

class MemoryUsageStatisticsIndexStore implements UsageStatisticsIndexStore {
  UsageStatisticsIndexSnapshot snapshot = const UsageStatisticsIndexSnapshot();

  @override
  Future<UsageStatisticsIndexSnapshot> load() async => snapshot;

  @override
  Future<void> save(UsageStatisticsIndexSnapshot value) async {
    snapshot = value;
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
