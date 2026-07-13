import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:zeta/src/features/agent/data/datasources/local_history/codex_usage_log_scanner.dart';

const int usageStatisticsIndexVersion = 2;
const String _usageStatisticsIndexKey = 'usage_statistics.index.v2';

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
          sessions[session.sourcePath] = session;
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

class SharedPreferencesUsageStatisticsIndexStore
    implements UsageStatisticsIndexStore {
  const SharedPreferencesUsageStatisticsIndexStore();

  @override
  Future<UsageStatisticsIndexSnapshot> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_usageStatisticsIndexKey);
    if (encoded == null || encoded.trim().isEmpty) {
      return const UsageStatisticsIndexSnapshot();
    }
    try {
      return UsageStatisticsIndexSnapshot.tryDecode(jsonDecode(encoded));
    } catch (_) {
      // 索引损坏不能阻止应用启动；下一次加载会从 Codex 历史重建。
      return const UsageStatisticsIndexSnapshot();
    }
  }

  @override
  Future<void> save(UsageStatisticsIndexSnapshot snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _usageStatisticsIndexKey,
      jsonEncode(snapshot.toJson()),
    );
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
