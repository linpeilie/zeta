import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:zeta/src/features/usage_statistics/data/legacy_usage_statistics_index_decoder.dart';

/// Provider 不透明分区索引的根版本。
const int usageStatisticsPartitionIndexVersion = 4;

/// 旧版 Zeta SharedPreferences 中的使用统计派生索引 key。
const String usageStatisticsIndexStorageKey = 'usage_statistics.index.v2';

/// 将 v2/v3/v4 输入宽容归一为仅含安全分区的 v4 根对象。
///
/// 供一次性 Zeta 存储迁移使用；正常读写仍通过 [UsageStatisticsPartitionStore]。
Map<String, Object?> normalizeUsageStatisticsPartitionIndex(Object? value) =>
    _encodeRoot(_decodeRoot(value));

/// 单个用量 source 拥有的 JSON-safe 索引分区。
final class UsageStatisticsIndexPartition {
  UsageStatisticsIndexPartition({
    required this.schemaVersion,
    required Map<String, Object?> payload,
  }) : payload = _freezeMap(payload) {
    if (schemaVersion < 1) {
      throw ArgumentError.value(schemaVersion, 'schemaVersion');
    }
  }

  final int schemaVersion;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'payload': payload,
  };

  static UsageStatisticsIndexPartition? tryDecode(Object? value) {
    final map = _tryObjectMap(value);
    if (map == null) {
      return null;
    }
    final schemaVersion = _integer(map['schemaVersion']);
    final payload = _tryObjectMap(map['payload']);
    if (schemaVersion == null || schemaVersion < 1 || payload == null) {
      return null;
    }
    try {
      return UsageStatisticsIndexPartition(
        schemaVersion: schemaVersion,
        payload: payload,
      );
    } on ArgumentError {
      return null;
    }
  }
}

/// 共享层只按 source key 原子读写不透明分区，不解析 Provider payload。
abstract interface class UsageStatisticsPartitionStore {
  Future<UsageStatisticsIndexPartition?> readPartition(String sourceKey);

  Future<void> writePartition(
    String sourceKey,
    UsageStatisticsIndexPartition partition,
  );
}

/// 基于同一使用统计索引文件的 v4 分区 Store。
final class FileUsageStatisticsPartitionStore
    implements UsageStatisticsPartitionStore {
  FileUsageStatisticsPartitionStore({required File file})
    : _storage = AtomicTextFile(file);

  final AtomicTextFile _storage;
  final _AsyncMutex _mutex = _AsyncMutex();

  @override
  Future<UsageStatisticsIndexPartition?> readPartition(String sourceKey) async {
    final normalizedKey = _validateSourceKey(sourceKey);
    return (await _loadPartitions())[normalizedKey];
  }

  @override
  Future<void> writePartition(
    String sourceKey,
    UsageStatisticsIndexPartition partition,
  ) {
    final normalizedKey = _validateSourceKey(sourceKey);
    return _mutex.synchronized(() async {
      final partitions = <String, UsageStatisticsIndexPartition>{
        ...await _loadPartitions(),
        normalizedKey: partition,
      };
      await _storage.write(jsonEncode(_encodeRoot(partitions)));
    });
  }

  Future<Map<String, UsageStatisticsIndexPartition>> _loadPartitions() async {
    try {
      final encoded = await _storage.read();
      if (encoded == null || encoded.trim().isEmpty) {
        return const <String, UsageStatisticsIndexPartition>{};
      }
      return _decodeRoot(jsonDecode(encoded));
    } on FormatException {
      return const <String, UsageStatisticsIndexPartition>{};
    } on IOException {
      return const <String, UsageStatisticsIndexPartition>{};
    } catch (_) {
      // 越界值、非法嵌套对象等语义损坏均视为可重建索引。
      return const <String, UsageStatisticsIndexPartition>{};
    }
  }
}

/// 测试和无文件持久化宿主使用的分区 Store。
final class MemoryUsageStatisticsPartitionStore
    implements UsageStatisticsPartitionStore {
  MemoryUsageStatisticsPartitionStore({
    Map<String, UsageStatisticsIndexPartition> partitions =
        const <String, UsageStatisticsIndexPartition>{},
  }) : _partitions = <String, UsageStatisticsIndexPartition>{...partitions};

  final Map<String, UsageStatisticsIndexPartition> _partitions;
  final _AsyncMutex _mutex = _AsyncMutex();

  @override
  Future<UsageStatisticsIndexPartition?> readPartition(String sourceKey) async {
    return _partitions[_validateSourceKey(sourceKey)];
  }

  @override
  Future<void> writePartition(
    String sourceKey,
    UsageStatisticsIndexPartition partition,
  ) {
    final normalizedKey = _validateSourceKey(sourceKey);
    return _mutex.synchronized(() async {
      _partitions[normalizedKey] = partition;
    });
  }
}

Map<String, UsageStatisticsIndexPartition> _decodeRoot(Object? value) {
  final root = _tryObjectMap(value);
  if (root == null) {
    return const <String, UsageStatisticsIndexPartition>{};
  }
  if (_integer(root['version']) != usageStatisticsPartitionIndexVersion) {
    final legacy = LegacyUsageStatisticsIndexDecoder.tryDecode(root);
    final partitions = <String, UsageStatisticsIndexPartition>{};
    for (final entry in legacy.entries) {
      try {
        partitions[entry.key] = UsageStatisticsIndexPartition(
          schemaVersion: 1,
          payload: entry.value,
        );
      } on ArgumentError {
        // 单个 legacy 分区损坏时保留其它可用分区。
      }
    }
    return Map<String, UsageStatisticsIndexPartition>.unmodifiable(partitions);
  }
  final providers = _tryObjectMap(root['providers']);
  if (providers == null) {
    return const <String, UsageStatisticsIndexPartition>{};
  }
  final partitions = <String, UsageStatisticsIndexPartition>{};
  for (final entry in providers.entries) {
    if (entry.key.trim().isEmpty) {
      continue;
    }
    final partition = UsageStatisticsIndexPartition.tryDecode(entry.value);
    if (partition != null) {
      partitions[entry.key] = partition;
    }
  }
  return Map<String, UsageStatisticsIndexPartition>.unmodifiable(partitions);
}

Map<String, Object?> _encodeRoot(
  Map<String, UsageStatisticsIndexPartition> partitions,
) {
  return <String, Object?>{
    'version': usageStatisticsPartitionIndexVersion,
    'providers': <String, Object?>{
      for (final entry in partitions.entries) entry.key: entry.value.toJson(),
    },
  };
}

String _validateSourceKey(String sourceKey) {
  final normalized = sourceKey.trim();
  if (normalized.isEmpty || normalized != sourceKey) {
    throw ArgumentError.value(sourceKey, 'sourceKey');
  }
  return normalized;
}

Map<String, Object?> _freezeMap(Map<String, Object?> value) {
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final entry in value.entries) entry.key: _freezeJson(entry.value),
  });
}

Object? _freezeJson(Object? value) {
  return switch (value) {
    null || bool() || num() || String() => value,
    List() => List<Object?>.unmodifiable(value.map(_freezeJson)),
    Map() => _freezeDynamicMap(value),
    _ => throw ArgumentError.value(value, 'payload', 'must be JSON-safe'),
  };
}

Map<String, Object?> _freezeDynamicMap(Map<Object?, Object?> value) {
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw ArgumentError.value(key, 'payload key', 'must be a string');
    }
    result[key] = _freezeJson(entry.value);
  }
  return Map<String, Object?>.unmodifiable(result);
}

Map<String, Object?>? _tryObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        return null;
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
  return null;
}

int? _integer(Object? value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  String() => int.tryParse(value),
  _ => null,
};

final class _AsyncMutex {
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
