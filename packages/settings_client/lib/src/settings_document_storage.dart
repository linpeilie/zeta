import 'dart:io';

import 'package:zeta_storage/zeta_storage.dart';

/// Injectable text persistence boundary for one settings document.
abstract interface class SettingsDocumentStorage {
  /// Reads the document, or returns null when it does not exist.
  Future<String?> read();

  /// Atomically replaces the document with [contents].
  Future<void> write(String contents);

  /// Flushes queued writes and closes the document.
  Future<void> close();
}

/// [AtomicTextFile]-backed settings document storage.
final class AtomicSettingsDocumentStorage implements SettingsDocumentStorage {
  /// Creates storage around an existing atomic text file.
  const AtomicSettingsDocumentStorage(this.storage);

  /// Creates storage for [file].
  factory AtomicSettingsDocumentStorage.fromFile(File file) {
    return AtomicSettingsDocumentStorage(AtomicTextFile(file));
  }

  /// Shared atomic storage primitive.
  final AtomicTextFile storage;

  @override
  Future<String?> read() => storage.read();

  @override
  Future<void> write(String contents) => storage.write(contents);

  @override
  Future<void> close() => storage.close();
}
