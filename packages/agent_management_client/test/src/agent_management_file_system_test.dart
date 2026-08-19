import 'dart:io';

import 'package:agent_management_client/agent_management_client.dart';
import 'package:test/test.dart';

void main() {
  group('IoAgentManagementFileSystem', () {
    late Directory root;
    const fileSystem = IoAgentManagementFileSystem();

    setUp(() async {
      root = await Directory.systemTemp.createTemp('zeta-management-fs-');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test(
      'reports missing, directory, regular-file, and injected link metadata',
      () async {
        final missing = await fileSystem.metadata(
          '${root.path}${Platform.pathSeparator}missing',
        );
        final directory = await fileSystem.metadata(root.path);
        final file = File('${root.path}${Platform.pathSeparator}config.json');
        await file.writeAsString('{}');
        final regular = await fileSystem.metadata(file.path);
        final link = await IoAgentManagementFileSystem(
          entityTypeReader: (_) async => FileSystemEntityType.link,
        ).metadata('link');

        expect(missing.exists, isFalse);
        expect(missing.isFile, isFalse);
        expect(missing.isLink, isFalse);
        expect(missing.size, 0);
        expect(missing.modifiedAt, isNull);
        expect(directory.exists, isTrue);
        expect(directory.isFile, isFalse);
        expect(directory.isLink, isFalse);
        expect(regular.exists, isTrue);
        expect(regular.isFile, isTrue);
        expect(regular.isLink, isFalse);
        expect(regular.size, 2);
        expect(regular.modifiedAt, isNotNull);
        expect(link.exists, isTrue);
        expect(link.isFile, isFalse);
        expect(link.isLink, isTrue);
      },
    );

    test(
      'reads and atomically writes with a backup for existing files',
      () async {
        final path =
            '${root.path}${Platform.pathSeparator}nested'
            '${Platform.pathSeparator}config.toml';
        expect(
          await fileSystem.writeTextAtomically(
            path,
            'first',
            backupSuffix: '.backup-1',
          ),
          isNull,
        );
        expect(await fileSystem.readText(path), 'first');

        final backup = await fileSystem.writeTextAtomically(
          path,
          'second',
          backupSuffix: '.backup-2',
        );
        expect(backup, '$path.backup-2');
        expect(await File(backup!).readAsString(), 'first');
        expect(await fileSystem.readText(path), 'second');
      },
    );

    test(
      'lists sorted regular files recursively and handles missing roots',
      () async {
        final nested = Directory(
          '${root.path}${Platform.pathSeparator}nested',
        );
        await nested.create();
        final first = File('${root.path}${Platform.pathSeparator}b.log');
        final second = File('${nested.path}${Platform.pathSeparator}a.log');
        await first.writeAsString('b');
        await second.writeAsString('a');

        expect(
          await fileSystem.listFiles(
            '${root.path}${Platform.pathSeparator}missing',
          ),
          isEmpty,
        );
        expect(
          await fileSystem.listFiles(root.path),
          <String>[first.path],
        );
        expect(
          await fileSystem.listFiles(root.path, recursive: true),
          <String>[first.path, second.path]..sort(),
        );
      },
    );

    test('reads bounded UTF-8 tails and validates the byte cap', () async {
      final file = File('${root.path}${Platform.pathSeparator}tail.log');
      await file.writeAsString('0123456789');

      final whole = await fileSystem.readTextTail(file.path, maxBytes: 20);
      final tail = await fileSystem.readTextTail(file.path, maxBytes: 4);
      final empty = await fileSystem.readTextTail(file.path, maxBytes: 0);

      expect(whole.contents, '0123456789');
      expect(whole.skippedPrefix, isFalse);
      expect(tail.contents, '6789');
      expect(tail.skippedPrefix, isTrue);
      expect(empty.contents, isEmpty);
      expect(empty.skippedPrefix, isTrue);
      await expectLater(
        fileSystem.readTextTail(file.path, maxBytes: -1),
        throwsArgumentError,
      );
    });
  });
}
