import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;

  String read(String path) => File('${root.path}/$path').readAsStringSync();

  group('flavor identity', () {
    const flavors = <String>['development', 'staging', 'production'];

    test('every entrypoint composes the app the same way', () {
      final sources = <String, String>{
        for (final flavor in flavors) flavor: read('lib/main_$flavor.dart'),
      };
      final development = sources['development']!;

      for (final flavor in flavors) {
        expect(
          sources[flavor],
          development,
          reason:
              'lib/main_$flavor.dart must differ from the development '
              'entrypoint only by file name.',
        );
      }
      expect(development, contains('await bootstrap('));
      expect(development, contains('composition.repositories'));
    });

    test('every platform registers the same application identity', () {
      expect(
        read('macos/Runner/Configs/AppInfo.xcconfig'),
        allOf(
          contains('PRODUCT_BUNDLE_IDENTIFIER = cn.easii.zeta'),
          contains('PRODUCT_NAME = Zeta'),
        ),
      );
      expect(
        read('linux/CMakeLists.txt'),
        contains('set(APPLICATION_ID "cn.easii.zeta")'),
      );
      expect(
        read('windows/runner/main.cpp'),
        contains('SetCurrentProcessExplicitAppUserModelID(L"cn.easii.zeta")'),
      );
    });

    test('desktop notifications use the registered Windows identity', () {
      final facade = read(
        'lib/app/platform/flutter_local_notifications_facade.dart',
      );
      expect(facade, contains("appUserModelId: 'cn.easii.zeta'"));
      expect(facade, contains("appName: 'Zeta'"));
    });

    test('no flavor overrides the Zeta data directory or schema', () {
      final bootstrap = read('lib/bootstrap.dart');
      expect(bootstrap, contains('ZetaDataPaths.fromEnvironment'));
      for (final flavor in flavors) {
        expect(
          read('lib/main_$flavor.dart'),
          isNot(contains('ZetaDataPaths')),
          reason: 'Flavors must not choose their own data directory.',
        );
      }
    });
  });
}
