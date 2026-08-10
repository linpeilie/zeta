import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 视觉 token 守卫：把「零阴影法则」和「圆角只走 token」变成可回归的门禁，
/// 而不是一次性清理。这些规则的正文见 `AGENTS.md` G9 与 `IdeEffects` 文档注释。
void main() {
  const effectsPath = 'lib/src/ui/core/ide_effects.dart';

  /// 递归收集 `lib/src` 下的 Dart 源文件。
  List<File> dartSources() {
    final root = Directory('lib/src');
    expect(root.existsSync(), isTrue, reason: '测试需要从仓库根目录运行，未找到 lib/src');
    return root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
  }

  /// 去掉行注释与文档注释，避免注释里提到 token 名被误判为违规。
  Iterable<({int number, String text})> codeLines(File file) sync* {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
        continue;
      }
      yield (number: i + 1, text: lines[i]);
    }
  }

  test('除 IdeEffects 外不得出现手写 BoxShadow', () {
    final violations = <String>[];
    for (final file in dartSources()) {
      final normalized = file.path.replaceAll(r'\', '/');
      if (normalized.endsWith(effectsPath)) {
        continue;
      }
      for (final line in codeLines(file)) {
        // `const <BoxShadow>[]` 是显式的「这里没有阴影」，允许保留。
        if (line.text.contains('BoxShadow(')) {
          violations.add('$normalized:${line.number}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '阴影只能来自 IdeEffects。层级请用 IdeColors 的表面阶梯加 1px 描边表达，'
          '需要新档位就去 $effectsPath 里补。违规位置：\n${violations.join('\n')}',
    );
  });

  test('Material elevation 不得出现在 IDE 壳层', () {
    final violations = <String>[];
    for (final file in dartSources()) {
      for (final line in codeLines(file)) {
        if (line.text.contains('elevation:')) {
          violations.add('${file.path.replaceAll(r'\', '/')}:${line.number}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Material elevation 会绕过零阴影法则。违规位置：\n${violations.join('\n')}',
    );
  });

  test('圆角只允许来自 IdeRadius', () {
    final violations = <String>[];
    // 数值由运行时尺寸算出的胶囊（如 BorderRadius.circular(barHeight)）不算魔法数字。
    final literalRadius = RegExp(r'(?:Border)?Radius\.circular\(\s*([\d.]+)');
    // CustomPainter 里的粒子/拖尾是绘制图元，不是 UI 容器，它们的半径描述的是
    // 形状本身（普遍小于 2px）。设计系统的圆角档位管的是容器，不管图元。
    const painterPrimitiveCeiling = 2.0;
    for (final file in dartSources()) {
      final normalized = file.path.replaceAll(r'\', '/');
      if (normalized.endsWith(effectsPath)) {
        continue;
      }
      for (final line in codeLines(file)) {
        final match = literalRadius.firstMatch(line.text);
        if (match == null) {
          continue;
        }
        final value = double.tryParse(match.group(1)!);
        if (value != null && value < painterPrimitiveCeiling) {
          continue;
        }
        violations.add('$normalized:${line.number}');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '圆角必须取自 IdeRadius 的 micro/small/medium/large/pill 五档，'
          '需要新档位就去 $effectsPath 里补。违规位置：\n${violations.join('\n')}',
    );
  });
}
