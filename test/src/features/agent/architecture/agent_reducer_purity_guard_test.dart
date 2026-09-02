import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// G3 守卫：reducer 只能"描述"变化，不能"执行"变化。
void main() {
  const reducerSources = <String>[
    'packages/zeta_agent_core/lib/src/application/agent_conversation_reducer.dart',
    // P5 之后追加 handlers/ 目录下全部文件（用 glob 展开）
  ];

  const forbidden = <String, String>{
    r'\.applyTo\(': 'reducer 不得执行 timeline mutation（G3）',
    r'\bunawaited\(': 'reducer 不得发起异步（G3）',
    r'\bTimer\b': 'reducer 不得创建 Timer（G3）',
    r'\bawait\b': 'reducer 必须纯同步（G3）',
    r'SchedulerBinding': 'reducer 不得触碰 Flutter scheduler（G3）',
  };

  test('reducer 源码不含副作用调用', () {
    for (final path in reducerSources) {
      // 注释里提及是允许的。沿用既有惯例：按行过滤，不做 AST 解析。
      // 参考 agent_file_change_presentation_purity_test.dart:102-105。
      final codeLines = File(path)
          .readAsLinesSync()
          .where((line) {
            final trimmed = line.trimLeft();
            return !trimmed.startsWith('//') && !trimmed.startsWith('///');
          })
          .join('\n');
      for (final entry in forbidden.entries) {
        expect(
          RegExp(entry.key).allMatches(codeLines),
          isEmpty,
          reason: '$path: ${entry.value}',
        );
      }
    }
  });
}
