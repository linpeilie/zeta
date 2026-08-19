import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'architecture_test_support.dart';

void main() {
  group('source dependency boundaries', () {
    late ArchitectureWorkspace workspace;
    late Map<String, String> packageLayers;

    setUp(() {
      workspace = ArchitectureWorkspace.load();
      packageLayers = workspace.packageLayers;
    });

    test('forbids external package src imports and package-to-app imports', () {
      final violations = <String>[];
      for (final file in workspace.productionDartFiles) {
        final owner = workspace.ownerPackageName(file);
        for (final uri in workspace.directives(file)) {
          final importedPackage = packageNameFromUri(uri);
          if (importedPackage == null) {
            continue;
          }
          if (uri.startsWith('package:$importedPackage/src/') &&
              importedPackage != owner) {
            violations.add('${workspace.relativePath(file)} -> $uri');
          }
          if (owner != 'zeta' && importedPackage == 'zeta') {
            violations.add('${workspace.relativePath(file)} -> $uri');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Package encapsulation violations:\n${violations.join('\n')}',
      );
    });

    test('allows app Data imports only in bootstrap', () {
      final dataPackages = workspace.packagesInLayer('data');
      final allowed = workspace.stringsAt([
        'composition_root',
        'data_package_import_allowlist',
      ]);
      final violations = <String>[];
      for (final file in _appDartFiles(workspace)) {
        final path = workspace.relativePath(file);
        final isPlatformAdapter = workspace.matchesConfiguredPath(
          path,
          ['composition_root', 'platform_adapter_roots'],
        );
        for (final uri in workspace.directives(file)) {
          final dependency = packageNameFromUri(uri);
          if (dependency != null &&
              dataPackages.contains(dependency) &&
              !(dependency == 'desktop_platform_api' && isPlatformAdapter) &&
              !allowed.any((pattern) => matchesGlob(path, pattern))) {
            violations.add('$path -> $uri');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'App Data imports must stay in bootstrap.dart.\n'
            '${violations.join('\n')}',
      );
    });

    test('keeps desktop platform ports out of Bloc and Presentation', () {
      final violations = <String>[];
      for (final file in _appDartFiles(workspace)) {
        final path = workspace.relativePath(file);
        final isBusinessLogic = workspace.matchesConfiguredPath(
          path,
          ['layers', 'business_logic', 'roots'],
        );
        final isPresentation = workspace.matchesConfiguredPath(
          path,
          ['layers', 'presentation', 'roots'],
        );
        if (!isBusinessLogic && !isPresentation) {
          continue;
        }
        for (final uri in workspace.directives(file)) {
          if (packageNameFromUri(uri) == 'desktop_platform_api') {
            violations.add('$path -> $uri');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Platform ports are consumed through Repositories only.\n'
            '${violations.join('\n')}',
      );
    });

    test('keeps app IO and Flutter services inside their boundaries', () {
      final violations = <String>[];
      for (final file in _appDartFiles(workspace)) {
        final path = workspace.relativePath(file);
        final isBootstrap = path == 'lib/bootstrap.dart';
        final isPlatformAdapter = workspace.matchesConfiguredPath(
          path,
          ['composition_root', 'platform_adapter_roots'],
        );
        for (final uri in workspace.directives(file)) {
          if (uri == 'dart:io' && !isBootstrap && !isPlatformAdapter) {
            violations.add('$path -> $uri');
          }
          if (uri == 'package:flutter/services.dart' && !isPlatformAdapter) {
            violations.add('$path -> $uri');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'App platform boundary violations:\n${violations.join('\n')}',
      );
    });

    test('limits platform adapters to approved imports', () {
      final allowedImports = workspace.stringsAt([
        'composition_root',
        'platform_adapter_allowed_imports',
      ]);
      final violations = <String>[];
      for (final file in _appDartFiles(workspace)) {
        final path = workspace.relativePath(file);
        if (!workspace.matchesConfiguredPath(
          path,
          ['composition_root', 'platform_adapter_roots'],
        )) {
          continue;
        }
        for (final uri in workspace.directives(file)) {
          if (!uri.startsWith('package:')) {
            continue;
          }
          final isAllowed = allowedImports.any(
            (allowed) => allowed.endsWith('/')
                ? uri.startsWith(allowed)
                : uri == allowed,
          );
          if (!isAllowed) {
            violations.add('$path -> $uri');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Platform adapter import violations:\n'
            '${violations.join('\n')}',
      );
    });

    test('limits repository imports to composition and Page boundaries', () {
      final repositories = workspace.packagesInLayer('repository');
      final allowed = workspace.stringsAt([
        'composition_root',
        'repository_package_import_allowlist',
      ]);
      final violations = <String>[];
      for (final file in _appDartFiles(workspace)) {
        final path = workspace.relativePath(file);
        for (final uri in workspace.directives(file)) {
          final dependency = packageNameFromUri(uri);
          if (dependency != null &&
              repositories.contains(dependency) &&
              !allowed.any((pattern) => matchesGlob(path, pattern))) {
            violations.add('$path -> $uri');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Repository imports bypassed an allowed boundary.\n'
            '${violations.join('\n')}',
      );
    });

    test('keeps business logic free of forbidden imports and Bloc peers', () {
      final forbiddenImports = workspace.stringsAt([
        'layers',
        'business_logic',
        'forbidden_imports',
      ]);
      final dataPackages = workspace.packagesInLayer('data');
      final violations = <String>[];
      for (final file in _appDartFiles(workspace)) {
        final path = workspace.relativePath(file);
        if (!workspace.matchesConfiguredPath(
          path,
          ['layers', 'business_logic', 'roots'],
        )) {
          continue;
        }
        final source = sourceWithoutComments(file.readAsStringSync());
        for (final uri in directiveUris(source)) {
          final dependency = packageNameFromUri(uri);
          if (forbiddenImports.any(
                (forbidden) => forbidden.endsWith('/')
                    ? uri.startsWith(forbidden)
                    : uri == forbidden,
              ) ||
              (dependency != null && dataPackages.contains(dependency))) {
            violations.add('$path -> $uri');
          }
        }
        if (_blocDependencyPattern.hasMatch(source)) {
          violations.add('$path -> Bloc/Cubit constructor dependency');
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Business-logic boundary violations:\n'
            '${violations.join('\n')}',
      );
    });

    test('keeps app_ui independent from app copy and lower layers', () {
      final appUi = workspace.packages['app_ui']!;
      final forbiddenPatterns = workspace.stringsAt([
        'layers',
        'presentation',
        'app_ui_forbidden_import_prefixes',
      ]);
      final violations = <String>[];
      for (final file in workspace.dartFilesForPackage(appUi)) {
        final source = file.readAsStringSync();
        for (final uri in directiveUris(source)) {
          final isForbidden = forbiddenPatterns.any(
            (pattern) => matchesGlob(uri, '$pattern*'),
          );
          if (isForbidden) {
            violations.add('${workspace.relativePath(file)} -> $uri');
          }
        }
        if (RegExp(r'\bAppLocalizations\b').hasMatch(source)) {
          violations.add(
            '${workspace.relativePath(file)} -> AppLocalizations',
          );
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'app_ui boundary violations:\n${violations.join('\n')}',
      );
    });

    test('keeps every package independent from AppLocalizations', () {
      final violations = <String>[];
      for (final package in workspace.packages.values) {
        for (final file in workspace.dartFilesForPackage(package)) {
          if (RegExp(r'\bAppLocalizations\b')
              .hasMatch(file.readAsStringSync())) {
            violations.add(workspace.relativePath(file));
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Packages must receive copy as data.\n${violations.join('\n')}',
      );
    });

    test('rejects GoRouter extra and raw-path navigation', () {
      final violations = <String>[];
      for (final file in _appDartFiles(workspace)) {
        final source = sourceWithoutComments(file.readAsStringSync());
        if (_goRouterExtraPattern.hasMatch(source)) {
          violations.add('${workspace.relativePath(file)} -> extra:');
        }
        if (_rawPathNavigationPattern.hasMatch(source)) {
          violations.add('${workspace.relativePath(file)} -> raw path');
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Navigation must use generated typed routes.\n'
            '${violations.join('\n')}',
      );
    });

    test('keeps non-Page presentation code from importing repositories', () {
      final repositories = packageLayers.entries
          .where((entry) => entry.value == 'repository')
          .map((entry) => entry.key)
          .toSet();
      final violations = <String>[];
      for (final file in _appDartFiles(workspace)) {
        final path = workspace.relativePath(file);
        final isPresentation = workspace.matchesConfiguredPath(
          path,
          ['layers', 'presentation', 'roots'],
        );
        if (!isPresentation || path.endsWith('_page.dart')) {
          continue;
        }
        for (final uri in workspace.directives(file)) {
          final dependency = packageNameFromUri(uri);
          if (dependency != null && repositories.contains(dependency)) {
            violations.add('$path -> $uri');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Widgets and Views must not call repositories.\n'
            '${violations.join('\n')}',
      );
    });
  });
}

Iterable<File> _appDartFiles(ArchitectureWorkspace workspace) {
  return Directory('${workspace.root.path}/lib')
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}

final _blocDependencyPattern = RegExp(
  r'\b[A-Z]\w*(?:Bloc|Cubit)\??\s+[_a-z]\w*\s*(?=[,;)=])',
);
final _goRouterExtraPattern = RegExp(r'\bextra\s*:');
final _rawPathNavigationPattern = RegExp(
  r'''\.(?:go|push|replace|pushReplacement)\s*\(\s*['"]/''',
);
