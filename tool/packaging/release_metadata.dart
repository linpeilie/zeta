import 'dart:convert';
import 'dart:io';

/// GitHub Release 与各平台打包脚本共享的版本元数据。
final class ReleaseMetadata {
  const ReleaseMetadata({
    required this.tag,
    required this.releaseVersion,
    required this.appVersion,
    required this.buildNumber,
    required this.prerelease,
    required this.linuxPackageVersion,
  });

  final String tag;
  final String releaseVersion;
  final String appVersion;
  final int buildNumber;
  final bool prerelease;
  final String linuxPackageVersion;

  String get appFullVersion => '$appVersion+$buildNumber';

  String get rpmRelease => buildNumber.toString();

  factory ReleaseMetadata.parse({
    required String tag,
    required String pubspecContents,
  }) {
    final versionPart = r'(?:0|[1-9][0-9]*)';
    final corePattern = '$versionPart\\.$versionPart\\.$versionPart';
    final tagPattern = RegExp('^v($corePattern)(?:-beta\\.([1-9][0-9]*))?\$');
    final tagMatch = tagPattern.firstMatch(tag);
    if (tagMatch == null) {
      throw const FormatException(
        'Release tag must be vX.Y.Z or vX.Y.Z-beta.N with N greater than zero.',
      );
    }

    final pubspecPattern = RegExp(
      '^version:\\s*($corePattern)\\+([1-9][0-9]*)\\s*\$',
      multiLine: true,
    );
    final pubspecMatch = pubspecPattern.firstMatch(pubspecContents);
    if (pubspecMatch == null) {
      throw const FormatException(
        'pubspec.yaml must contain a numeric version and positive build number, such as 1.2.3+4.',
      );
    }

    final tagCore = tagMatch.group(1)!;
    final appVersion = pubspecMatch.group(1)!;
    if (tagCore != appVersion) {
      throw FormatException(
        'Release tag core $tagCore does not match pubspec version $appVersion.',
      );
    }

    final betaNumber = tagMatch.group(2);
    final buildNumber = int.parse(pubspecMatch.group(2)!);
    final prerelease = betaNumber != null;
    final releaseVersion = tag.substring(1);
    return ReleaseMetadata(
      tag: tag,
      releaseVersion: releaseVersion,
      appVersion: appVersion,
      buildNumber: buildNumber,
      prerelease: prerelease,
      linuxPackageVersion: prerelease
          ? '$appVersion~beta.$betaNumber'
          : appVersion,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'tag': tag,
    'release_version': releaseVersion,
    'app_version': appVersion,
    'build_number': buildNumber,
    'app_full_version': appFullVersion,
    'prerelease': prerelease,
    'linux_package_version': linuxPackageVersion,
    'rpm_release': rpmRelease,
  };

  Map<String, String> toGitHubOutputs() =>
      toJson().map((key, value) => MapEntry(key, value.toString()));
}

void main(List<String> arguments) {
  try {
    final options = _ReleaseMetadataOptions.parse(arguments);
    final pubspec = File(options.pubspecPath);
    if (!pubspec.existsSync()) {
      throw FileSystemException('pubspec.yaml not found', pubspec.path);
    }
    final metadata = ReleaseMetadata.parse(
      tag: options.tag,
      pubspecContents: pubspec.readAsStringSync(),
    );
    final githubOutputPath = options.githubOutputPath;
    if (githubOutputPath != null) {
      final contents = metadata
          .toGitHubOutputs()
          .entries
          .map((entry) => '${entry.key}=${entry.value}\n')
          .join();
      File(
        githubOutputPath,
      ).writeAsStringSync(contents, mode: FileMode.append, flush: true);
    }
    stdout.writeln(jsonEncode(metadata.toJson()));
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 66;
  }
}

final class _ReleaseMetadataOptions {
  const _ReleaseMetadataOptions({
    required this.tag,
    required this.pubspecPath,
    this.githubOutputPath,
  });

  final String tag;
  final String pubspecPath;
  final String? githubOutputPath;

  static _ReleaseMetadataOptions parse(List<String> arguments) {
    String? tag;
    String? pubspecPath;
    String? githubOutputPath;
    for (var index = 0; index < arguments.length; index += 2) {
      if (index + 1 >= arguments.length) {
        throw FormatException('Missing value for ${arguments[index]}.');
      }
      final value = arguments[index + 1];
      switch (arguments[index]) {
        case '--tag':
          if (tag != null) {
            throw const FormatException('--tag can only be provided once.');
          }
          tag = value;
        case '--pubspec':
          if (pubspecPath != null) {
            throw const FormatException('--pubspec can only be provided once.');
          }
          pubspecPath = value;
        case '--github-output':
          if (githubOutputPath != null) {
            throw const FormatException(
              '--github-output can only be provided once.',
            );
          }
          githubOutputPath = value;
        default:
          throw FormatException('Unknown option: ${arguments[index]}.');
      }
    }
    if (tag == null || pubspecPath == null) {
      throw const FormatException(
        'Usage: dart release_metadata.dart --tag <tag> --pubspec <pubspec.yaml> [--github-output <path>]',
      );
    }
    return _ReleaseMetadataOptions(
      tag: tag,
      pubspecPath: pubspecPath,
      githubOutputPath: githubOutputPath,
    );
  }
}
