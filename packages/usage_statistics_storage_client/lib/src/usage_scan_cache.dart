import 'dart:convert';

import 'package:usage_statistics_storage_client/src/usage_index_models.dart';
import 'package:usage_statistics_storage_client/src/usage_statistics_storage_client.dart';

/// One path-free, rebuildable scan-cache value.
final class UsageScanCacheEntry {
  /// Creates a cache entry.
  UsageScanCacheEntry({
    required String sourceId,
    required String fingerprint,
    required Map<String, Object?> payload,
  }) : sourceId = _validateUsageSourceId(sourceId),
       fingerprint = _validateUsageFingerprint(fingerprint),
       payload = freezeUsageJsonMap(payload);

  /// Stable hash of the source path; the path itself is never persisted.
  final String sourceId;

  /// File metadata fingerprint.
  final String fingerprint;

  /// Vendor-produced derived JSON payload.
  final Map<String, Object?> payload;
}

/// Rebuildable cache backed by one opaque usage partition.
final class UsageScanCache {
  /// Creates a cache for [sourceKey].
  UsageScanCache({
    required this.store,
    required this.sourceKey,
    this.schemaVersion = 1,
  }) {
    if (sourceKey.isEmpty || sourceKey.trim() != sourceKey) {
      throw ArgumentError.value(sourceKey, 'sourceKey');
    }
    if (schemaVersion < 1) {
      throw ArgumentError.value(schemaVersion, 'schemaVersion');
    }
  }

  /// Shared partition store.
  final UsagePartitionStore store;

  /// Provider configuration/source partition key.
  final String sourceKey;

  /// Cache payload schema.
  final int schemaVersion;

  Future<void> _tail = Future<void>.value();

  /// Reads [sourceId] only when [fingerprint] still matches.
  Future<UsageScanCacheEntry?> read({
    required String sourceId,
    required String fingerprint,
    bool forceRefresh = false,
  }) {
    final id = _validateUsageSourceId(sourceId);
    final currentFingerprint = _validateUsageFingerprint(fingerprint);
    return _synchronized(() async {
      if (forceRefresh) {
        return null;
      }
      final entries = await _readEntries();
      final entry = entries[id];
      return entry?.fingerprint == currentFingerprint ? entry : null;
    });
  }

  /// Inserts or replaces [entry] without dropping sibling source entries.
  Future<void> write(UsageScanCacheEntry entry) {
    return _synchronized(() async {
      final entries = await _readEntries();
      entries[entry.sourceId] = entry;
      await _writeEntries(entries);
    });
  }

  /// Removes a single derived source entry.
  Future<void> invalidate(String sourceId) {
    final id = _validateUsageSourceId(sourceId);
    return _synchronized(() async {
      final entries = await _readEntries();
      if (entries.remove(id) == null) {
        return;
      }
      await _writeEntries(entries);
    });
  }

  /// Removes this provider's complete cache partition.
  Future<void> clear() => _synchronized(_clearDirect);

  Future<Map<String, UsageScanCacheEntry>> _readEntries() async {
    final partition = await store.readPartition(sourceKey);
    if (partition == null) {
      return <String, UsageScanCacheEntry>{};
    }
    if (partition.schemaVersion != schemaVersion) {
      await _clearDirect();
      return <String, UsageScanCacheEntry>{};
    }
    final rawEntries = partition.payload['entries'];
    if (rawEntries is! Map<String, Object?>) {
      await _clearDirect();
      return <String, UsageScanCacheEntry>{};
    }
    final entries = <String, UsageScanCacheEntry>{};
    try {
      for (final item in rawEntries.entries) {
        final raw = item.value;
        if (raw is! Map<String, Object?> ||
            !_usageSourceIdPattern.hasMatch(item.key)) {
          throw const FormatException();
        }
        final fingerprint = raw['fingerprint'];
        final payload = raw['payload'];
        if (fingerprint is! String ||
            !_usageFingerprintPattern.hasMatch(fingerprint) ||
            payload is! Map<String, Object?>) {
          throw const FormatException();
        }
        entries[item.key] = UsageScanCacheEntry(
          sourceId: item.key,
          fingerprint: fingerprint,
          payload: payload,
        );
      }
    } on FormatException {
      await _clearDirect();
      return <String, UsageScanCacheEntry>{};
    }
    return entries;
  }

  Future<void> _writeEntries(Map<String, UsageScanCacheEntry> entries) {
    return store.writePartition(
      sourceKey,
      UsageIndexPartition(
        schemaVersion: schemaVersion,
        payload: <String, Object?>{
          'entries': <String, Object?>{
            for (final entry in entries.entries)
              entry.key: <String, Object?>{
                'fingerprint': entry.value.fingerprint,
                'payload': entry.value.payload,
              },
          },
        },
      ),
    );
  }

  Future<void> _clearDirect() => store.deletePartition(sourceKey);

  Future<T> _synchronized<T>(Future<T> Function() operation) {
    final previous = _tail;
    final result = previous.then((_) => operation());
    _tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}

/// Stable 64-bit FNV-1a identifier for an in-memory source path.
String usageSourceId(String sourcePath) {
  if (sourcePath.isEmpty) {
    throw ArgumentError.value(sourcePath, 'sourcePath');
  }
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = BigInt.parse('ffffffffffffffff', radix: 16);
  for (final byte in utf8.encode(sourcePath)) {
    hash ^= BigInt.from(byte);
    hash = (hash * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// Stable size/mtime fingerprint without importing filesystem types.
String usageFileFingerprint({
  required int size,
  required int modifiedMicroseconds,
}) {
  if (size < 0) {
    throw ArgumentError.value(size, 'size');
  }
  return '$size:$modifiedMicroseconds';
}

final RegExp _usageSourceIdPattern = RegExp(r'^[0-9a-f]{16}$');
final RegExp _usageFingerprintPattern = RegExp(r'^\d+:-?\d+$');

String _validateUsageSourceId(String value) {
  if (!_usageSourceIdPattern.hasMatch(value)) {
    throw ArgumentError.value(value, 'sourceId');
  }
  return value;
}

String _validateUsageFingerprint(String value) {
  if (!_usageFingerprintPattern.hasMatch(value)) {
    throw ArgumentError.value(value, 'fingerprint');
  }
  return value;
}
