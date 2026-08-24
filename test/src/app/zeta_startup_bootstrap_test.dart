import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/zeta_startup_bootstrap.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';

void main() {
  group('ZetaStartupBootstrap', () {
    late Directory homeDirectory;
    late ZetaDataPaths paths;

    setUp(() {
      homeDirectory = Directory.systemTemp.createTempSync('zeta_bootstrap_');
      paths = ZetaDataPaths.fromHomeDirectory(
        homeDirectory.path,
        isWindows: Platform.isWindows,
      );
    });

    tearDown(() {
      if (homeDirectory.existsSync()) {
        homeDirectory.deleteSync(recursive: true);
      }
    });

    test('prepares Zeta storage directories', () async {
      final result = await ZetaStartupBootstrap(paths: paths).run();

      expect(result.filePersistenceEnabled, isTrue);
      expect(Directory(paths.configDirectoryPath).existsSync(), isTrue);
      expect(Directory(paths.stateDirectoryPath).existsSync(), isTrue);
      expect(Directory(paths.logsDirectoryPath).existsSync(), isTrue);
      expect(Directory(paths.cacheDirectoryPath).existsSync(), isTrue);
    });

    test(
      'disables file persistence when a storage directory is blocked',
      () async {
        File(paths.configDirectoryPath).createSync(recursive: true);

        final result = await ZetaStartupBootstrap(paths: paths).run();

        expect(result.filePersistenceEnabled, isFalse);
      },
    );
  });
}
