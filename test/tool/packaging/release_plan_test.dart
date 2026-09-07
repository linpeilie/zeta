import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/packaging/release_plan.dart';

void main() {
  test('reads beta identity while preserving native numeric version', () {
    final result = readReleasePlan(
      '{"schemaVersion":1,"version":"0.1.0-beta.13"}',
      'version: 0.1.0+2\n',
    );
    expect(result.tag, 'v0.1.0-beta.13');
    expect(result.appFullVersion, '0.1.0+2');
    expect(result.prerelease, isTrue);
  });

  test('rejects invalid schemas, versions and mismatched native versions', () {
    for (final contents in [
      '{"schemaVersion":2,"version":"0.1.0"}',
      '{"schemaVersion":1,"version":"v0.1.0"}',
      '{"schemaVersion":1,"version":"0.1.0-beta.0"}',
      '{"schemaVersion":1,"version":"0.1.0-beta.01"}',
      '{"schemaVersion":1,"version":"0.1.0-rc.1"}',
      '{"schemaVersion":1,"version":"0.2.0"}',
    ]) {
      expect(
        () => readReleasePlan(contents, 'version: 0.1.0+2\n'),
        throwsFormatException,
      );
    }
  });

  test('compares numeric components and beta numbers, not strings', () {
    validateReleaseProgression('v0.1.0-beta.12', ['v0.1.0-beta.9']);
    validateReleaseProgression('v0.10.0-beta.1', ['v0.9.9']);
    validateReleaseProgression('v1.0.0', ['v0.99.99']);
  });

  test('promotes beta to stable and accepts next-core beta', () {
    validateReleaseProgression('v0.1.0', ['v0.1.0-beta.99']);
    validateReleaseProgression('v0.1.1-beta.1', ['v0.1.0']);
  });

  test('rejects equality and rollback across both channels and all tags', () {
    for (final pair in [
      ['v0.1.0-beta.12', 'v0.1.0-beta.12'],
      ['v0.1.0-beta.11', 'v0.1.0-beta.12'],
      ['v0.1.0', 'v0.1.0'],
      ['v0.1.0-beta.99', 'v0.1.0'],
      ['v0.1.0', 'v0.2.0-beta.1'],
    ]) {
      expect(
        () => validateReleaseProgression(pair[0], ['v0.0.1', pair[1]]),
        throwsFormatException,
      );
    }
  });

  test('first release and unrelated tags do not invent a baseline', () {
    validateReleaseProgression('v0.1.0-beta.1', []);
    validateReleaseProgression('v0.1.0-beta.1', ['archive', 'v1.0.0-rc.1']);
    expect(
      () => validateReleaseProgression('v0.1.0-beta.01', []),
      throwsFormatException,
    );
  });

  test('CLI enforces notes, main baseline, and retry commit identity', () {
    final script = File('tool/packaging/release_plan.dart').absolute.path;
    final directory = Directory.systemTemp.createTempSync('zeta-release-plan-');
    addTearDown(() => directory.deleteSync(recursive: true));
    ProcessResult run(String command, List<String> args) => Process.runSync(
      command,
      args,
      workingDirectory: directory.path,
      runInShell: Platform.isWindows,
    );
    void git(List<String> args) {
      final result = run('git', args);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    void writePlan(String version) {
      File(
        '${directory.path}/release.json',
      ).writeAsStringSync(jsonEncode({'schemaVersion': 1, 'version': version}));
    }

    void commit() {
      git(['add', '.']);
      git(['commit', '-m', 'fixture']);
    }

    git(['init']);
    git(['config', 'user.email', 'fixture@example.invalid']);
    git(['config', 'user.name', 'Fixture']);
    File(
      '${directory.path}/pubspec.yaml',
    ).writeAsStringSync('version: 0.1.0+2\n');
    writePlan('0.1.0-beta.12');
    commit();
    git(['tag', 'v0.1.0-beta.12']);
    git(['branch', 'previous-main']);
    expect(run('dart', [script]).exitCode, isNot(0));

    writePlan('0.1.0-beta.13');
    expect(run('dart', [script]).exitCode, isNot(0)); // Missing notes.
    final notes = File(
      '${directory.path}/docs/zh/release/notes/v0.1.0-beta.13.md',
    );
    notes.parent.createSync(recursive: true);
    notes.writeAsStringSync('Release fixture\n');
    commit();
    final output = '${directory.path}/outputs';
    final success = run('dart', [
      script,
      '--previous-ref',
      'previous-main',
      '--github-output',
      output,
    ]);
    expect(success.exitCode, 0, reason: '${success.stderr}');
    expect(File(output).readAsStringSync(), contains('tag=v0.1.0-beta.13\n'));
    expect(run('dart', [script, '--previous-ref', 'HEAD']).exitCode, isNot(0));
    git(['tag', 'v0.1.0-beta.13']);
    expect(run('dart', [script]).exitCode, isNot(0));
    expect(run('dart', [script, '--allow-existing']).exitCode, 0);
    notes.writeAsStringSync('Changed fixture\n');
    commit();
    expect(run('dart', [script, '--allow-existing']).exitCode, isNot(0));
  });
}
