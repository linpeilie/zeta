import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'architecture_test_support.dart';

void main() {
  group('workspace package dependency graph', () {
    late ArchitectureWorkspace workspace;
    late Map<String, String> packageLayers;

    setUp(() {
      workspace = ArchitectureWorkspace.load();
      packageLayers = workspace.packageLayers;
    });

    test('uses path dependencies at every local package boundary', () {
      final violations = <String>[];
      for (final package in workspace.packages.values) {
        final dependencies = package.dependencies;
        if (dependencies == null) {
          continue;
        }
        for (final dependency in dependencies.keys.whereType<String>()) {
          if (!workspace.packages.containsKey(dependency)) {
            continue;
          }
          final specification = dependencies[dependency];
          if (specification is! YamlMap || specification['path'] is! String) {
            violations.add('${package.name} -> $dependency');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Local dependencies must use path:.\n${violations.join('\n')}',
      );
    });

    test('enforces allowed local dependency layers', () {
      final violations = <String>[];
      for (final package in workspace.packages.values) {
        final layer = packageLayers[package.name]!;
        final allowedLayers = _allowedDependencyLayers[layer]!;
        for (final dependency in package.dependencyNames) {
          final dependencyLayer = packageLayers[dependency];
          if (dependencyLayer != null &&
              !allowedLayers.contains(dependencyLayer)) {
            violations.add(
              '${package.name} ($layer) -> '
              '$dependency ($dependencyLayer)',
            );
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Layer dependency violations:\n${violations.join('\n')}',
      );
    });

    test('forbids repository-to-repository dependencies', () {
      final repositories = workspace.packagesInLayer('repository');
      final violations = <String>[];
      for (final repository in repositories) {
        final dependencies = workspace.packages[repository]!.dependencyNames;
        for (final dependency in dependencies) {
          if (repositories.contains(dependency)) {
            violations.add('$repository -> $dependency');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Repositories must remain isolated.\n${violations.join('\n')}',
      );
    });

    test('forbids vendor-client cross-dependencies', () {
      final vendors = workspace.stringsAt([
        'layers',
        'data',
        'vendor_packages',
      ]);
      final violations = <String>[];
      for (final vendor in vendors) {
        for (final dependency in workspace.packages[vendor]!.dependencyNames) {
          if (vendors.contains(dependency)) {
            violations.add('$vendor -> $dependency');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Vendor clients must be mutually isolated.\n'
            '${violations.join('\n')}',
      );
    });

    test('keeps contracts, data, and repositories Flutter-free', () {
      final nonFlutterPackages = {
        ...workspace.packagesInLayer('contracts'),
        ...workspace.packagesInLayer('data'),
        ...workspace.packagesInLayer('repository'),
      };
      final violations = <String>[];
      for (final name in nonFlutterPackages) {
        final package = workspace.packages[name]!;
        if (package.dependsOnFlutter) {
          violations.add('${package.name}/pubspec.yaml -> flutter');
        }
        for (final file in workspace.dartFilesForPackage(package)) {
          for (final uri in workspace.directives(file)) {
            if (uri == 'dart:ui' ||
                uri.startsWith('package:flutter/') ||
                uri.startsWith('package:flutter_')) {
              violations.add('${workspace.relativePath(file)} -> $uri');
            }
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Pure-Dart layers imported Flutter.\n${violations.join('\n')}',
      );
    });

    test('exposes every package through its public barrel', () {
      final libraryPackages = packageLayers.entries
          .where((entry) => entry.value != 'tooling')
          .map((entry) => workspace.packages[entry.key]!);
      final missing = libraryPackages
          .where((package) => !package.barrel.existsSync())
          .map((package) => workspace.relativePath(package.barrel))
          .toList();
      expect(
        missing,
        isEmpty,
        reason: 'Missing package barrels:\n${missing.join('\n')}',
      );
    });

    test('keeps ADR-001 production dependencies within its exception', () {
      final contracts = workspace.packages['agent_provider_contracts']!;
      final allowed = workspace.stringsAt([
        'adr_001',
        'allowed_dependency_packages',
      ]);
      expect(contracts.dependencyNames.difference(allowed), isEmpty);
    });
  });
}

const _allowedDependencyLayers = <String, Set<String>>{
  'contracts': {},
  'data': {'contracts', 'data'},
  'repository': {'contracts', 'data'},
  'presentation': {},
  'tooling': {'presentation'},
};
