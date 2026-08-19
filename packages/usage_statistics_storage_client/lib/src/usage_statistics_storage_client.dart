import 'dart:async';
import 'dart:convert';

import 'package:usage_statistics_storage_client/src/usage_document_storage.dart';
import 'package:usage_statistics_storage_client/src/usage_index_codec.dart';
import 'package:usage_statistics_storage_client/src/usage_index_models.dart';
import 'package:usage_statistics_storage_client/src/usage_storage_exceptions.dart';

/// Atomic, serialized storage for provider-owned derived usage partitions.
final class UsagePartitionStore {
  /// Creates a partition store.
  UsagePartitionStore({
    required this.storage,
    this.codec = const UsageIndexCodec(),
  });

  /// External current-schema document storage.
  final UsageDocumentStorage storage;

  /// Current-schema root codec.
  final UsageIndexCodec codec;

  Future<void> _tail = Future<void>.value();
  bool _isClosed = false;

  /// Reads [sourceKey], returning a cache miss when absent.
  ///
  /// A corrupt derived index is atomically cleared before this returns `null`.
  Future<UsageIndexPartition?> readPartition(String sourceKey) {
    final key = _validateSourceKey(sourceKey);
    return _synchronized(() async {
      final index = await _loadIndex();
      return index.partitions[key];
    });
  }

  /// Atomically replaces [sourceKey] without dropping other provider data.
  Future<void> writePartition(
    String sourceKey,
    UsageIndexPartition partition,
  ) {
    final key = _validateSourceKey(sourceKey);
    return _synchronized(() async {
      final current = await _loadIndex();
      await _writeIndex(
        UsageIndexDocument(
          partitions: <String, UsageIndexPartition>{
            ...current.partitions,
            key: partition,
          },
        ),
      );
    });
  }

  /// Removes [sourceKey]. Corrupt input is cleared as an empty index.
  Future<void> deletePartition(String sourceKey) {
    final key = _validateSourceKey(sourceKey);
    return _synchronized(() async {
      final current = await _loadIndex();
      if (!current.partitions.containsKey(key)) {
        return;
      }
      final partitions = <String, UsageIndexPartition>{
        ...current.partitions,
      }..remove(key);
      await _writeIndex(UsageIndexDocument(partitions: partitions));
    });
  }

  /// Clears every rebuildable derived partition.
  Future<void> clear() {
    return _synchronized(
      () => _writeIndex(UsageIndexDocument()),
    );
  }

  /// Waits for queued operations and closes the underlying storage.
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    await _tail;
    await storage.close();
  }

  Future<UsageIndexDocument> _loadIndex() async {
    final source = await storage.read();
    if (source == null || source.trim().isEmpty) {
      return UsageIndexDocument();
    }

    try {
      return codec.decode(jsonDecode(source));
    } on FormatException {
      final empty = UsageIndexDocument();
      await _writeIndex(empty);
      return empty;
    }
  }

  Future<void> _writeIndex(UsageIndexDocument index) {
    return storage.write(jsonEncode(codec.encode(index)));
  }

  Future<T> _synchronized<T>(Future<T> Function() operation) {
    _ensureOpen();
    final previous = _tail;
    final result = previous.then((_) => operation());
    _tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _ensureOpen() {
    if (_isClosed) {
      throw const UsageStorageClosedException();
    }
  }
}

String _validateSourceKey(String sourceKey) {
  if (sourceKey.isEmpty || sourceKey.trim() != sourceKey) {
    throw ArgumentError.value(sourceKey, 'sourceKey');
  }
  return sourceKey;
}
