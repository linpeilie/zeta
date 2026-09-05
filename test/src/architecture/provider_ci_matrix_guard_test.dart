import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CI packages 动态矩阵连接到自动发现入口和 --only runner', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();
    expect(_matrixWired(workflow), isTrue);
    final discovered = Process.runSync('bash', [
      'tool/test_packages.sh',
      '--list-json',
    ]);
    expect(discovered.exitCode, 0, reason: '${discovered.stderr}');
    final packages = (jsonDecode(discovered.stdout as String) as List)
        .cast<String>();
    final expected =
        Directory('packages')
            .listSync(followLinks: false)
            .whereType<Directory>()
            .where(
              (dir) =>
                  File('${dir.path}/pubspec.yaml').existsSync() &&
                  Directory('${dir.path}/test').existsSync(),
            )
            .map((dir) => dir.path.split(Platform.pathSeparator).last)
            .toList()
          ..sort();
    expect(packages, expected);
    expect(packages.toSet(), hasLength(packages.length));
    expect(packages, isNotEmpty);
  });
  test('反例：冻结矩阵或丢失 --only 均使 CI 接线守卫失败', () {
    final source = File('.github/workflows/ci.yml').readAsStringSync();
    for (final token in _required) {
      expect(
        _matrixWired(source.replaceAll(token, 'broken')),
        isFalse,
        reason: token,
      );
    }
  });
}

const _required = [
  'needs: package-list',
  r'packages: ${{ steps.discover.outputs.packages }}',
  r'package: ${{ fromJSON(needs.package-list.outputs.packages) }}',
  'bash tool/test_packages.sh --list-json',
  r'echo "packages=$packages" >> "$GITHUB_OUTPUT"',
  r'bash tool/test_packages.sh --only ${{ matrix.package }}',
];
bool _matrixWired(String source) => _required.every(source.contains);
