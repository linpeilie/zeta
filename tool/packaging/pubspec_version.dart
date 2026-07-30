import 'dart:io';

void main(List<String> arguments) {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln(
      'Usage: dart run pubspec_version.dart '
      '<full|name|number|windows> [pubspec.yaml]',
    );
    exitCode = 64;
    return;
  }

  final pubspec = File(arguments.length == 2 ? arguments[1] : 'pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml not found: ${pubspec.path}');
    exitCode = 66;
    return;
  }

  final versionPattern = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?\s*$',
  );
  RegExpMatch? versionMatch;
  for (final line in pubspec.readAsLinesSync()) {
    versionMatch = versionPattern.firstMatch(line);
    if (versionMatch != null) {
      break;
    }
  }
  if (versionMatch == null) {
    stderr.writeln(
      'pubspec.yaml must contain a numeric version such as 1.2.3+4.',
    );
    exitCode = 65;
    return;
  }

  final buildName = versionMatch.group(1)!;
  final buildNumber = versionMatch.group(2);
  switch (arguments.first) {
    case 'full':
      stdout.writeln(
        buildNumber == null ? buildName : '$buildName+$buildNumber',
      );
    case 'name':
      stdout.writeln(buildName);
    case 'number':
      stdout.writeln(buildNumber ?? '0');
    case 'windows':
      stdout.writeln('${buildName.split('.').join('.')}.${buildNumber ?? '0'}');
    default:
      stderr.writeln('Unknown output format: ${arguments.first}');
      exitCode = 64;
  }
}
