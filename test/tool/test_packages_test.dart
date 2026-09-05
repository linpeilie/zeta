import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory sandbox;
  late File calls;
  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('zeta-package-runner-');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    Directory('${sandbox.path}/tool').createSync();
    File(
      'tool/test_packages.sh',
    ).copySync('${sandbox.path}/tool/test_packages.sh');
    Directory('${sandbox.path}/bin').createSync();
    calls = File('${sandbox.path}/calls');
    for (final runner in ['dart', 'flutter']) {
      final stub = File('${sandbox.path}/bin/$runner');
      stub.writeAsStringSync(r'''#!/usr/bin/env bash
printf '%s|%s|%s\n' "${PWD##*/}" "${0##*/}" "$*" >> "$TASK_CALLS"
[[ "${TASK_FAIL:-}" != "${PWD##*/}:$1" ]]
''');
      Process.runSync('chmod', ['+x', stub.path]);
    }
    for (final (name, flutter) in [('zeta_a', false), ('zeta_b', true)]) {
      Directory(
        '${sandbox.path}/packages/$name/test',
      ).createSync(recursive: true);
      File('${sandbox.path}/packages/$name/pubspec.yaml').writeAsStringSync(
        'name: $name\n${flutter ? "dependencies:\n  flutter:\n    sdk: flutter\n" : ""}',
      );
    }
  });
  ProcessResult run(List<String> args, {String? fail}) => Process.runSync(
    'bash',
    ['${sandbox.path}/tool/test_packages.sh', ...args],
    environment: {
      'PATH': '${sandbox.path}/bin:${Platform.environment['PATH']}',
      'TASK_CALLS': calls.path,
      'TASK_FAIL': ?fail,
    },
  );
  test('不传选择参数自动发现全部包，使用各自工具链且参数逐字透传', () {
    final result = run(['--plain-name', 'two words']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(calls.readAsLinesSync(), [
      'zeta_a|dart|analyze',
      'zeta_a|dart|test --plain-name two words',
      'zeta_b|flutter|analyze',
      'zeta_b|flutter|test --plain-name two words',
    ]);
  });
  test('--only 仅分析并测试一个包', () {
    expect(run(['--only', 'zeta_b']).exitCode, 0);
    expect(calls.readAsLinesSync(), [
      'zeta_b|flutter|analyze',
      'zeta_b|flutter|test',
    ]);
  });
  test('空参数、重复选择与路径穿越失败，绝不误跑全量', () {
    for (final args in <List<String>>[
      ['--only'],
      ['--only', '../zeta_a'],
      ['--only', 'zeta_a', '--only', 'zeta_b'],
      ['--only', 'missing'],
      ['--list-json', '--only', 'zeta_a'],
    ]) {
      expect(run(args).exitCode, isNot(0));
    }
    expect(calls.existsSync(), isFalse);
  });
  test('分析或测试失败保留退出码并继续后续包', () {
    for (final stage in ['analyze', 'test']) {
      if (calls.existsSync()) calls.deleteSync();
      expect(run([], fail: 'zeta_a:$stage').exitCode, 1);
      expect(calls.readAsLinesSync().last, 'zeta_b|flutter|test');
    }
  });
  test('--list-json 动态发现新增包，不调用工具链', () {
    Directory(
      '${sandbox.path}/packages/zeta_future/test',
    ).createSync(recursive: true);
    File(
      '${sandbox.path}/packages/zeta_future/pubspec.yaml',
    ).writeAsStringSync('name: zeta_future');
    final result = run(['--list-json']);
    expect(result.exitCode, 0);
    expect(jsonDecode(result.stdout as String), [
      'zeta_a',
      'zeta_b',
      'zeta_future',
    ]);
    expect(calls.existsSync(), isFalse);
  });
  test('零测试包 fail-closed，避免空矩阵变绿', () {
    Directory('${sandbox.path}/packages').deleteSync(recursive: true);
    expect(run([]).exitCode, 66);
    expect(run(['--list-json']).exitCode, 66);
  });
}
