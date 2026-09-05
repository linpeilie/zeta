import 'package:zeta_foundation/zeta_foundation.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/storage/zeta_data_file_system.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';

void main() {
  group('ZetaDataPaths', () {
    late Directory homeDirectory;

    setUp(() {
      homeDirectory = Directory.systemTemp.createTempSync('zeta_paths_');
    });

    tearDown(() {
      if (homeDirectory.existsSync()) {
        homeDirectory.deleteSync(recursive: true);
      }
    });

    test('creates only the Zeta-owned directory layout', () async {
      final paths = ZetaDataPaths.fromHomeDirectory(
        homeDirectory.path,
        isWindows: Platform.isWindows,
      );

      await ensureZetaDataDirectories(paths);

      expect(paths.rootPath, _join(homeDirectory.path, '.zeta'));
      expect(Directory(paths.configDirectoryPath).existsSync(), isTrue);
      expect(Directory(paths.stateDirectoryPath).existsSync(), isTrue);
      expect(Directory(paths.logsDirectoryPath).existsSync(), isTrue);
      expect(Directory(paths.cacheDirectoryPath).existsSync(), isTrue);
      expect(
        paths.providersFilePath,
        _join(homeDirectory.path, '.zeta', 'config', 'providers.json'),
      );
      expect(
        paths.generalSettingsFilePath,
        _join(homeDirectory.path, '.zeta', 'config', 'general.json'),
      );
      expect(
        paths.usageStatisticsIndexFilePath,
        _join(
          homeDirectory.path,
          '.zeta',
          'state',
          'usage_statistics_index.json',
        ),
      );
      expect(
        paths.sessionStateDirectoryPath,
        _join(homeDirectory.path, '.zeta', 'state', 'session'),
      );
      expect(
        paths.agentModelCatalogCacheFilePath,
        _join(homeDirectory.path, '.zeta', 'cache', 'agent_models_v1.json'),
      );
      expect(
        Directory(_join(homeDirectory.path, '.codex')).existsSync(),
        isFalse,
      );
      expect(
        Directory(_join(homeDirectory.path, '.grok')).existsSync(),
        isFalse,
      );
    });

    test('resolves POSIX and Windows home environment variables', () {
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
    });

    test('rejects missing or relative home paths', () {
      expect(
        () => ZetaDataPaths.fromEnvironment(
          environment: const <String, String>{},
          isWindows: false,
        ),
        throwsStateError,
      );
      expect(
        () =>
            ZetaDataPaths.fromHomeDirectory('relative/home', isWindows: false),
        throwsArgumentError,
      );
    });
  });
}

String _join(
  String first,
  String second, [
  String? third,
  String? fourth,
  String? fifth,
]) {
  return <String?>[
    first,
    second,
    third,
    fourth,
    fifth,
  ].whereType<String>().join(Platform.pathSeparator);
}
