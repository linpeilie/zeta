import 'dart:io';

import 'package:test/test.dart';
import 'package:zeta_storage/zeta_storage.dart';

void main() {
  group('path utilities', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('zeta-path-utils-');
    });

    tearDown(() async {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    test('extracts names from POSIX and Windows paths', () {
      expect(fileName('/workspace/file.dart'), 'file.dart');
      expect(fileName(r'C:\workspace\file.dart'), 'file.dart');
      expect(fileName('/'), '/');
    });

    test('normalizes paths with explicit platform rules', () {
      expect(normalizePath('/a/./b/../c', isWindows: false), '/a/c');
      expect(
        normalizePath(r'C:\a\.\b\..\c', isWindows: true),
        r'C:\a\c',
      );
    });

    test('rejects empty normalized paths with a typed failure', () {
      expect(
        () => normalizePath('  '),
        throwsA(isA<StoragePathException>()),
      );
    });

    test('resolves an existing absolute directory canonically', () async {
      final expected = await directory.resolveSymbolicLinks();

      expect(await canonicalDirectoryPath(directory.path), expected);
    });

    test('rejects missing and relative canonical directories', () async {
      await expectLater(
        canonicalDirectoryPath('relative/path'),
        throwsA(isA<StoragePathException>()),
      );
      await expectLater(
        canonicalDirectoryPath('${directory.path}.missing'),
        throwsA(isA<StoragePathException>()),
      );
    });

    test('filters and freezes existing paths in first-seen order', () {
      final second = Directory(
        '${directory.path}${Platform.pathSeparator}second',
      )..createSync();
      final result = existingDirectoryPaths(<String>[
        '',
        directory.path,
        '${directory.path}.missing',
        directory.path,
        second.path,
      ]);

      expect(result, <String>[directory.path, second.path]);
      expect(() => result.add('later'), throwsUnsupportedError);
    });
  });
}
