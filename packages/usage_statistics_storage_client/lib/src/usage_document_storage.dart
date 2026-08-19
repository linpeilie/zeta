import 'dart:io';

import 'package:zeta_storage/zeta_storage.dart';

/// Injectable text boundary for the rebuildable usage index.
abstract interface class UsageDocumentStorage {
  /// Reads the index, or returns `null` when absent.
  Future<String?> read();

  /// Atomically replaces the index with [contents].
  Future<void> write(String contents);

  /// Flushes writes and closes the document.
  Future<void> close();
}

/// [AtomicTextFile]-backed usage index storage.
final class AtomicUsageDocumentStorage implements UsageDocumentStorage {
  /// Creates storage around [storage].
  const AtomicUsageDocumentStorage(this.storage);

  /// Creates storage for [file].
  factory AtomicUsageDocumentStorage.fromFile(File file) {
    return AtomicUsageDocumentStorage(AtomicTextFile(file));
  }

  /// Shared atomic text storage.
  final AtomicTextFile storage;

  @override
  Future<String?> read() => storage.read();

  @override
  Future<void> write(String contents) => storage.write(contents);

  @override
  Future<void> close() => storage.close();
}
