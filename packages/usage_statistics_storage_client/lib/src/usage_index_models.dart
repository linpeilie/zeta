/// Current usage index root schema.
const usageIndexSchemaVersion = 4;

/// Provider-owned, JSON-safe derived usage partition.
final class UsageIndexPartition {
  /// Creates a partition and defensively freezes [payload].
  UsageIndexPartition({
    required this.schemaVersion,
    required Map<String, Object?> payload,
  }) : payload = freezeUsageJsonMap(payload) {
    if (schemaVersion < 1) {
      throw ArgumentError.value(schemaVersion, 'schemaVersion');
    }
  }

  /// Provider-owned partition schema.
  final int schemaVersion;

  /// Opaque JSON-safe payload.
  final Map<String, Object?> payload;
}

/// Current root index containing isolated provider partitions.
final class UsageIndexDocument {
  /// Creates an index and defensively freezes its partition map.
  UsageIndexDocument({
    Map<String, UsageIndexPartition> partitions =
        const <String, UsageIndexPartition>{},
  }) : partitions = Map<String, UsageIndexPartition>.unmodifiable(partitions) {
    for (final key in partitions.keys) {
      if (key.isEmpty || key.trim() != key) {
        throw ArgumentError.value(key, 'partition key');
      }
    }
  }

  /// Partitions keyed by provider configuration/source identifier.
  final Map<String, UsageIndexPartition> partitions;
}

/// Defensively freezes a JSON-safe map.
Map<String, Object?> freezeUsageJsonMap(Map<String, Object?> value) {
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final entry in value.entries) entry.key: _freezeUsageJson(entry.value),
  });
}

Object? _freezeUsageJson(Object? value) {
  return switch (value) {
    null || bool() || num() || String() => value,
    List<Object?>() => List<Object?>.unmodifiable(
      value.map(_freezeUsageJson),
    ),
    Map<String, Object?>() => freezeUsageJsonMap(value),
    Map<Object?, Object?>() => _freezeDynamicMap(value),
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
    result[key] = _freezeUsageJson(entry.value);
  }
  return Map<String, Object?>.unmodifiable(result);
}
