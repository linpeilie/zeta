import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// 已删除的过渡 API 不得重新出现在生产代码里。
///
/// 这是零容忍守卫：没有 allowlist，也不接受"先加回来再慢慢改"。
/// 每个符号在删除时均已确认没有生产调用者；重新出现说明旧路径被重新接入。
void main() {
  final production = _productionDartFiles();

  test('已删除的过渡符号不得重新出现在 lib/ 与 packages/', () {
    // 注意：这里只能放**唯一归属**于被删路径的名字。
    // `displayTitle` 故意不在名单里——它同时是 AgentToolCallUiText 的活 API，
    // 按名字断言会误伤仍在使用的 API。
    const deleted = <String>[
      // 修订号别名：统一到 contentRevision
      'renderRevision',
      // 设计 token 别名：统一到 textSecondary
      'mutedText',
      // Shell 兼容 getter：统一到 selectedAgentController
      'agentViewModel',
      // usage source id 转发：统一到 usageSourceId
      'codexUsageSourceId',
      // model selection 兼容入口
      'selectServiceTier',
      // 虚拟列表死 flag 与其 fallback helper
      'kIdeUseAnchoredDynamicSliver',
      'buildIdeVirtualSliver',
      // 只有测试用过的 callback store
      'CallbackAgentProviderConfigStore',
      'CallbackAppearanceSettingsStore',
    ];

    for (final symbol in deleted) {
      final pattern = RegExp('\\b$symbol\\b');
      final offenders = <String>[
        for (final file in production)
          if (pattern.hasMatch(file.readAsStringSync())) file.path,
      ];
      expect(offenders, isEmpty, reason: '$symbol 已删除，不得重新引入：$offenders');
    }
  });

  test('lib/src 不得新增过渡 re-export', () {
    // 过渡期曾用 `export` 让下游省掉一条 import，代价是真源被隐藏、
    // 分层边界看不出来。generated l10n 保留；编译期 manifest 只准导出
    // 在插件中声明的身份常量，不放行实现类型或无 show 的整库导出。
    const allowed = 'lib/src/ui/localization/app_localizations_x.dart';

    final offenders = <String>[
      for (final file in production)
        if (file.path.startsWith('lib${Platform.pathSeparator}src') &&
            _normalize(file.path) != allowed &&
            !(_normalize(file.path) == _manifestPath &&
                _onlyProviderIdentityExports(file.readAsStringSync())) &&
            file.readAsLinesSync().any((line) => line.startsWith('export ')))
          _normalize(file.path),
    ];

    expect(offenders, isEmpty, reason: '这些文件新增了过渡 re-export：$offenders');
  });
  test('manifest 再导出拒绝实现类型与整库暴露', () {
    const barrel =
        'package:zeta_agent_provider_codex/zeta_agent_provider_codex.dart';
    expect(
      _onlyProviderIdentityExports(
        "export '$barrel' show defaultAgentProviderId;",
      ),
      isTrue,
    );
    expect(
      _onlyProviderIdentityExports(
        "export '$barrel' show CodexAgentProviderPlugin;",
      ),
      isFalse,
    );
    expect(_onlyProviderIdentityExports("export '$barrel';"), isFalse);
  });
}

List<File> _productionDartFiles() {
  final roots = <Directory>[
    Directory('lib'),
    for (final package in Directory(
      'packages',
    ).listSync().whereType<Directory>())
      Directory('${package.path}${Platform.pathSeparator}lib'),
  ];

  return <File>[
    for (final root in roots)
      if (root.existsSync())
        ...root
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
  ];
}

String _normalize(String path) => path.replaceAll(Platform.pathSeparator, '/');

const _manifestPath = 'lib/src/app/plugins/agent_provider_manifest.dart';

/// manifest 是永久登记边界；它的出口必须仍指向插件声明的身份常量。
bool _onlyProviderIdentityExports(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  if (parsed.errors.isNotEmpty) return false;
  final exports = parsed.unit.directives.whereType<ExportDirective>().toList();
  if (exports.isEmpty) return false;
  for (final directive in exports) {
    final uri = Uri.tryParse(directive.uri.stringValue ?? '');
    if (uri == null ||
        uri.scheme != 'package' ||
        uri.pathSegments.length != 2) {
      return false;
    }
    final package = uri.pathSegments.first;
    if (!RegExp(r'^zeta_agent_provider_[a-z_]+$').hasMatch(package) ||
        uri.pathSegments.last != '$package.dart') {
      return false;
    }
    if (directive.combinators.length != 1 ||
        directive.combinators.single is! ShowCombinator) {
      return false;
    }
    final names = (directive.combinators.single as ShowCombinator).shownNames
        .map((name) => name.name);
    final library = Directory('packages/$package/lib');
    if (!library.existsSync()) return false;
    final constants = <String>{};
    for (final file
        in library
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final unit = parseString(content: file.readAsStringSync()).unit;
      for (final declaration
          in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
        if (!declaration.variables.isConst) continue;
        for (final variable in declaration.variables.variables) {
          constants.add(variable.name.lexeme);
        }
      }
    }
    if (names.any(
      (name) =>
          !RegExp(r'^[a-z]\w*(?:Id|Type|Definition|Config)$').hasMatch(name) ||
          !constants.contains(name),
    )) {
      return false;
    }
  }
  return true;
}
