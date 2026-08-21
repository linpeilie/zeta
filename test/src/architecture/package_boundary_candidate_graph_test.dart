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
  final files =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => _posix(file.path))
          .toList(growable: false)
        ..sort();

  test('候选 Package 覆盖 lib 下全部 Dart 文件', () {
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

  test('zeta_agent_core 候选文件对 Flutter foundation 的依赖不再增长', () {
    final dependents = <String>{};
    for (final path in files) {
      if (_candidatePackageFor(path) != _agentCore) {
        continue;
      }
      final imports = _externalImports(File(path).readAsStringSync());
      if (imports.any((import) => import.startsWith('package:flutter/'))) {
        dependents.add(path);
      }
    }

    // 这些文件用 ChangeNotifier / listEquals 等 foundation 能力；Phase 1 之前
    // 不强制拆除，但数量只允许减少，避免共享内核继续被 Flutter 绑定拖住。
    expect(
      dependents.length,
      lessThanOrEqualTo(_agentCoreFlutterFoundationBaseline),
      reason:
          'zeta_agent_core 候选层新增了 Flutter 依赖：\n'
          '${dependents.join('\n')}',
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

  test('可观测性核心保持纯 Dart 且只被 app 注入', () {
    final metricsFiles = files
        .where((path) => path.startsWith('lib/src/core/observability/'))
        .toList(growable: false);

    expect(metricsFiles, isNotEmpty);
    for (final path in metricsFiles) {
      final imports = _externalImports(File(path).readAsStringSync());
      expect(
        imports,
        isEmpty,
        reason: '$path 是 zeta_foundation 候选文件，不得依赖外部库：$imports',
      );
    }
  });
}

const String _foundation = 'zeta_foundation';
const String _agentCore = 'zeta_agent_core';
const String _agentProviders = 'zeta_agent_providers';
const String _ui = 'zeta_ui';
const String _app = 'app';

const Set<String> _candidatePackages = <String>{
  _foundation,
  _agentCore,
  _agentProviders,
  _ui,
  _app,
};

/// 目标架构 §3.1 的依赖方向；根 app 是唯一可以看到所有 Package 的组合点。
const Map<String, Set<String>> _allowedEdges = <String, Set<String>>{
  _foundation: <String>{_foundation},
  _agentCore: <String>{_agentCore, _foundation},
  _agentProviders: <String>{_agentProviders, _agentCore, _foundation},
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
      _agentCore: <String>[
        'package:flutter/material',
        'package:flutter/widgets',
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

/// Phase 1 的燃尽清单：现存的候选 Package 反向依赖。
const Set<String> _knownEdgeViolations = <String>{
  // ui/core 直接用 generated l10n 扩展；拆包时需要把文案改成注入的 token/labels。
  'lib/src/ui/core/ide_image_preview.dart -> lib/src/ui/localization/app_localizations_x.dart',
  'lib/src/ui/core/ide_tabs.dart -> lib/src/ui/localization/app_localizations_x.dart',
  'lib/src/ui/core/virtualization/ide_virtual_scrollbar.dart -> lib/src/ui/localization/app_localizations_x.dart',
  'lib/src/ui/core/window_frame.dart -> lib/src/ui/localization/app_localizations_x.dart',
  'lib/src/ui/core/workbench/ide_workbench_scaffold.dart -> lib/src/ui/localization/app_localizations_x.dart',
  // application 直接构造 data 层存储/静态能力；拆包时改为 app 注入端口。
  'lib/src/features/agent/application/agent_provider_settings_controller.dart -> lib/src/features/agent/data/agent_provider_static_capabilities.dart',
  'lib/src/features/agent/application/agent_thread_workspace_controller.dart -> lib/src/features/agent/data/agent_turn_context_store.dart',
  'lib/src/features/agent/application/agent_turn_context_recorder.dart -> lib/src/features/agent/data/agent_turn_context_store.dart',
  // Workspace controller 直接持有 presentation ViewModel 与 workspace feature 模型；
  // 目标态由 root app 组合（Phase 2/3 拆解 IdeShellController 时处理）。
  'lib/src/features/agent/application/agent_thread_workspace_controller.dart -> lib/src/features/agent/presentation/agent_conversation_view_model.dart',
  'lib/src/features/agent/application/agent_thread_workspace_controller.dart -> lib/src/features/workspace/domain/workspace_node.dart',
};

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
  // 图片预览直接读本机文件；拆包时改为注入的字节流端口。
  'lib/src/ui/core/ide_image_preview.dart -> dart:io',
};

/// 当前 `zeta_agent_core` 候选层里依赖 `package:flutter/foundation.dart` 的文件数。
const int _agentCoreFlutterFoundationBaseline = 17;

/// 把仓库内路径映射到候选 Package。
///
/// 规则来自目标架构 §3.1 与 §4.1：`ui/core` 是通用 Widget 层，`ui/features`
/// 是业务组合页，属于根 app；Agent 的 domain/application 是中立内核，data 是
/// Provider 适配层。
String _candidatePackageFor(String path) {
  if (path.startsWith('lib/src/core/')) {
    return _foundation;
  }
  if (path.startsWith('lib/src/ui/core/')) {
    return _ui;
  }
  if (path.startsWith('lib/src/features/agent/domain/') ||
      path.startsWith('lib/src/features/agent/application/')) {
    return _agentCore;
  }
  if (path.startsWith('lib/src/features/agent/data/')) {
    return _agentProviders;
  }
  return _app;
}

Iterable<String> _zetaImports(String source) sync* {
  for (final match in _importPattern.allMatches(source)) {
    final uri = match.group(1)!;
    if (uri.startsWith('package:zeta/')) {
      yield 'lib/${uri.substring('package:zeta/'.length)}';
    }
  }
}

Iterable<String> _externalImports(String source) sync* {
  for (final match in _importPattern.allMatches(source)) {
    final uri = match.group(1)!;
    if (!uri.startsWith('package:zeta/') && !uri.startsWith('.')) {
      yield uri;
    }
  }
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

final RegExp _importPattern = RegExp(
  r"""^\s*import\s+['"]([^'"]+)['"]""",
  multiLine: true,
);

String _posix(String path) => path.replaceAll(r'\', '/');
