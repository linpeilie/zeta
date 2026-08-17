import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 本地化 inventory 护栏：禁止新增未登记的用户可见字面量。
///
/// 扫描逻辑与 `tool/check_localized_ui_strings.dart` 共用同一入口，
/// 避免测试与 CLI 漂移。
void main() {
  test('user-visible literals stay within the baseline allowlist', () async {
    final result = await Process.run(
      'dart',
      ['run', 'tool/check_localized_ui_strings.dart', '--check'],
      workingDirectory: Directory.current.path,
      runInShell: true,
    );
    expect(
      result.exitCode,
      0,
      reason:
          '新增用户可见字面量必须先登记 allowlist 或改为 ARB。\n'
          'stdout:\n${result.stdout}\n'
          'stderr:\n${result.stderr}',
    );
  });

  test(
    'literal report locates file, line and field without log payloads',
    () async {
      final result = await Process.run(
        'dart',
        ['run', 'tool/check_localized_ui_strings.dart', '--report'],
        workingDirectory: Directory.current.path,
        runInShell: true,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stdout = result.stdout.toString();
      expect(stdout, startsWith('file\tline\tfield\tclassification\ttext\n'));
      final rows = stdout
          .split('\n')
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .skip(1)
          .toList();
      for (final row in rows.take(20)) {
        final columns = row.split('\t');
        expect(columns.length, 5, reason: row);
        expect(columns[0], startsWith('lib/'));
        expect(int.tryParse(columns[1]), isNonZero);
        expect(columns[2], isNotEmpty);
        expect(columns[3], 'zeta_copy');
      }
      expect(stdout, isNot(contains('developer.log')));
      expect(stdout.toLowerCase(), isNot(contains('password')));
      expect(stdout.toLowerCase(), isNot(contains('authorization')));
    },
  );

  test('allowlist is versioned JSON and only records production files', () {
    final file = File('tool/localization_literal_allowlist.json');
    expect(file.existsSync(), isTrue);
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['version'], 1);
    final entries = decoded['entries'] as List<dynamic>;
    for (final raw in entries) {
      final entry = raw as Map<String, dynamic>;
      expect(entry['file'], startsWith('lib/'));
      expect(entry['file'], isNot(contains('/generated/')));
      expect(entry['classification'], 'zeta_copy');
      expect((entry['text'] as String).trim(), isNotEmpty);
    }
  });
}
