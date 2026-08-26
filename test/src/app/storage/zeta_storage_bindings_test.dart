import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/storage/file_storage_service.dart';
import 'package:zeta/src/app/storage/zeta_storage_bindings.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

void main() {
  group('ZetaStorageBindings', () {
    test(
      'memory bindings do not create files and share keyed documents',
      () async {
        final bindings = ZetaStorageBindings.memory();

        expect(bindings.appearance, isA<MemoryStorageService>());
        await bindings.appearance.write('appearance');
        expect(await bindings.appearance.read(), 'appearance');

        final first = bindings.turnContextFactory('codex/thread-1.json');
        await first.write('turn');
        final again = bindings.turnContextFactory('codex/thread-1.json');
        expect(await again.read(), 'turn');
        expect(identical(first, again), isTrue, reason: '同一相对键必须复用同一个内存文档');
      },
    );

    test(
      'file bindings point at ZetaDataPaths and persist atomically',
      () async {
        final home = Directory.systemTemp.createTempSync(
          'zeta_storage_bindings_',
        );
        addTearDown(() {
          if (home.existsSync()) {
            home.deleteSync(recursive: true);
          }
        });
        final paths = ZetaDataPaths.fromHomeDirectory(
          home.path,
          isWindows: Platform.isWindows,
        );
        final bindings = ZetaStorageBindings.file(paths);

        expect(bindings.appearance, isA<FileStorageService>());
        await bindings.appearance.write('{"themeMode":"light"}');
        expect(File(paths.appearanceFilePath).existsSync(), isTrue);
        expect(await bindings.appearance.read(), '{"themeMode":"light"}');
      },
    );
  });
}
