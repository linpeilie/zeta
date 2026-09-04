import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 内部 Package 依赖图守卫（**零容忍，无 allowlist**）。
///
/// `zeta_foundation` / `zeta_plugin_kernel` / `zeta_agent_core` /
/// `zeta_agent_providers` / `zeta_ui` 与根 app 之间的依赖方向是单向 DAG。
/// 本守卫断言三件事：
///
/// - 依赖方向只能沿 [_allowedEdges]；
/// - 核心纯 Dart 层不得引入 Flutter / Riverpod / `dart:io`；
///   `zeta_foundation/src/platform` 只允许宿主平台适配器依赖对应插件；
/// - 依赖图无环。
///
/// 曾经的燃尽清单（`_knownEdgeViolations` / `_knownExternalViolations`）在
/// Phase 4 P4-6 删除——它们早已为空，留着只会给"先违规再登记"开口子。
void main() {
  final files = <String>[
    ..._dartFilesUnder('lib'),
    // 已经物理拆出的 Package 也纳入同一张依赖图，
    // 保证"已拆"和"待拆"用同一套规则。
    ..._dartFilesUnder('packages'),
  ]..sort();

  test('候选 Package 覆盖 lib 与 packages 下全部 Dart 文件', () {
    expect(files, isNotEmpty);
    for (final path in files) {
      expect(
        _candidatePackages.contains(_candidatePackageFor(path)),
        isTrue,
        reason: '$path 没有落到任何候选 Package',
      );
    }
  });

  test('候选 Package 之间只允许正向依赖', () {
    final violations = <String>{};
    for (final path in files) {
      final source = _candidatePackageFor(path);
      for (final import in _zetaImports(File(path).readAsStringSync())) {
        final target = _candidatePackageFor(import);
        if (_allowedEdges[source]!.contains(target)) {
          continue;
        }
        violations.add('$path -> $import');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '内部 Package 出现反向/越级依赖，必须改依赖方向（不接受登记豁免）：'
          '\n${violations.join('\n')}',
    );
  });

  test('候选 Package 的外部依赖符合平台约束', () {
    final violations = <String>{};
    for (final path in files) {
      final source = _candidatePackageFor(path);
      final banned = _bannedExternalPrefixes[source];
      if (banned == null) {
        continue;
      }
      for (final import in _externalImports(File(path).readAsStringSync())) {
        for (final prefix in banned) {
          if (import.startsWith(prefix)) {
            violations.add('$path -> $prefix');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '内部 Package 引入了不允许的外部依赖（纯 Dart 层不得依赖 Flutter/Riverpod/dart:io）：'
          '\n${violations.join('\n')}',
    );
  });

  test('内部 Package 的 manifest 依赖与 DAG 精确一致', () {
    for (final entry in _manifestInternalDependencies.entries) {
      final manifest = File('packages/${entry.key}/pubspec.yaml');
      expect(
        manifest.existsSync(),
        isTrue,
        reason: '扫不到 ${entry.key} 的 pubspec.yaml，守卫本身失效了',
      );

      final lines = manifest.readAsLinesSync();
      final declared = <String>{};
      var inDependencies = false;
      for (final line in lines) {
        if (line.startsWith('dependencies:')) {
          inDependencies = true;
          continue;
        }
        if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
          inDependencies = false;
        }
        if (!inDependencies) {
          continue;
        }
        final match = RegExp(r'^  (zeta_[a-z_]+):').firstMatch(line);
        if (match != null) {
          declared.add(match.group(1)!);
        }
      }

      expect(
        declared,
        equals(entry.value),
        reason:
            '${entry.key} 的 manifest 内部依赖与允许的 DAG 不一致。'
            'manifest 多出的依赖迟早会变成代码里的越界 import。',
      );
    }
  });

  test('内部 Package 依赖图无环', () {
    final edges = <String, Set<String>>{
      for (final package in _candidatePackages) package: <String>{},
    };
    for (final path in files) {
      final source = _candidatePackageFor(path);
      for (final import in _zetaImports(File(path).readAsStringSync())) {
        final target = _candidatePackageFor(import);
        if (source == target) {
          continue;
        }
        edges[source]!.add(target);
      }
    }

    expect(_findCycle(edges), isNull, reason: '候选 Package 之间出现循环依赖');
  });

  test('已拆出的 Package 之间只 import 顶层 barrel', () {
    final offenders = <String>[];
    for (final path in files) {
      final owner = _candidatePackageFor(path);
      final source = File(path).readAsStringSync();
      for (final match in _importPattern.allMatches(source)) {
        final uri = match.group(1)!;
        for (final package in _materializedPackages) {
          if (package == owner) {
            continue; // 包内允许引用自己的 src。
          }
          if (uri.startsWith('package:$package/src/')) {
            offenders.add('$path -> $uri');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '跨 Package 只能 import 对方的顶层 barrel：\n${offenders.join('\n')}',
    );
  });

  test('zeta_foundation 的核心契约保持平台中立', () {
    final foundationFiles = files
        .where((path) => path.startsWith('packages/zeta_foundation/lib/'))
        .toList(growable: false);

    expect(foundationFiles, isNotEmpty);
    for (final path in foundationFiles) {
      final imports = _externalImports(File(path).readAsStringSync());
      final offenders = imports
          .where(
            (import) =>
                !_platformNeutralCoreLibraries.contains(import) &&
                !(path.endsWith('/src/platform/user_directory.dart') &&
                    import.startsWith('package:path_provider/')) &&
                !(path.endsWith('/src/platform/system_language.dart') &&
                    import == 'dart:ui'),
          )
          .toList(growable: false);
      expect(
        offenders,
        isEmpty,
        reason:
            '$path 属于 zeta_foundation：核心契约只能依赖平台中立库；'
            '宿主工具只能依赖对应的平台库，命中 $offenders',
      );
    }
  });

  test('zeta_ui 不认识业务，也不碰本机 IO', () {
    final uiFiles = files
        .where((path) => path.startsWith('packages/zeta_ui/lib/'))
        .toList(growable: false);

    expect(uiFiles, isNotEmpty);
    for (final path in uiFiles) {
      final source = File(path).readAsStringSync();
      final imports = _externalImports(source).toList(growable: false);
      for (final banned in const <String>[
        'dart:io',
        'package:flutter_riverpod/',
      ]) {
        expect(
          imports.any((import) => import.startsWith(banned)),
          isFalse,
          reason: '$path 引入了 $banned；设计系统必须与宿主 IO / 状态管理解耦',
        );
      }
      expect(
        source.contains('package:zeta/'),
        isFalse,
        reason: '$path 反向依赖了根 app',
      );
      expect(
        source.contains('app_localizations'),
        isFalse,
        reason: '$path 直接用了 generated l10n；控件文案必须走 ZetaUiTextCatalog',
      );
    }
  });

  test('zeta_ui 不硬编码用户可见文案', () {
    final offenders = <String>[];
    for (final path in files.where(
      (path) => path.startsWith('packages/zeta_ui/lib/'),
    )) {
      final source = File(path).readAsStringSync();
      for (final match in _literalCopyPattern.allMatches(source)) {
        final line = source.substring(0, match.start).split('\n').length;
        offenders.add('$path:$line ${match.group(0)}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '控件自有文案必须走注入的 ZetaUiTextCatalog，否则中文界面下读屏仍是英文：'
          '\n${offenders.join('\n')}',
    );
  });

  test('设计系统已整体移出 lib/src/ui/core', () {
    final remaining = files
        .where((path) => path.startsWith('lib/src/ui/core/'))
        .toList(growable: false);

    // 只允许留下确实需要宿主能力（本机 IO / 拉起系统程序）的封装。
    expect(remaining, const <String>[
      'lib/src/ui/core/ide_image_preview.dart',
      'lib/src/ui/core/system_file_manager.dart',
      'lib/src/ui/core/system_url_opener.dart',
    ]);
  });

  test('zeta_agent_core 不反向依赖根 app，也不碰本机 IO', () {
    final coreFiles = files
        .where((path) => path.startsWith('packages/zeta_agent_core/lib/'))
        .toList(growable: false);

    expect(coreFiles, isNotEmpty);
    for (final path in coreFiles) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('package:zeta/'),
        isFalse,
        reason: '$path 反向依赖了根 app',
      );
      expect(
        _externalImports(source).any((import) => import.startsWith('dart:io')),
        isFalse,
        reason: '$path 引入了 dart:io；中立内核不碰本机 IO',
      );
    }
    // Provider 协议与身份分支的纯度由 G1 守卫单独管（五文件 + ACP mapper），
    // 见 claude_code_shared_layer_purity_test；内核 domain 里的
    // `AgentProviderTypeId` / 默认配置常量是既有中立设计，不在此列。
  });

  test('zeta_agent_core 不得依赖 Flutter', () {
    final dependents = files
        .where((path) => path.startsWith('packages/zeta_agent_core/lib/'))
        .where(
          (path) => _externalImports(
            File(path).readAsStringSync(),
          ).any((import) => import.startsWith('package:flutter/')),
        )
        .toList(growable: false);

    expect(
      dependents,
      isEmpty,
      reason: 'zeta_agent_core 必须保持纯 Dart：\n${dependents.join('\n')}',
    );

    final pubspec = File(
      'packages/zeta_agent_core/pubspec.yaml',
    ).readAsStringSync();
    expect(
      RegExp(
        r'^\s*(?:flutter|flutter_test):\s*$',
        multiLine: true,
      ).hasMatch(pubspec),
      isFalse,
      reason: 'zeta_agent_core pubspec 不得声明 Flutter SDK/flutter_test 依赖',
    );
  });

  test('zeta_agent_providers 不反向依赖根 app 与 UI', () {
    final providerFiles = files
        .where((path) => path.startsWith('packages/zeta_agent_providers/lib/'))
        .toList(growable: false);

    expect(providerFiles, isNotEmpty);
    for (final path in providerFiles) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('package:zeta/'),
        isFalse,
        reason: '$path 反向依赖了根 app',
      );
      for (final banned in const <String>[
        'package:zeta_ui/',
        'package:flutter_riverpod/',
        'package:flutter/material',
        'package:flutter/widgets',
      ]) {
        expect(
          _externalImports(source).any((import) => import.startsWith(banned)),
          isFalse,
          reason: '$path 引入了 $banned；适配层不认识 UI 与状态管理',
        );
      }
    }
  });

  test('Provider 协议原文只出现在 zeta_agent_providers 里', () {
    // wire 层标识（JSON-RPC method、ACP session/update、stream-json 事件名）
    // 一旦出现在内核或 app，就说明协议细节又漏出了适配层。
    // 只列 **wire 标识**：`stream-json` 之类的协议名会出现在管理页文案与 ARB 里，
    // 那是产品文案不是协议使用，不能当泄漏证据。
    const protocolTokens = <String>['jsonrpc', 'session/update'];
    final offenders = <String>[];
    for (final path in files) {
      if (path.startsWith('packages/zeta_agent_providers/')) {
        continue;
      }
      if (path.startsWith('test/')) {
        continue;
      }
      final source = File(path).readAsStringSync();
      final codeOnly = source
          .split('\n')
          .where((line) {
            final trimmed = line.trimLeft();
            return !trimmed.startsWith('//') && !trimmed.startsWith('///');
          })
          .join('\n');
      for (final token in protocolTokens) {
        if (codeOnly.contains(token)) {
          offenders.add('$path: $token');
        }
      }
    }

    expect(offenders, isEmpty, reason: '协议原文泄漏：\n${offenders.join('\n')}');
  });

  test('zeta_plugin_kernel 不认识任何具体插件或 Provider', () {
    final kernelFiles = files
        .where((path) => path.startsWith('packages/zeta_plugin_kernel/lib/'))
        .toList(growable: false);

    expect(kernelFiles, isNotEmpty);
    for (final path in kernelFiles) {
      final source = File(path).readAsStringSync();
      final codeOnly = source
          .split('\n')
          .where((line) {
            final trimmed = line.trimLeft();
            return !trimmed.startsWith('//') && !trimmed.startsWith('///');
          })
          .join('\n');
      for (final token in const <String>[
        'codex',
        'grok',
        'claude',
        'Agent',
        'package:zeta/',
      ]) {
        expect(
          codeOnly.contains(token),
          isFalse,
          reason: '$path 出现了具体插件/Provider 标识：$token',
        );
      }
    }
  });
}

const String _foundation = 'zeta_foundation';
const String _pluginKernel = 'zeta_plugin_kernel';
const String _agentCore = 'zeta_agent_core';
const String _agentProviders = 'zeta_agent_providers';
const String _ui = 'zeta_ui';
const String _app = 'app';

const Set<String> _candidatePackages = <String>{
  _foundation,
  _pluginKernel,
  _agentCore,
  _agentProviders,
  _ui,
  _app,
};

/// 已经物理拆出的 Package（`packages/<name>`）。
///
/// 这些名字既是目录名，也是 `package:` scheme 名；跨 Package 只能 import 对方
/// 的顶层 barrel，禁止 `package:<name>/src/...`。
const Set<String> _materializedPackages = <String>{
  _foundation,
  _pluginKernel,
  _ui,
  _agentCore,
  _agentProviders,
};

/// 目标架构 §3.1 的依赖方向；根 app 是唯一可以看到所有 Package 的组合点。
const Map<String, Set<String>> _allowedEdges = <String, Set<String>>{
  _foundation: <String>{_foundation},
  _pluginKernel: <String>{_pluginKernel, _foundation},
  _agentCore: <String>{_agentCore, _foundation},
  _agentProviders: <String>{
    _agentProviders,
    _agentCore,
    _pluginKernel,
    _foundation,
  },
  _ui: <String>{_ui, _foundation},
  _app: _candidatePackages,
};

/// 纯 Dart 候选层禁止的外部依赖前缀。
const Map<String, List<String>> _bannedExternalPrefixes =
    <String, List<String>>{
      _foundation: <String>[
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:shadcn_flutter/',
        'dart:io',
      ],
      _pluginKernel: <String>[
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:shadcn_flutter/',
        'dart:io',
      ],
      _agentCore: <String>[
        'package:flutter/material',
        'package:flutter/widgets',
        'package:flutter/services',
        'package:flutter_riverpod/',
        'package:shadcn_flutter/',
        'dart:io',
      ],
      _agentProviders: <String>[
        'package:flutter/material',
        'package:flutter/widgets',
        'package:flutter_riverpod/',
        'package:shadcn_flutter/',
      ],
      _ui: <String>['package:flutter_riverpod/', 'dart:io'],
    };

/// 纯 Dart Package 允许使用的核心库。
///
/// "纯 Dart"指的是**能在任何宿主上跑**，不是"零 import"：`dart:math` /
/// `dart:convert` 这类库在 VM、Web、Flutter 上都存在。`dart:io` 与 `dart:ui`
/// 不在此列——它们把 Package 钉死在特定宿主上。
const Set<String> _platformNeutralCoreLibraries = <String>{
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:math',
  'dart:typed_data',
};

/// Phase 1 的燃尽清单：现存的外部依赖越界。
///

/// 把仓库内路径映射到候选 Package。
///
/// 规则来自目标架构 §3.1 与 §4.1：`ui/core` 是通用 Widget 层，`ui/features`
/// 是业务组合页，属于根 app；Agent 的 domain/application 是中立内核，data 是
/// Provider 适配层。
String _candidatePackageFor(String path) {
  for (final package in _materializedPackages) {
    if (path.startsWith('packages/$package/')) {
      return package;
    }
  }
  if (path.startsWith('lib/src/core/')) {
    return _foundation;
  }
  return _app;
}

/// 把仓库内 import 归一成"仓库相对路径"，便于统一判定所属 Package。
Iterable<String> _zetaImports(String source) sync* {
  for (final match in _importPattern.allMatches(source)) {
    final uri = match.group(1)!;
    if (uri.startsWith('package:zeta/')) {
      yield 'lib/${uri.substring('package:zeta/'.length)}';
      continue;
    }
    for (final package in _materializedPackages) {
      if (uri.startsWith('package:$package/')) {
        yield 'packages/$package/lib/'
            '${uri.substring('package:$package/'.length)}';
        break;
      }
    }
  }
}

Iterable<String> _externalImports(String source) sync* {
  for (final match in _importPattern.allMatches(source)) {
    final uri = match.group(1)!;
    if (uri.startsWith('.')) {
      continue;
    }
    if (uri.startsWith('package:zeta/')) {
      continue;
    }
    if (_materializedPackages.any(
      (package) => uri.startsWith('package:$package/'),
    )) {
      continue;
    }
    yield uri;
  }
}

List<String> _dartFilesUnder(String directory) {
  final root = Directory(directory);
  if (!root.existsSync()) {
    return const <String>[];
  }
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => _posix(file.path))
      .where(
        (path) =>
            path.endsWith('.dart') &&
            !path.contains('/.dart_tool/') &&
            !path.contains('/build/'),
      )
      .toList(growable: false);
}

String? _findCycle(Map<String, Set<String>> edges) {
  final visiting = <String>{};
  final visited = <String>{};

  String? visit(String node, List<String> stack) {
    if (visiting.contains(node)) {
      return <String>[...stack, node].join(' -> ');
    }
    if (!visited.add(node)) {
      return null;
    }
    visiting.add(node);
    for (final next in edges[node] ?? const <String>{}) {
      final cycle = visit(next, <String>[...stack, node]);
      if (cycle != null) {
        return cycle;
      }
    }
    visiting.remove(node);
    return null;
  }

  for (final node in edges.keys) {
    final cycle = visit(node, <String>[]);
    if (cycle != null) {
      return cycle;
    }
  }
  return null;
}

/// 直接写死在 tooltip / 无障碍标签上的字面量文案。
///
/// `ValueKey('...')` 之类的标识符不在此列——只匹配会被用户读到的参数名。
final RegExp _literalCopyPattern = RegExp(
  r"(?:tooltip|semanticLabel|semanticsLabel|message)\s*:\s*'[^']+'",
);

final RegExp _importPattern = RegExp(
  r"""^\s*import\s+['"]([^'"]+)['"]""",
  multiLine: true,
);

String _posix(String path) => path.replaceAll(r'\', '/');

/// 各内部 Package 的 `pubspec.yaml` 里**允许出现的 zeta 内部依赖**（精确匹配）。
///
/// manifest 与代码依赖必须一致：代码里改对了方向、manifest 却还留着旧依赖，
/// 下一次有人 import 就会"合法地"违反 DAG。
const Map<String, Set<String>> _manifestInternalDependencies =
    <String, Set<String>>{
      'zeta_foundation': <String>{},
      'zeta_plugin_kernel': <String>{'zeta_foundation'},
      'zeta_agent_core': <String>{'zeta_foundation'},
      'zeta_agent_providers': <String>{
        'zeta_agent_core',
        'zeta_foundation',
        'zeta_plugin_kernel',
      },
      'zeta_ui': <String>{'zeta_foundation'},
    };
