import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget 测试卫生守卫。
///
/// 自动化测试**不得拉起真实 Agent CLI**：不覆盖 `agentProviderBundleFactoryProvider`
/// 时，组合根会激活真实的内置 Provider 插件，Shell 启动阶段的模型
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
/// zetaTestApp(
///   // TODO: override agentProviderBundleFactoryProvider
/// )
/// ```
///
/// 括号配对同样会被字符串和注释里的括号带偏。analyzer 解析出的 AST 天然不含
/// 注释，命名实参也是结构化的，没有这类漏洞。
void main() {
  test('测试构造 zetaTestApp 时必须显式覆盖 Agent provider 工厂', () {
    final offenders = <String>[];
    var scanned = 0;
    for (final file in _dartFilesUnder('test')) {
      final path = _posix(file.path);
      // 测试助手自己只是把 overrides 透传给组合根，判据落在它的调用方身上。
      if (path.endsWith('test/src/testing/zeta_test_app.dart')) {
        continue;
      }
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
        if (construction.overridesAgentProviderFactory) {
          continue;
        }
        final line = parsed.lineInfo
            .getLocation(construction.offset)
            .lineNumber;
        offenders.add('$path:$line');
      }
    }

    // 防止守卫变成空转：真的扫到了构造点，才谈得上"没有违规"。
    expect(scanned, greaterThan(0), reason: '没有扫到任何 zetaTestApp 构造点，守卫多半失效了');
    expect(
      offenders,
      isEmpty,
      reason:
          '这些测试会拉起真实 Agent CLI，并留下 30 秒 JSON-RPC Timer。'
          '请注入 FakeAgentProviderBundleBuilder：\n${offenders.join('\n')}',
    );
  });

  test('守卫只接受无条件的 Agent provider 工厂覆盖', () {
    // 回归用例：注释与条件列表元素都不能证明 override 在运行时一定存在。
    const disguised = '''
void main() {
  final widget = zetaTestApp(
    // TODO: override agentProviderBundleFactoryProvider
    hostMode: ZetaHostMode.ephemeral,
  );
  final ok = zetaTestApp(
    overrides: <Override>[
      agentProviderBundleFactoryProvider.overrideWithValue(factory),
    ],
  );
  final conditional = zetaTestApp(
    overrides: <Override>[
      if (factory != null)
        agentProviderBundleFactoryProvider.overrideWithValue(factory),
    ],
  );
}
''';
    final parsed = parseString(content: disguised, throwIfDiagnostics: false);
    final visitor = _MainAppConstructionVisitor();
    parsed.unit.accept(visitor);

    expect(visitor.constructions, hasLength(3));
    expect(visitor.constructions.first.overridesAgentProviderFactory, isFalse);
    expect(visitor.constructions[1].overridesAgentProviderFactory, isTrue);
    expect(visitor.constructions.last.overridesAgentProviderFactory, isFalse);
  });
}

/// 一次 `zetaTestApp(...)` 构造及其 Agent 工厂覆盖判定。
final class _MainAppConstruction {
  const _MainAppConstruction({
    required this.offset,
    required this.overridesAgentProviderFactory,
  });

  final int offset;
  final bool overridesAgentProviderFactory;
}

/// 收集所有 `zetaTestApp(...)` 构造点。
///
/// 只做语法解析（不做元素解析）时，省略 `new` 的构造在 AST 里是
/// [MethodInvocation] 而不是 [InstanceCreationExpression]，两种都要看。
/// `_pumpMainApp(...)` 不会被误判：方法名要求完全相等。
/// 两个入口都要扫：`zetaTestApp` 直接建 Widget，`zetaTestComposition` 建组合根，
/// 漏掉后者就能绕过守卫。
const _testAppFactories = <String>{'zetaTestApp', 'zetaTestComposition'};

final class _MainAppConstructionVisitor extends RecursiveAstVisitor<void> {
  final List<_MainAppConstruction> constructions = <_MainAppConstruction>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_testAppFactories.contains(node.constructorName.type.name.lexeme)) {
      _record(node.offset, node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null &&
        _testAppFactories.contains(node.methodName.name)) {
      _record(node.offset, node.argumentList);
    }
    super.visitMethodInvocation(node);
  }

  void _record(int offset, ArgumentList arguments) {
    final overrides = arguments.arguments
        .whereType<NamedExpression>()
        .where((argument) => argument.name.label.name == 'overrides')
        .map((argument) => argument.expression)
        .whereType<ListLiteral>();
    constructions.add(
      _MainAppConstruction(
        offset: offset,
        overridesAgentProviderFactory: overrides.any(
          _hasUnconditionalAgentProviderFactoryOverride,
        ),
      ),
    );
  }
}

/// 覆盖 Agent bundle 工厂的唯一 provider 名。
const _agentProviderFactoryProvider = 'agentProviderBundleFactoryProvider';

/// 只接受列表顶层的直接调用；`if` / `for` / spread 都不能保证运行时一定装入。
bool _hasUnconditionalAgentProviderFactoryOverride(ListLiteral overrides) {
  for (final expression in overrides.elements.whereType<Expression>()) {
    if (expression is! MethodInvocation ||
        expression.methodName.name != 'overrideWithValue') {
      continue;
    }
    final target = expression.target;
    if (target is SimpleIdentifier &&
        target.name == _agentProviderFactoryProvider) {
      return true;
    }
  }
  return false;
}

Iterable<File> _dartFilesUnder(String directory) {
  return Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}

String _posix(String path) => path.replaceAll(r'\', '/');
