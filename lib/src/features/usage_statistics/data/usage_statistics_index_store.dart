import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

const int usageStatisticsIndexVersion = 1;
const String _usageStatisticsIndexKey = 'usage_statistics.index.v1';

class UsageStatisticsIndexedThread {
  const UsageStatisticsIndexedThread({
    required this.threadId,
    required this.updatedAt,
    required this.records,
  });

  final String threadId;
  final DateTime updatedAt;
  final List<AgentUsageRecord> records;

  Map<String, Object?> toJson() => <String, Object?>{
    'threadId': threadId,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'records': records.map((record) => record.toJson()).toList(),
  };

  static UsageStatisticsIndexedThread? tryDecode(Object? value) {
    final map = _objectMap(value);
    final threadId = _string(map['threadId']);
    final updatedAtMs = _int(map['updatedAt']);
    if (threadId == null || updatedAtMs == null) {
      return null;
    }
    final records = <AgentUsageRecord>[];
    final rawRecords = map['records'];
    if (rawRecords is List) {
      for (final rawRecord in rawRecords) {
        final record = AgentUsageRecord.tryDecode(rawRecord);
        if (record != null) {
          records.add(record);
        }
      }
    }
    return UsageStatisticsIndexedThread(
      threadId: threadId,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
      records: List<AgentUsageRecord>.unmodifiable(records),
    );
  }
}

class UsageStatisticsIndexSnapshot {
  const UsageStatisticsIndexSnapshot({
    this.threads = const <String, UsageStatisticsIndexedThread>{},
  });

  final Map<String, UsageStatisticsIndexedThread> threads;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': usageStatisticsIndexVersion,
    'threads': threads.values.map((thread) => thread.toJson()).toList(),
  };

  static UsageStatisticsIndexSnapshot tryDecode(Object? value) {
    final map = _objectMap(value);
    if (_int(map['version']) != usageStatisticsIndexVersion) {
      return const UsageStatisticsIndexSnapshot();
    }
    final threads = <String, UsageStatisticsIndexedThread>{};
    final rawThreads = map['threads'];
    if (rawThreads is List) {
      for (final rawThread in rawThreads) {
        final thread = UsageStatisticsIndexedThread.tryDecode(rawThread);
        if (thread != null) {
          threads[thread.threadId] = thread;
        }
      }
    }
    return UsageStatisticsIndexSnapshot(
      threads: Map<String, UsageStatisticsIndexedThread>.unmodifiable(threads),
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

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

int? _int(Object? value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  String() => int.tryParse(value),
  _ => null,
};
