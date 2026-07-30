import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';

void main() {
  group('DesktopSystemFontCatalogService', () {
    test(
      'decodes localized names, aliases and native monospace metadata',
      () async {
        final service = DesktopSystemFontCatalogService(
          localeName: 'zh_CN',
          loader: (_) async => <Object?>[
            <String, Object?>{
              'id': 'windows:fangsong',
              'familyName': 'FangSong',
              'displayName': '仿宋',
              'aliases': <String>['FangSong', '仿宋', 'simfang'],
              'monospace': false,
            },
            <String, Object?>{
              'id': 'windows:cascadia mono',
              'familyName': 'Cascadia Mono',
              'displayName': 'Cascadia Mono',
              'aliases': <String>['CascadiaMono', 'CascadiaCode'],
              'monospace': true,
            },
            <String, Object?>{'displayName': '缺少真实家族名'},
          ],
        );

        final uiFonts = await service.uiFontFamilies();
        final codeFonts = await service.codeFontFamilies();

        expect(uiFonts.map((font) => font.displayName), <String>[
          'Cascadia Mono',
          '仿宋',
        ]);
        expect(codeFonts.single.familyName, 'Cascadia Mono');
        expect((await service.resolveFontFamily('simfang'))?.displayName, '仿宋');
        expect(
          (await service.resolveFontFamily('CASCADIACODE'))?.familyName,
          'Cascadia Mono',
        );
      },
    );

    test('caches the native catalog and deduplicates stable ids', () async {
      var loadCount = 0;
      final service = DesktopSystemFontCatalogService(
        loader: (_) async {
          loadCount += 1;
          return <Object?>[
            <String, Object?>{
              'id': 'linux:maple mono',
              'familyName': 'Maple Mono',
              'displayName': 'Maple Mono',
              'monospace': true,
            },
            <String, Object?>{
              'id': 'LINUX:MAPLE MONO',
              'familyName': 'Maple Mono Duplicate',
              'displayName': '重复项',
              'monospace': true,
            },
          ];
        },
      );

      expect((await service.uiFontFamilies()).single.familyName, 'Maple Mono');
      await service.codeFontFamilies();
      await service.resolveFontFamily('Maple Mono');

      expect(loadCount, 1);
    });

    test('retries after a transient native catalog failure', () async {
      var loadCount = 0;
      final service = DesktopSystemFontCatalogService(
        loader: (_) async {
          loadCount += 1;
          if (loadCount == 1) {
            throw PlatformException(code: 'channel-unavailable');
          }
          return <Object?>[
            <String, Object?>{
              'id': 'macos:menlo',
              'familyName': 'Menlo',
              'displayName': 'Menlo',
              'monospace': true,
            },
          ];
        },
      );

      await expectLater(
        service.uiFontFamilies(),
        throwsA(isA<PlatformException>()),
      );

      expect((await service.uiFontFamilies()).single.familyName, 'Menlo');
      expect(loadCount, 2);
    });
  });
}
