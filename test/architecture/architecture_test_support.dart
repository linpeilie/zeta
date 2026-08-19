import 'dart:io';

import 'package:yaml/yaml.dart';

final class ArchitectureWorkspace {
  ArchitectureWorkspace._({
    required this.root,
    required this.configuration,
    required this.packages,
  });

  factory ArchitectureWorkspace.load() {
    final root = _findWorkspaceRoot();
    final configuration = loadYaml(
      File('${root.path}/.architecture.yaml').readAsStringSync(),
    );
    if (configuration is! YamlMap) {
      throw const FormatException('.architecture.yaml must contain a map.');
    }

    final packages = <String, WorkspacePackage>{};
    _visitPackageDirectories(
      Directory('${root.path}/packages'),
      onPubspec: (pubspecFile) {
        final pubspec = loadYaml(pubspecFile.readAsStringSync());
        if (pubspec is! YamlMap || pubspec['name'] is! String) {
          throw FormatException(
            '${pubspecFile.path} must contain a package name.',
          );
        }
        final name = pubspec['name']! as String;
        packages[name] = WorkspacePackage(
          name: name,
          root: pubspecFile.parent,
          pubspec: pubspec,
        );
      },
    );

    return ArchitectureWorkspace._(
      root: root,
      configuration: configuration,
      packages: Map.unmodifiable(packages),
    );
  }

  final Directory root;
  final YamlMap configuration;
  final Map<String, WorkspacePackage> packages;

  YamlMap mapAt(List<String> path) {
    Object? value = configuration;
    for (final segment in path) {
      if (value is! YamlMap) {
        throw FormatException('${path.join('.')} must contain a map.');
      }
      value = value[segment];
    }
    if (value is! YamlMap) {
      throw FormatException('${path.join('.')} must contain a map.');
    }
    return value;
  }

  Set<String> stringsAt(List<String> path) {
    Object? value = configuration;
    for (final segment in path) {
      if (value is! YamlMap) {
        throw FormatException('${path.join('.')} must contain a list.');
      }
      value = value[segment];
    }
    if (value is! YamlList || value.any((item) => item is! String)) {
      throw FormatException('${path.join('.')} must contain strings.');
    }
    return value.cast<String>().toSet();
  }

  Set<String> packagesInLayer(String layer) =>
      stringsAt(['layers', layer, 'packages']);

  Map<String, String> get packageLayers {
    final result = <String, String>{};
    for (final layer in const [
      'contracts',
      'data',
      'repository',
      'presentation',
      'tooling',
    ]) {
      for (final package in packagesInLayer(layer)) {
        final previous = result[package];
        if (previous != null) {
          throw StateError('$package is registered in $previous and $layer.');
        }
        result[package] = layer;
      }
    }
    return result;
  }

  Iterable<File> get productionDartFiles sync* {
    yield* _dartFilesUnder(Directory('${root.path}/lib'));
    for (final package in packages.values) {
      yield* _dartFilesUnder(Directory('${package.root.path}/lib'));
    }
  }

  Iterable<File> dartFilesForPackage(WorkspacePackage package) =>
      _dartFilesUnder(Directory('${package.root.path}/lib'));

  String relativePath(FileSystemEntity entity) {
    final rootPath = normalizedPath(root.absolute.path);
    final entityPath = normalizedPath(entity.absolute.path);
    return entityPath.substring(rootPath.length + 1);
  }

  String ownerPackageName(File file) {
    final path = relativePath(file);
    if (path.startsWith('lib/')) {
      return 'zeta';
    }
    for (final package in packages.values) {
      final packagePath = normalizedPath(package.root.absolute.path);
      final filePath = normalizedPath(file.absolute.path);
      if (filePath.startsWith('$packagePath/')) {
        return package.name;
      }
    }
    throw StateError('No workspace package owns $path.');
  }

  List<String> directives(File file) => directiveUris(
    file.readAsStringSync(),
  );

  bool matchesConfiguredPath(String path, List<String> configPath) {
    return stringsAt(configPath).any(
      (pattern) => matchesGlob(path, pattern),
    );
  }
}

final class WorkspacePackage {
  const WorkspacePackage({
    required this.name,
    required this.root,
    required this.pubspec,
  });

  final String name;
  final Directory root;
  final YamlMap pubspec;

  YamlMap? get dependencies {
    final value = pubspec['dependencies'];
    return value is YamlMap ? value : null;
  }

  Set<String> get dependencyNames =>
      dependencies?.keys.whereType<String>().toSet() ?? const {};

  bool get dependsOnFlutter => dependencies?['flutter'] != null;

  File get barrel => File('${root.path}/lib/$name.dart');
}

List<String> directiveUris(String source) {
  return _directivePattern
      .allMatches(source)
      .map((match) => match.group(1)!)
      .toList(growable: false);
}

String? packageNameFromUri(String uri) {
  return _packageUriPattern.firstMatch(uri)?.group(1);
}

bool matchesGlob(String value, String pattern) {
  final expression = StringBuffer('^');
  var index = 0;
  while (index < pattern.length) {
    final character = pattern[index];
    if (character == '*') {
      final isDouble = index + 1 < pattern.length && pattern[index + 1] == '*';
      expression.write(isDouble ? '.*' : '[^/]*');
      index += isDouble ? 2 : 1;
      continue;
    }
    expression.write(RegExp.escape(character));
    index += 1;
  }
  expression.write(r'$');
  return RegExp(expression.toString()).hasMatch(value);
}

String normalizedPath(String path) => path.replaceAll(r'\', '/');

String sourceWithoutComments(String source) {
  return source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .split('\n')
      .map((line) {
        final comment = line.indexOf('//');
        return comment < 0 ? line : line.substring(0, comment);
      })
      .join('\n');
}

Directory _findWorkspaceRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (File('${directory.path}/.architecture.yaml').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not locate .architecture.yaml.');
    }
    directory = parent;
  }
}

void _visitPackageDirectories(
  Directory directory, {
  required void Function(File pubspec) onPubspec,
}) {
  if (!directory.existsSync()) {
    return;
  }
  final name = normalizedPath(directory.path).split('/').last;
  if (_ignoredDirectoryNames.contains(name)) {
    return;
  }

  final pubspec = File('${directory.path}/pubspec.yaml');
  if (pubspec.existsSync()) {
    onPubspec(pubspec);
  }
  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is Directory) {
      _visitPackageDirectories(entity, onPubspec: onPubspec);
    }
  }
}

Iterable<File> _dartFilesUnder(Directory directory) sync* {
  if (!directory.existsSync()) {
    return;
  }
  for (final entity in directory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

const _ignoredDirectoryNames = {
  '.dart_tool',
  'build',
  'coverage',
};

final _directivePattern = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);
final _packageUriPattern = RegExp('^package:([^/]+)/');
