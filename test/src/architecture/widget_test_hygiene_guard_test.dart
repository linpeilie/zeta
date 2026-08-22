import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget 测试卫生守卫。
///
/// 自动化测试**不得拉起真实 Agent CLI**：不注入 `agentProviderFactory` 时，
/// `MainApp` 会构造真实的 `DefaultAgentProviderFactory`，Shell 启动阶段的模型
/// 目录预热就会去启动本机 Codex/Grok/Claude 进程，并注册 30 秒的 JSON-RPC
/// 超时 `Timer`。该 Timer 常常活过 widget 树销毁，于是测试以
/// "A Timer is still pending even after the widget tree was disposed" 随机失败——
/// 失败与否取决于本机是否装了 CLI、进程起得多快，属于最难排查的一类 flake。
///
/// 真实 CLI 的验收走 `tool/smoke_*.py`，不走 Widget 测试。
///
/// **这条守卫用 AST 而不是正则**：早期的文本实现只判断参数文本里是否出现过
/// `agentProviderFactory`，于是下面这种写法能骗过它——
///
/// ```dart
/// MainApp(
///   // TODO: inject agentProviderFactory
/// )
/// ```
///
/// 括号配对同样会被字符串和注释里的括号带偏。analyzer 解析出的 AST 天然不含
/// 注释，命名实参也是结构化的，没有这类漏洞。
void main() {
  test('测试构造 MainApp 时必须显式注入 Agent provider 工厂', () {
    final offenders = <String>[];
    var scanned = 0;
    for (final file in _dartFilesUnder('test')) {
      final path = _posix(file.path);
      final source = file.readAsStringSync();
      final parsed = parseString(content: source, throwIfDiagnostics: false);
      if (parsed.errors.isNotEmpty && parsed.unit.declarations.isEmpty) {
        offenders.add('$path: 无法解析（语法错误）');
        continue;
      }

      final visitor = _MainAppConstructionVisitor();
      parsed.unit.accept(visitor);
      scanned += visitor.constructions.length;
      for (final construction in visitor.constructions) {
        if (construction.hasAgentProviderFactory) {
          continue;
        }
        final line = parsed.lineInfo
            .getLocation(construction.offset)
            .lineNumber;
        offenders.add('$path:$line');
      }
    }

    // 防止守卫变成空转：真的扫到了 MainApp 构造点，才谈得上"没有违规"。
    expect(scanned, greaterThan(0), reason: '没有扫到任何 MainApp 构造点，守卫多半失效了');
    expect(
      offenders,
      isEmpty,
      reason:
          '这些测试会拉起真实 Agent CLI，并留下 30 秒 JSON-RPC Timer。'
          '请注入 FakeAgentProviderBundleBuilder：\n${offenders.join('\n')}',
    );
  });

  test('守卫本身识别得出注释伪装', () {
    // 回归用例：文本实现会放过这段代码，AST 实现必须抓住。
    const disguised = '''
void main() {
  final widget = MainApp(
    // TODO: inject agentProviderFactory
    enableNativeWindowFrame: false,
  );
  final ok = MainApp(agentProviderFactory: factory);
}
''';
    final parsed = parseString(content: disguised, throwIfDiagnostics: false);
    final visitor = _MainAppConstructionVisitor();
    parsed.unit.accept(visitor);

    expect(visitor.constructions, hasLength(2));
    expect(visitor.constructions.first.hasAgentProviderFactory, isFalse);
    expect(visitor.constructions.last.hasAgentProviderFactory, isTrue);
  });
}

/// 一次 `MainApp(...)` 构造及其命名实参判定。
final class _MainAppConstruction {
  const _MainAppConstruction({
    required this.offset,
    required this.hasAgentProviderFactory,
  });

  final int offset;
  final bool hasAgentProviderFactory;
}

/// 收集所有 `MainApp(...)` 构造点。
///
/// 只做语法解析（不做元素解析）时，省略 `new` 的构造在 AST 里是
/// [MethodInvocation] 而不是 [InstanceCreationExpression]，两种都要看。
/// `_pumpMainApp(...)` 不会被误判：方法名要求完全相等。
final class _MainAppConstructionVisitor extends RecursiveAstVisitor<void> {
  final List<_MainAppConstruction> constructions = <_MainAppConstruction>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'MainApp') {
      _record(node.offset, node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == 'MainApp') {
      _record(node.offset, node.argumentList);
    }
    super.visitMethodInvocation(node);
  }

  void _record(int offset, ArgumentList arguments) {
    constructions.add(
      _MainAppConstruction(
        offset: offset,
        hasAgentProviderFactory: arguments.arguments
            .whereType<NamedExpression>()
            .any(
              (argument) => argument.name.label.name == 'agentProviderFactory',
            ),
      ),
    );
  }
}

Iterable<File> _dartFilesUnder(String directory) {
  return Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}

String _posix(String path) => path.replaceAll(r'\', '/');
