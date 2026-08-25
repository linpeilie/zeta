import 'package:flutter_test/flutter_test.dart';

import '../../../tool/packaging/release_metadata.dart';

void main() {
  group('ReleaseMetadata.parse', () {
    test('parses a stable release', () {
      final metadata = ReleaseMetadata.parse(
        tag: 'v1.2.3',
        pubspecContents: 'name: zeta\nversion: 1.2.3+4\n',
      );

      expect(metadata.releaseVersion, '1.2.3');
      expect(metadata.appFullVersion, '1.2.3+4');
      expect(metadata.prerelease, isFalse);
      expect(metadata.linuxPackageVersion, '1.2.3');
      expect(metadata.rpmRelease, '4');
    });

    test('parses a beta release and preserves package ordering', () {
      final metadata = ReleaseMetadata.parse(
        tag: 'v1.2.3-beta.5',
        pubspecContents: 'version: 1.2.3+9\n',
      );

      expect(metadata.releaseVersion, '1.2.3-beta.5');
      expect(metadata.prerelease, isTrue);
      expect(metadata.linuxPackageVersion, '1.2.3~beta.5');
      expect(metadata.rpmRelease, '9');
      expect(metadata.toGitHubOutputs()['prerelease'], 'true');
    });

    test('rejects a tag whose core differs from pubspec', () {
      expect(
        () => ReleaseMetadata.parse(
          tag: 'v1.2.4',
          pubspecContents: 'version: 1.2.3+4\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    for (final tag in <String>[
      '1.2.3',
      'v1.2.3-rc.1',
      'v1.2.3-beta.0',
      'v1.2.3-beta.01',
      'v01.2.3',
    ]) {
      test('rejects invalid tag $tag', () {
        expect(
          () => ReleaseMetadata.parse(
            tag: tag,
            pubspecContents: 'version: 1.2.3+4\n',
          ),
          throwsA(isA<FormatException>()),
        );
      });
    }

    for (final version in <String>[
      'version: 1.2.3\n',
      'version: 1.2.3+0\n',
      'version: 1.2.3-beta.1+4\n',
    ]) {
      test('rejects invalid pubspec version ${version.trim()}', () {
        expect(
          () => ReleaseMetadata.parse(tag: 'v1.2.3', pubspecContents: version),
          throwsA(isA<FormatException>()),
        );
      });
    }
  });
}
