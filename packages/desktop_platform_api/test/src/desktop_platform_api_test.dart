import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:test/test.dart';

void main() {
  group('SystemFontFamily', () {
    test('decodes, trims, compares, and freezes aliases', () {
      final rawAliases = <Object?>[' JetBrains Mono ', 'JetBrainsMono'];
      final family = SystemFontFamily.tryDecode(<Object?, Object?>{
        'id': ' windows:jetbrains mono ',
        'familyName': ' JetBrains Mono ',
        'displayName': ' JetBrains Mono ',
        'aliases': rawAliases,
        'monospace': true,
      });

      expect(
        family,
        SystemFontFamily(
          id: 'windows:jetbrains mono',
          familyName: 'JetBrains Mono',
          displayName: 'JetBrains Mono',
          aliases: const ['JetBrains Mono', 'JetBrainsMono'],
          isMonospace: true,
        ),
      );
      rawAliases.add('mutated');
      expect(family!.aliases, hasLength(2));
      expect(() => family.aliases.add('blocked'), throwsUnsupportedError);
    });

    test('rejects malformed native values', () {
      final valid = <Object?, Object?>{
        'id': 'id',
        'familyName': 'family',
        'displayName': 'display',
        'aliases': <Object?>['alias'],
        'monospace': false,
      };
      final malformed = <Object?>[
        null,
        <Object?, Object?>{...valid, 'id': 1},
        <Object?, Object?>{...valid, 'familyName': ' '},
        <Object?, Object?>{...valid, 'displayName': null},
        <Object?, Object?>{...valid, 'aliases': 'alias'},
        <Object?, Object?>{
          ...valid,
          'aliases': <Object?>[1],
        },
        <Object?, Object?>{...valid, 'monospace': 1},
      ];

      expect(malformed.map(SystemFontFamily.tryDecode), everyElement(isNull));
    });
  });

  test('FileTypeFilter snapshots collections and has value equality', () {
    final extensions = <String>['png'];
    final filter = FileTypeFilter(
      label: 'Images',
      extensions: extensions,
      mimeTypes: const ['image/png'],
      uniformTypeIdentifiers: const ['public.png'],
    );
    extensions.add('jpg');

    expect(
      filter,
      FileTypeFilter(
        label: 'Images',
        extensions: const ['png'],
        mimeTypes: const ['image/png'],
        uniformTypeIdentifiers: const ['public.png'],
      ),
    );
    expect(() => filter.extensions.add('gif'), throwsUnsupportedError);
  });

  test('window values and menu configuration use value equality', () {
    final width = double.parse('1280');
    final height = double.parse('800');
    final fileMenuLabel = String.fromCharCodes(<int>[70, 105, 108, 101]);
    final size = WindowSize(width: width, height: height);
    final configuration = WindowBootstrapConfiguration(
      size: size,
      minimumSize: const WindowSize(width: 900, height: 560),
      title: 'Zeta',
      backgroundColorArgb: 0xFF101010,
    );

    expect(size, WindowSize(width: width, height: height));
    expect(
      configuration,
      WindowBootstrapConfiguration(
        size: WindowSize(width: width, height: height),
        minimumSize: const WindowSize(width: 900, height: 560),
        title: 'Zeta',
        backgroundColorArgb: 0xFF101010,
      ),
    );
    expect(
      MenuConfiguration(
        fileMenuLabel: fileMenuLabel,
        openProjectLabel: 'Open Project',
      ),
      MenuConfiguration(
        fileMenuLabel: fileMenuLabel,
        openProjectLabel: 'Open Project',
      ),
    );
    expect(WindowLifecycleEvent.values, hasLength(7));
    expect(MenuCommand.values, [MenuCommand.openProject]);
  });
}
