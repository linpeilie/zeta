import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zeta_storage/zeta_storage.dart';

void main() {
  group(AtomicTextFile, () {
    late Directory directory;
    late File target;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('zeta-atomic-file-');
      target = File(
        '${directory.path}${Platform.pathSeparator}nested'
        '${Platform.pathSeparator}state.json',
      );
    });

    tearDown(() async {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    test('returns null when the target does not exist', () async {
      final storage = AtomicTextFile(target);

      expect(await storage.read(), isNull);
    });

    test('creates parents and atomically replaces UTF-8 text', () async {
      final storage = AtomicTextFile(target);

      await storage.write('first');
      await storage.write('第二');

      expect(await storage.read(), '第二');
      expect(target.parent.existsSync(), isTrue);
      expect(
        target.parent.listSync().whereType<File>().map((file) => file.path),
        <String>[target.path],
      );
    });

    test('serializes concurrent writes in invocation order', () async {
      final storage = AtomicTextFile(target);

      await Future.wait(<Future<void>>[
        storage.write('first'),
        storage.write('second'),
      ]);

      expect(await target.readAsString(), 'second');
    });

    test(
      'preserves the target and removes temp data on replace failure',
      () async {
        await target.parent.create(recursive: true);
        await target.writeAsString('stable');
        final temporary = File('${target.path}.controlled.tmp');
        final storage = AtomicTextFile(
          target,
          temporaryPathBuilder: (_) => temporary.path,
          replacer: (_, _) async => throw StateError('replace failed'),
        );

        await expectLater(
          storage.write('new'),
          throwsA(
            isA<StorageWriteException>()
                .having(
                  (error) => error.operation,
                  'operation',
                  StorageOperation.replace,
                )
                .having((error) => error.path, 'path', target.path),
          ),
        );

        expect(await target.readAsString(), 'stable');
        expect(temporary.existsSync(), isFalse);
      },
    );

    test('preserves the target when writing the temp file fails', () async {
      await target.parent.create(recursive: true);
      await target.writeAsString('stable');
      final temporaryDirectory = Directory('${target.path}.tmp')..createSync();
      final storage = AtomicTextFile(
        target,
        temporaryPathBuilder: (_) => temporaryDirectory.path,
      );

      await expectLater(
        storage.write('new'),
        throwsA(
          isA<StorageWriteException>().having(
            (error) => error.operation,
            'operation',
            StorageOperation.writeTemporary,
          ),
        ),
      );

      expect(await target.readAsString(), 'stable');
      expect(temporaryDirectory.existsSync(), isTrue);
    });

    test('wraps a temporary cleanup failure after replacement', () async {
      final temporary = File('${target.path}.controlled.tmp');

      await expectLater(
        writeAtomic(
          target,
          'new',
          temporaryPathBuilder: (_) => temporary.path,
          replacer: (source, destination) async {
            await destination.parent.create(recursive: true);
            await source.copy(destination.path);
          },
          temporaryFileDeleter: (_) async {
            throw StateError('cleanup failed');
          },
        ),
        throwsA(
          isA<StorageWriteException>().having(
            (error) => error.operation,
            'operation',
            StorageOperation.deleteTemporary,
          ),
        ),
      );

      expect(await target.readAsString(), 'new');
      expect(temporary.existsSync(), isTrue);
    });

    test('rejects a temp path equal to the target', () async {
      await expectLater(
        writeAtomic(target, 'new', temporaryPathBuilder: (_) => target.path),
        throwsA(isA<StoragePathException>()),
      );
    });

    test('wraps parent creation failures without creating a target', () async {
      final blocker = File('${directory.path}${Platform.pathSeparator}blocker');
      await blocker.writeAsString('file');
      final blockedTarget = File(
        '${blocker.path}${Platform.pathSeparator}state.json',
      );

      await expectLater(
        writeAtomic(blockedTarget, 'new'),
        throwsA(
          isA<StorageWriteException>().having(
            (error) => error.operation,
            'operation',
            StorageOperation.createDirectory,
          ),
        ),
      );

      expect(blocker.readAsStringSync(), 'file');
    });

    test('wraps malformed UTF-8 read failures', () async {
      await target.parent.create(recursive: true);
      await target.writeAsBytes(<int>[0xFF]);
      final storage = AtomicTextFile(target);

      await expectLater(storage.read(), throwsA(isA<StorageReadException>()));
    });

    test('close waits for queued work and rejects future operations', () async {
      final replaceStarted = Completer<void>();
      final allowReplace = Completer<void>();
      final storage = AtomicTextFile(
        target,
        replacer: (temporary, destination) async {
          replaceStarted.complete();
          await allowReplace.future;
          await temporary.rename(destination.path);
        },
      );
      final write = storage.write('value');
      await replaceStarted.future;

      final close = storage.close();
      expect(storage.isClosed, isTrue);
      allowReplace.complete();
      await Future.wait(<Future<void>>[write, close]);
      await storage.close();

      expect(
        () => storage.write('later'),
        throwsA(isA<StorageClosedException>()),
      );
      await expectLater(storage.read(), throwsA(isA<StorageClosedException>()));
    });

    test('a failed write does not poison the serialization queue', () async {
      var attempts = 0;
      final storage = AtomicTextFile(
        target,
        replacer: (temporary, destination) async {
          attempts += 1;
          if (attempts == 1) {
            throw StateError('first fails');
          }
          await temporary.rename(destination.path);
        },
      );

      await expectLater(
        storage.write('first'),
        throwsA(isA<StorageException>()),
      );
      await storage.write('second');

      expect(await target.readAsString(), 'second');
    });
  });
}
