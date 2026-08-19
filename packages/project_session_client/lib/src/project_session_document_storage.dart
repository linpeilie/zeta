import 'dart:io';

import 'package:zeta_storage/zeta_storage.dart';

/// Injectable text persistence boundary for the IDE session document.
abstract interface class ProjectSessionDocumentStorage {
  /// Reads the document, or returns `null` when it does not exist.
  Future<String?> read();

  /// Atomically replaces the document with [contents].
  Future<void> write(String contents);

  /// Flushes queued writes and closes the document.
  Future<void> close();
}

/// [AtomicTextFile]-backed IDE session document storage.
final class AtomicProjectSessionDocumentStorage
    implements ProjectSessionDocumentStorage {
  /// Creates storage around an existing atomic text file.
  const AtomicProjectSessionDocumentStorage(this.storage);

  /// Creates storage for [file].
  factory AtomicProjectSessionDocumentStorage.fromFile(File file) {
    return AtomicProjectSessionDocumentStorage(AtomicTextFile(file));
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
