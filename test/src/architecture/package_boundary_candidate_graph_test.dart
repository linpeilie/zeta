import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 阶段 0：Package 候选依赖图守卫。
///
/// 目标架构会把当前单一 Flutter Package 拆成
/// `zeta_foundation` / `zeta_plugin_kernel` / `zeta_agent_core` /
/// `zeta_agent_providers` / `zeta_ui` 加根 app。阶段 0 **不移动任何文件**，
/// 只把「文件属于哪个候选 Package」和「允许的依赖方向」写成可执行断言：
///
/// - 现有越界依赖冻结在 [_knownEdgeViolations] / [_knownExternalViolations]；
/// - 新增越界会直接失败；
/// - 修好一条就必须从清单里删掉一条（清单不允许有过期条目）。
///
/// 这样 Phase 1 的物理拆包有一份可燃尽的清单，而不是搬完文件才发现循环依赖。
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

    final unexpected = violations.difference(_knownEdgeViolations);
    expect(
      unexpected,
      isEmpty,
      reason:
          '新增了候选 Package 反向/越级依赖。要么改依赖方向，'
          '要么在架构评审后显式登记：\n${unexpected.join('\n')}',
    );

    final stale = _knownEdgeViolations.difference(violations);
    expect(
      stale,
      isEmpty,
      reason: '这些越界依赖已经消失，请从 _knownEdgeViolations 中删除：\n${stale.join('\n')}',
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

    final unexpected = violations.difference(_knownExternalViolations);
    expect(
      unexpected,
      isEmpty,
      reason:
          '候选 Package 引入了不允许的外部依赖（纯 Dart 层不得依赖 Flutter/Riverpod/dart:io）：'
          '\n${unexpected.join('\n')}',
    );

    final stale = _knownExternalViolations.difference(violations);
    expect(
      stale,
      isEmpty,
      reason:
          '这些外部依赖越界已经消失，请从 _knownExternalViolations 中删除：'
          '\n${stale.join('\n')}',
    );
  });

  test('候选依赖图（已知违规除外）无环', () {
    final edges = <String, Set<String>>{
      for (final package in _candidatePackages) package: <String>{},
    };
    for (final path in files) {
      final source = _candidatePackageFor(path);
      for (final import in _zetaImports(File(path).readAsStringSync())) {
        final target = _candidatePackageFor(import);
        if (source == target ||
            _knownEdgeViolations.contains('$path -> $import')) {
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

  test('zeta_foundation 保持纯 Dart', () {
    final foundationFiles = files
        .where((path) => path.startsWith('packages/zeta_foundation/lib/'))
        .toList(growable: false);

    expect(foundationFiles, isNotEmpty);
    for (final path in foundationFiles) {
      final imports = _externalImports(File(path).readAsStringSync());
      final offenders = imports
          .where((import) => !_platformNeutralCoreLibraries.contains(import))
          .toList(growable: false);
      expect(
        offenders,
        isEmpty,
        reason:
            '$path 属于 zeta_foundation：除平台中立的核心库外不得依赖任何外部库，'
            '命中 $offenders',
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

    // 只允许留下确实需要宿主能力（本机文件读取 + generated l10n）的封装。
    expect(remaining, <String>['lib/src/ui/core/ide_image_preview.dart']);
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
    // `AgentProviderKind` / 默认配置常量是既有中立设计，不在此列。
  });

  test('zeta_agent_core 对 Flutter 的依赖只允许收缩', () {
    final dependents = files
        .where((path) => path.startsWith('packages/zeta_agent_core/lib/'))
        .where(
          (path) => _externalImports(
            File(path).readAsStringSync(),
          ).any((import) => import.startsWith('package:flutter/')),
        )
        .toList(growable: false);

    // 这些文件用 ChangeNotifier / ValueListenable；目标态要求纯 Dart，但去掉它们
    // 需要把 10 个 controller 换成 MVI store（Phase 2/3），且会触碰 G1 冻结文件。
    // 阶段 1 只冻结数量：只能变少。
    expect(
      dependents.length,
      lessThanOrEqualTo(_agentCoreFlutterBaseline),
      reason: 'zeta_agent_core 新增了 Flutter 依赖：\n${dependents.join('\n')}',
    );
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

/// Phase 1 的燃尽清单：现存的候选 Package 反向依赖。
const Set<String> _knownEdgeViolations = <String>{};

/// Phase 1 的燃尽清单：现存的外部依赖越界。
const Set<String> _knownExternalViolations = <String>{
  // core/ 目前同时承担纯契约与本机 IO；拆包时 IO 部分应下沉到 app 或独立适配层。
  'lib/src/core/logging/app_logging.dart -> package:flutter/',
  'lib/src/core/logging/app_logging.dart -> dart:io',
  'lib/src/core/security/sensitive_data_redactor.dart -> dart:io',
  'lib/src/core/storage/atomic_text_file.dart -> dart:io',
  'lib/src/core/storage/zeta_data_paths.dart -> dart:io',
  'lib/src/core/utils/path_utils.dart -> dart:io',
  'lib/src/core/utils/system_file_manager.dart -> dart:io',
};

/// 当前 `zeta_agent_core` 里依赖 `package:flutter/foundation.dart` 的文件数。
const int _agentCoreFlutterBaseline = 17;

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
  if (path.startsWith('lib/src/features/agent/data/')) {
    return _agentProviders;
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
      .where((file) => file.path.endsWith('.dart'))
      .map((file) => _posix(file.path))
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
