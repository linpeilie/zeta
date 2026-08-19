import 'package:usage_statistics_storage_client/src/usage_index_models.dart';
import 'package:usage_statistics_storage_client/src/usage_storage_exceptions.dart';

/// Strict codec for the current rebuildable usage index.
final class UsageIndexCodec {
  /// Creates a current-schema codec.
  const UsageIndexCodec();

  /// Encodes [document] to a JSON-compatible root.
  Map<String, Object?> encode(UsageIndexDocument document) {
    return <String, Object?>{
      'version': usageIndexSchemaVersion,
      'providers': <String, Object?>{
        for (final entry in document.partitions.entries)
          entry.key: <String, Object?>{
            'schemaVersion': entry.value.schemaVersion,
            'payload': entry.value.payload,
          },
      },
    };
  }

  /// Decodes a current-schema root.
  UsageIndexDocument decode(Object? raw) {
    if (raw is! Map<String, Object?>) {
      throw const UsageIndexDecodeException(
        code: UsageIndexDecodeFailureCode.invalidRoot,
      );
    }
    if (raw['version'] != usageIndexSchemaVersion) {
      throw const UsageIndexDecodeException(
        code: UsageIndexDecodeFailureCode.unsupportedVersion,
        field: 'version',
      );
    }
    final providers = raw['providers'];
    if (providers is! Map<String, Object?>) {
      throw const UsageIndexDecodeException(
        code: UsageIndexDecodeFailureCode.invalidField,
        field: 'providers',
      );
    }

    final partitions = <String, UsageIndexPartition>{};
    for (final entry in providers.entries) {
      if (entry.key.isEmpty || entry.key.trim() != entry.key) {
        throw const UsageIndexDecodeException(
          code: UsageIndexDecodeFailureCode.invalidField,
          field: 'providers',
        );
      }
      final partition = entry.value;
      if (partition is! Map<String, Object?>) {
        throw const UsageIndexDecodeException(
          code: UsageIndexDecodeFailureCode.invalidField,
          field: 'providers',
        );
      }
      final schemaVersion = partition['schemaVersion'];
      final payload = partition['payload'];
      if (schemaVersion is! int ||
          schemaVersion < 1 ||
          payload is! Map<String, Object?>) {
        throw const UsageIndexDecodeException(
          code: UsageIndexDecodeFailureCode.invalidField,
          field: 'providers',
        );
      }
      if (!_isJsonSafe(payload)) {
        throw const UsageIndexDecodeException(
          code: UsageIndexDecodeFailureCode.invalidField,
          field: 'providers',
        );
      }
      partitions[entry.key] = UsageIndexPartition(
        schemaVersion: schemaVersion,
        payload: payload,
      );
    }
    return UsageIndexDocument(
      partitions: Map<String, UsageIndexPartition>.unmodifiable(partitions),
    );
  }
}

bool _isJsonSafe(Object? value) {
  return switch (value) {
    null || bool() || num() || String() => true,
    List<Object?>() => value.every(_isJsonSafe),
    Map<String, Object?>() => value.values.every(_isJsonSafe),
    _ => false,
  };
}
