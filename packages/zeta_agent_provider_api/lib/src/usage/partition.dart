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
abstract interface class AgentUsagePartitionPort {
  Future<UsageStatisticsIndexPartition?> readPartition(String sourceKey);

  Future<void> writePartition(
    String sourceKey,
    UsageStatisticsIndexPartition partition,
  );
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
