import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// G1 守卫：共享 handler 目录零 Provider 依赖。
void main() {
  const reductionDir = 'packages/zeta_agent_core/lib/src/application/reduction';

  test('共享 handler 目录不出现 Provider 标识（G1）', () {
    final providerIdentifier = RegExp(
      r'(codex|grok|claude|cursor)',
      caseSensitive: false,
    );
    for (final entity in Directory(reductionDir).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final codeLines = entity.readAsLinesSync().where((line) {
        final trimmed = line.trimLeft();
        return !trimmed.startsWith('//') && !trimmed.startsWith('///');
      });
      for (final line in codeLines) {
        expect(
          providerIdentifier.hasMatch(line),
          isFalse,
          reason: '${entity.path} 在代码（非注释）中出现 Provider 标识',
        );
      }
    }
  });

  test('共享注册表不按 providerId 分支（G1）', () {
    final source = File(
      '$reductionDir/default_agent_handlers.dart',
    ).readAsStringSync();
    expect(source.contains('providerId =='), isFalse);
    expect(source.contains('switch (providerId'), isFalse);
  });
}
