import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:zeta_storage/zeta_storage.dart';

void main() {
  group(ZetaDataPaths, () {
    late Directory homeDirectory;

    setUp(() async {
      homeDirectory = await Directory.systemTemp.createTemp('zeta-data-paths-');
    });

    tearDown(() async {
      if (homeDirectory.existsSync()) {
        homeDirectory.deleteSync(recursive: true);
      }
    });

    test('creates only the current Zeta-owned directory layout', () async {
      final paths = ZetaDataPaths.fromHomeDirectory(homeDirectory.path);

      await paths.ensureDirectories();

      final root = path.join(homeDirectory.path, '.zeta');
      expect(paths.rootDirectory.path, root);
      expect(paths.configDirectory.existsSync(), isTrue);
      expect(paths.stateDirectory.existsSync(), isTrue);
      expect(paths.logsDirectory.existsSync(), isTrue);
      expect(paths.cacheDirectory.existsSync(), isTrue);
      expect(
        paths.sessionStateDirectory.path,
        path.join(root, 'state', 'session'),
      );
      expect(
        paths.providersFile.path,
        path.join(root, 'config', 'providers.json'),
      );
      expect(
        paths.appearanceFile.path,
        path.join(root, 'config', 'appearance.json'),
      );
      expect(
        paths.generalSettingsFile.path,
        path.join(root, 'config', 'general.json'),
      );
      expect(
        paths.ideSessionFile.path,
        path.join(root, 'state', 'ide_session.json'),
      );
      expect(
        paths.usageStatisticsIndexFile.path,
        path.join(root, 'state', 'usage_statistics_index.json'),
      );
      expect(
        paths.agentModelCatalogCacheFile.path,
        path.join(root, 'cache', 'agent_models_v1.json'),
      );
    });

    test('builds deterministic Windows paths on any host platform', () {
      final paths = ZetaDataPaths.fromHomeDirectory(
        r'C:\Users\zeta',
        isWindows: true,
      );

      expect(paths.rootDirectory.path, r'C:\Users\zeta\.zeta');
      expect(
        paths.providersFile.path,
        r'C:\Users\zeta\.zeta\config\providers.json',
      );
    });

    test('resolves supported home environment variables', () {
      expect(
        resolveUserHomeDirectory(
          environment: const <String, String>{'HOME': '/home/zeta'},
          isWindows: false,
        ),
        '/home/zeta',
      );
      expect(
        resolveUserHomeDirectory(
          environment: const <String, String>{
            'USERPROFILE': r'C:\Users\zeta',
            'HOME': r'D:\fallback',
          },
          isWindows: true,
        ),
        r'C:\Users\zeta',
      );
      expect(
        resolveUserHomeDirectory(
          environment: const <String, String>{
            'HOMEDRIVE': 'C:',
            'HOMEPATH': r'\Users\zeta',
          },
          isWindows: true,
        ),
        r'C:\Users\zeta',
      );
      expect(
        resolveUserHomeDirectory(
          environment: const <String, String>{'HOME': r'D:\fallback'},
          isWindows: true,
        ),
        r'D:\fallback',
      );
      expect(
        resolveUserHomeDirectory(
          environment: const <String, String>{'HOME': '  '},
          isWindows: false,
        ),
        isNull,
      );
    });

    test('uses the current platform environment by default', () {
      final paths = ZetaDataPaths.fromEnvironment();

      expect(paths.rootDirectory.path, isNotEmpty);
    });

    test('rejects missing and relative home paths with typed failures', () {
      expect(
        () => ZetaDataPaths.fromEnvironment(
          environment: const <String, String>{},
          isWindows: false,
        ),
        throwsA(isA<StoragePathException>()),
      );
      expect(
        () => ZetaDataPaths.fromHomeDirectory('relative/home'),
        throwsA(isA<StoragePathException>()),
      );
    });

    test('wraps directory creation failures', () async {
      final blocker = File(
        '${homeDirectory.path}${Platform.pathSeparator}blocker',
      );
      await blocker.writeAsString('file');
      final paths = ZetaDataPaths.fromHomeDirectory(
        '${blocker.path}${Platform.pathSeparator}home',
      );

      await expectLater(
        paths.ensureDirectories(),
        throwsA(
          isA<StorageWriteException>().having(
            (error) => error.operation,
            'operation',
            StorageOperation.createDirectory,
          ),
        ),
      );

      expect(await blocker.readAsString(), 'file');
    });
  });
}
