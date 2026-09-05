import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

const providerManifestPath = 'lib/src/app/plugins/agent_provider_manifest.dart';
const providerSetupGuidePath =
    'lib/src/features/agent_management/presentation/agent_management_page.dart';
const providerApiPackage = 'zeta_agent_provider_api';
const providerSdkPackage = 'zeta_agent_provider_sdk';

/// 包名规则覆盖未来插件；api/sdk 是中立包，不属于厂商集合。
bool isProviderPlugin(String name) =>
    name.startsWith('zeta_agent_provider_') &&
    name != providerApiPackage &&
    name != providerSdkPackage;

/// 只枚举生产/测试源码，不跟随链接或读取工具产物。
Map<String, String> providerAuditSources() => {
  for (final root in ['lib', 'test', 'packages'])
    for (final file in Directory(
      root,
    ).listSync(recursive: true, followLinks: false).whereType<File>())
      if (file.path.endsWith('.dart') &&
          !file.path.contains('/.dart_tool/') &&
          !file.path.contains('/build/'))
        file.path.replaceAll(r'\', '/'): file.readAsStringSync(),
};

String? _packageOf(String path) => path.startsWith('packages/')
    ? path.split('/')[1]
    : path.startsWith('lib/')
    ? 'zeta'
    : null;

String? _targetPackage(String uri, String from) {
  if (uri.startsWith('package:')) return uri.substring(8).split('/').first;
  if (Uri.parse(uri).hasScheme) return null;
  return _packageOf(Uri.parse(from).resolve(uri).path);
}

/// 使用 AST 同时检查 import/export/part 和条件导入，注释不能伪装合规代码。
/// 返回稳定规则名，反例测试和真实仓库扫描共用同一个判定器。
List<String> auditProviderArchitecture(Map<String, String> sources) {
  final issues = <String>[];
  final units = {
    for (final entry in sources.entries)
      entry.key: parseString(
        content: entry.value,
        throwIfDiagnostics: false,
      ).unit,
  };
  final constants = <String, Set<String>>{};
  for (final entry in units.entries) {
    if (!entry.key.contains('/lib/')) continue;
    final owner = _packageOf(entry.key);
    if (owner == null) continue;
    for (final declaration
        in entry.value.declarations.whereType<TopLevelVariableDeclaration>()) {
      if (declaration.variables.isConst) {
        final type = declaration.variables.type?.toSource();
        constants
            .putIfAbsent(owner, () => {})
            .addAll(
              declaration.variables.variables
                  .where(
                    (v) =>
                        const {
                          'AgentProviderTypeId',
                          'AgentProviderDefinition',
                          'AgentProviderConfig',
                        }.contains(type) ||
                        type == 'String' &&
                            v.name.lexeme.endsWith('ProviderId'),
                  )
                  .map((v) => v.name.lexeme),
            );
      }
    }
  }
  var guideHits = 0;
  for (final entry in units.entries) {
    final path = entry.key, unit = entry.value;
    final owner = _packageOf(path);
    final production = path.startsWith('lib/') || path.contains('/lib/');
    final providerPackage =
        owner == providerApiPackage ||
        owner == providerSdkPackage ||
        (owner != null && isProviderPlugin(owner));
    void fail(String rule) => issues.add('$rule: $path');
    for (final directive in unit.directives) {
      final uris = <String>[];
      if (directive is UriBasedDirective && directive.uri.stringValue != null) {
        uris.add(directive.uri.stringValue!);
      }
      if (directive is ImportDirective) {
        uris.addAll(
          directive.configurations.map((c) => c.uri.stringValue!).toList(),
        );
      }
      if (directive is ExportDirective) {
        uris.addAll(
          directive.configurations.map((c) => c.uri.stringValue!).toList(),
        );
      }
      for (final uri in uris) {
        final target = _targetPackage(uri, path);
        if (production && providerPackage) {
          if (target == 'zeta' ||
              target == 'zeta_ui' ||
              target == 'zeta_markdown' ||
              (target != owner && target != null && isProviderPlugin(target)) ||
              (owner == providerApiPackage && target == providerSdkPackage)) {
            fail('package-direction');
          }
          if (uri == 'dart:ui' ||
              target == 'flutter' ||
              target == 'flutter_test' ||
              (target?.contains('riverpod') ?? false) ||
              (owner == providerApiPackage && uri == 'dart:io')) {
            fail('pure-dart');
          }
        }
        if (target != null && isProviderPlugin(target)) {
          if (path.startsWith('lib/') && path != providerManifestPath) {
            fail('manifest-only');
          }
          if (path.startsWith('test/') &&
              !path.startsWith('test/src/testing/')) {
            fail('test-boundary');
          }
        }
        if (production &&
            !path.contains('/src/testing/') &&
            !path.endsWith('_testing.dart') &&
            (uri.endsWith('_testing.dart') || uri.contains('/src/testing/'))) {
          fail('testing-leak');
        }
        if (target != owner &&
            target != null &&
            target.startsWith('zeta_') &&
            uri.contains('/src/')) {
          fail('private-import');
        }
        if (path == providerManifestPath && directive is ExportDirective) {
          if (target == null ||
              !isProviderPlugin(target) ||
              directive.configurations.isNotEmpty ||
              directive.combinators.length != 1 ||
              directive.combinators.single is! ShowCombinator) {
            fail('manifest-export');
          } else {
            final names = (directive.combinators.single as ShowCombinator)
                .shownNames
                .map((n) => n.name);
            if (names.any(
              (name) => !(constants[target]?.contains(name) ?? false),
            )) {
              fail('manifest-export');
            }
          }
        }
      }
    }
    final visitor = _Strings();
    unit.accept(visitor);
    if (production &&
        owner != null &&
        isProviderPlugin(owner) &&
        visitor.invalidMetricLabel) {
      fail('metric-constant');
    }
    if (path.startsWith('lib/') &&
        path != providerManifestPath &&
        visitor.values.any({'codexAppServer', 'acp', 'claudeCode'}.contains)) {
      fail('type-literal');
    }
    if (path.startsWith('lib/src/features/') &&
        path.contains('/presentation/')) {
      final hits = visitor.claudeIdentityLiterals.where((node) {
        // 品牌资源表只映射资产，不参与能力与协议路由。精确到常量表的 key。
        final parent = node.parent;
        final declaration = node.thisOrAncestorOfType<VariableDeclaration>();
        final brandAsset =
            path ==
                'lib/src/features/agent/presentation/widgets/agent_provider_icon.dart' &&
            parent is MapLiteralEntry &&
            identical(parent.key, node) &&
            declaration?.name.lexeme == '_agentProviderIconAssets' &&
            declaration?.parent is VariableDeclarationList &&
            (declaration!.parent as VariableDeclarationList).isConst;
        return !brandAsset;
      }).length;
      guideHits += hits;
      if (hits > 0 &&
          (path != providerSetupGuidePath ||
              hits != 1 ||
              !unit.declarations.whereType<TopLevelVariableDeclaration>().any(
                (d) =>
                    d.variables.isConst &&
                    d.variables.variables.any(
                      (v) =>
                          v.name.lexeme == '_setupGuideAgentId' &&
                          v.initializer is SimpleStringLiteral &&
                          (v.initializer as SimpleStringLiteral).value ==
                              'claude_code',
                    ),
              ))) {
        fail('setup-guide');
      }
    }
    final tokens = <String>[];
    for (var token = unit.beginToken; !token.isEof; token = token.next!) {
      tokens.add(token.lexeme);
    }
    final code = tokens.join(' ');
    if (production &&
        RegExp(
          r'AgentDefinition\s*\.\s*(codex|grok|claudeCode|all|byId)\b',
        ).hasMatch(code)) {
      fail('static-vendor-table');
    }
    final shared =
        (owner == providerSdkPackage &&
            production &&
            !path.contains('/src/testing/') &&
            !path.endsWith('_testing.dart')) ||
        path.startsWith(
          'packages/zeta_agent_core/lib/src/application/reduction/',
        ) ||
        _sharedFiles.contains(path);
    if (shared &&
        RegExp(
          'codex|grok|claude|cursor',
          caseSensitive: false,
        ).hasMatch(code)) {
      fail('shared-purity');
    }
    if ((path.startsWith('lib/src/app/composition/') ||
            path.startsWith('lib/src/app/usage_statistics_slice/')) &&
        (tokens.contains('pluginRegistry') ||
            RegExp(r'\.\s*registry\s*\.\s*contributions').hasMatch(code))) {
      fail('contribution-seam');
    }
  }
  if (guideHits != 1) issues.add('setup-guide-count: $guideHits');
  return issues;
}

final class _Strings extends RecursiveAstVisitor<void> {
  final values = <String>[];
  final claudeIdentityLiterals = <SimpleStringLiteral>[];
  var invalidMetricLabel = false;
  @override
  void visitNamedExpression(NamedExpression node) {
    if (node.name.label.name == 'metricLabel') {
      final call = node.parent?.parent;
      final definition =
          call is InstanceCreationExpression &&
              call.constructorName.type.toSource() ==
                  'AgentProviderDefinition' ||
          call is MethodInvocation &&
              call.methodName.name == 'AgentProviderDefinition';
      if (definition) {
        final value = node.expression;
        final valid =
            value is InstanceCreationExpression &&
                value.constructorName.toSource() ==
                    'ZetaMetricLabel.constant' &&
                value.argumentList.arguments.length == 1 &&
                value.argumentList.arguments.single is SimpleStringLiteral ||
            value is MethodInvocation &&
                value.target?.toSource() == 'ZetaMetricLabel' &&
                value.methodName.name == 'constant' &&
                value.argumentList.arguments.length == 1 &&
                value.argumentList.arguments.single is SimpleStringLiteral;
        if (!valid) invalidMetricLabel = true;
      }
    }
    super.visitNamedExpression(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    values.add(node.value);
    if (node.value == 'claude_code') claudeIdentityLiterals.add(node);
  }
}

const _sharedFiles = {
  'packages/zeta_agent_core/lib/src/application/agent_event_pipeline.dart',
  'packages/zeta_agent_core/lib/src/application/agent_event_coalescing_policy.dart',
  'packages/zeta_agent_core/lib/src/application/coalescing_event_buffer.dart',
  'packages/zeta_agent_core/lib/src/application/bounded_event_dispatcher.dart',
  'packages/zeta_agent_core/lib/src/application/agent_conversation_timeline_store.dart',
};

/// 自动纳入未来插件，防止守卫只覆盖最初三个包。
List<String> providerPluginLibRoots() => [
  for (final dir in Directory(
    'packages',
  ).listSync(followLinks: false).whereType<Directory>())
    if (isProviderPlugin(dir.path.split(Platform.pathSeparator).last))
      '${dir.path.replaceAll(r'\', '/')}/lib',
];
