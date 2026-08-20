import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'architecture_test_support.dart';

void main() {
  group('architecture configuration', () {
    late ArchitectureWorkspace workspace;

    setUp(() {
      workspace = ArchitectureWorkspace.load();
    });

    test('registers every workspace package in exactly one layer', () {
      expect(
        workspace.packageLayers.keys.toSet(),
        workspace.packages.keys.toSet(),
      );
      expect(workspace.mapAt(['baseline'])['open_decisions'], 0);
    });

    test('keeps composition-root allowlists fixed to accepted ADRs', () {
      expect(
        workspace.stringsAt([
          'composition_root',
          'data_package_import_allowlist',
        ]),
        {'lib/bootstrap.dart'},
      );
      expect(
        workspace.stringsAt([
          'composition_root',
          'repository_package_import_allowlist',
        ]),
        {
          'lib/bootstrap.dart',
          'lib/**/bloc/**',
          'lib/**/cubit/**',
          'lib/**/view/*_page.dart',
        },
      );
      expect(
        workspace.stringsAt([
          'composition_root',
          'platform_adapter_allowed_imports',
        ]),
        {
          'package:desktop_platform_api/',
          'package:zeta/app/platform/',
          'package:flutter/services.dart',
          'package:file_selector/',
          'package:flutter_local_notifications/',
          'package:macos_window_utils/',
          'package:pasteboard/',
          'package:window_manager/',
        },
      );
    });

    test('keeps the contracts exception dependency list narrow', () {
      expect(
        workspace.stringsAt([
          'adr_001',
          'allowed_dependency_packages',
        ]),
        {'collection', 'equatable', 'meta'},
      );
      expect(
        workspace.stringsAt(['adr_001', 'forbidden_imports']),
        {'dart:io', 'package:flutter/', 'package:flutter_localizations/'},
      );
    });
  });

  group('continuous integration contract', () {
    late ArchitectureWorkspace workspace;
    late String qualityWorkflow;

    setUp(() {
      workspace = ArchitectureWorkspace.load();
      qualityWorkflow = File(
        '${workspace.root.path}/.github/workflows/main.yaml',
      ).readAsStringSync();
    });

    test('runs package gates in analyze-format-test-coverage order', () {
      expect(loadYaml(qualityWorkflow), isA<YamlMap>());
      final analyze = qualityWorkflow.indexOf('- name: Analyze');
      final format = qualityWorkflow.indexOf('- name: Check formatting');
      final testAndCoverage = qualityWorkflow.indexOf(
        '- name: Test and coverage',
      );

      expect(analyze, greaterThanOrEqualTo(0));
      expect(format, greaterThan(analyze));
      expect(testAndCoverage, greaterThan(format));
      expect(qualityWorkflow, contains('matrix.directory'));
      expect(qualityWorkflow, contains('bloc lint .'));
      expect(qualityWorkflow, contains('--coverage'));
      expect(qualityWorkflow, contains('--min-coverage 100'));
      expect(qualityWorkflow, contains('--exclude-tags golden'));
      expect(qualityWorkflow, isNot(contains('--check-ignore')));
      expect(
        qualityWorkflow,
        contains("--exclude-coverage '**/*.{g,freezed,gen}.dart'"),
      );
      expect(qualityWorkflow, contains('--timeout 120'));
      expect(
        qualityWorkflow,
        contains('--test-randomize-ordering-seed random'),
      );
    });

    test('runs tagged golden tests in a dedicated job', () {
      expect(qualityWorkflow, contains('\n  golden:\n'));
      expect(qualityWorkflow, contains('--no-optimization'));
      expect(qualityWorkflow, contains('--tags golden'));
      expect(qualityWorkflow, contains('flutter-version: 3.47.0'));
      expect(qualityWorkflow, contains('actions/upload-artifact@v7'));
      expect(qualityWorkflow, contains("'**/test/failures/*.png'"));
      expect(qualityWorkflow, isNot(contains('flutter test')));
      expect(
        RegExp(
          'dart pub global run very_good_cli:very_good test',
        ).allMatches(qualityWorkflow).length,
        greaterThanOrEqualTo(2),
      );
      expect(
        File('${workspace.root.path}/dart_test.yaml').readAsStringSync(),
        allOf(
          contains('test-randomize-ordering-seed: random'),
          contains('golden:'),
        ),
      );
      expect(
        File(
          '${workspace.root.path}/packages/app_ui/dart_test.yaml',
        ).readAsStringSync(),
        contains('golden:'),
      );
    });

    test('keeps vulnerability and license checks explicit', () {
      final osv = File(
        '${workspace.root.path}/.github/workflows/osv_scan.yaml',
      ).readAsStringSync();
      final licenses = File(
        '${workspace.root.path}/.github/workflows/license_check.yaml',
      ).readAsStringSync();

      expect(osv, contains('osv-scanner-reusable'));
      expect(osv, contains('--recursive'));
      expect(licenses, contains('packages check licenses'));
      expect(licenses, contains('--dependency-type=direct-main,transitive'));
      _expectEveryExceptionExplained(osv);
      _expectEveryExceptionExplained(licenses);
    });

    test('builds production on macOS, Windows, and Linux', () {
      final desktop = File(
        '${workspace.root.path}/.github/workflows/desktop_build.yaml',
      ).readAsStringSync();
      expect(desktop, contains('- linux'));
      expect(desktop, contains('- macos'));
      expect(desktop, contains('- windows'));
      expect(desktop, contains('- production'));
      expect(desktop, contains(r'main_${{ matrix.entrypoint }}.dart'));
    });
  });
}

void _expectEveryExceptionExplained(String workflow) {
  final comments = workflow
      .split('\n')
      .where((line) => line.trimLeft().startsWith('#'))
      .join('\n');
  final exceptionPattern = RegExp(
    r'--(?:ignore-vulns|skip-packages)=([^\s]+)',
  );
  for (final match in exceptionPattern.allMatches(workflow)) {
    for (final exception in match.group(1)!.split(',')) {
      expect(
        comments,
        contains(exception),
        reason: '$exception must have an adjacent reviewable rationale.',
      );
    }
  }
}
