import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
      final paths = ZetaDataPaths.fromHomeDirectory(homeDirectory.path);

      await paths.ensureDirectories();

      expect(paths.rootDirectory.path, _join(homeDirectory.path, '.zeta'));
      expect(paths.configDirectory.existsSync(), isTrue);
      expect(paths.stateDirectory.existsSync(), isTrue);
      expect(paths.logsDirectory.existsSync(), isTrue);
      expect(paths.cacheDirectory.existsSync(), isTrue);
      expect(
        paths.providersFile.path,
        _join(homeDirectory.path, '.zeta', 'config', 'providers.json'),
      );
      expect(
        paths.generalSettingsFile.path,
        _join(homeDirectory.path, '.zeta', 'config', 'general.json'),
      );
      expect(
        paths.usageStatisticsIndexFile.path,
        _join(
          homeDirectory.path,
          '.zeta',
          'state',
          'usage_statistics_index.json',
        ),
      );
      expect(
        paths.sessionStateDirectory.path,
        _join(homeDirectory.path, '.zeta', 'state', 'session'),
      );
      expect(
        paths.agentModelCatalogCacheFile.path,
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
        () => ZetaDataPaths.fromHomeDirectory('relative/home'),
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
