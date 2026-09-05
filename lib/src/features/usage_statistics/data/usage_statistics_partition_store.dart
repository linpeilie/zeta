import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zeta_foundation/zeta_foundation.dart';

/// Provider 不透明分区索引的根版本。
const int usageStatisticsPartitionIndexVersion = 4;

/// 基于同一使用统计索引文件的 v4 分区 Store。
final class FileUsageStatisticsPartitionStore
    implements AgentUsagePartitionPort {
  FileUsageStatisticsPartitionStore({required this._storage});

  final StorageService _storage;
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

Map<String, UsageStatisticsIndexPartition> _decodeRoot(Object? value) {
  final root = _tryObjectMap(value);
  if (root == null) {
    return const <String, UsageStatisticsIndexPartition>{};
  }
  if (root['version'] != usageStatisticsPartitionIndexVersion) {
    return const <String, UsageStatisticsIndexPartition>{};
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
