import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Feature 内部分层守卫（G6）。
///
/// `AGENTS.md` G6 的依赖方向是 `presentation/application → domain`：presentation
/// 与 application 是**平级**，谁都不该反过来依赖对方。目标架构 §6.2 另把
/// 「Riverpod adapter」单列成一层，因此 Riverpod 类型只允许出现在
/// presentation / app 组合层。
///
/// 这两条以前只写在文档里：仓库有 Package 边界守卫，却没有 feature 内部的分层
/// 守卫，于是 Phase 2 切片一度把五个 region state 从 presentation import 进
/// application，和 `agent_conversation_ui_state.dart → application` 形成闭环，
/// 而 analyze 与全量测试都是绿的。本守卫补上这个缺口。
void main() {
  /// 允许存在的既有反向依赖（**只允许变少**）。
  ///
  /// 这两个 controller 负责构造并持有对应 feature 的 ViewModel，属于拆包前就
  /// 有的组合职责；随 Phase 2/3 把 ViewModel 换成切片后清掉。新增一律不允许。
  const knownApplicationToPresentation = <String>{
    'lib/src/features/agent/application/agent_thread_workspace_controller.dart',
    'lib/src/features/project_threads/application/project_threads_controller.dart',
  };

  /// application 仍 import Flutter 的既有文件（**只允许变少**）。
  ///
  /// 目标架构 §12.5 明确禁止 application import Flutter。这 12 个都是
  /// `ChangeNotifier` 形态的既有 controller，属于拆包前的设计，随 Phase 2/3
  /// 转成 MVI 切片时清掉。新增一律不允许——Phase 2 切片就因为搬家时把
  /// `@immutable` / `setEquals` 一起带进来踩过一次。
  const knownApplicationFlutterImports = <String>{
    'lib/src/features/agent/application/agent_conversation_mode_controller.dart',
    'lib/src/features/agent/application/agent_conversation_model_selection_controller.dart',
    'lib/src/features/agent/application/agent_provider_settings_controller.dart',
    'lib/src/features/agent/application/agent_provider_settings_port.dart',
    'lib/src/features/agent/application/agent_skills_catalog_controller.dart',
    'lib/src/features/agent/application/agent_thread_workspace_controller.dart',
    'lib/src/features/agent_management/application/agent_management_controller.dart',
    'lib/src/features/settings/application/appearance_settings_controller.dart',
    'lib/src/features/settings/application/general_settings_controller.dart',
    'lib/src/features/usage_statistics/application/agent_usage_panel_controller.dart',
    'lib/src/features/usage_statistics/application/usage_statistics_controller.dart',
    'lib/src/features/workspace/application/workspace_file_index_controller.dart',
  };

  /// domain 纯度的既有例外（**只允许变少**）。
  const knownDomainImpurities = <String>{
    'lib/src/features/settings/domain/appearance_settings.dart',
    'lib/src/features/settings/domain/general_settings.dart',
    'lib/src/features/settings/domain/system_font_family.dart',
    'lib/src/features/workspace/domain/workspace_directory_rules.dart',
  };

  final featuresRoot = Directory('lib/src/features');

  List<File> dartFilesInLayer(String layer) {
    if (!featuresRoot.existsSync()) {
      return const <File>[];
    }
    final files = <File>[];
    for (final feature in featuresRoot.listSync().whereType<Directory>()) {
      final layerDir = Directory(
        '${feature.path}${Platform.pathSeparator}$layer',
      );
      if (!layerDir.existsSync()) {
        continue;
      }
      files.addAll(
        layerDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
      );
    }
    return files;
  }

  String normalize(String path) => path.replaceAll(r'\', '/');

  /// 只看 import 指令，注释里提到某一层不算依赖。
  Iterable<String> importsOf(File file) {
    return RegExp(
      r"""^\s*import\s+['"]([^'"]+)['"]""",
      multiLine: true,
    ).allMatches(file.readAsStringSync()).map((match) => match.group(1)!);
  }

  test('application 不得依赖 presentation（G6 单向分层）', () {
    final applicationFiles = dartFilesInLayer('application');
    expect(applicationFiles, isNotEmpty, reason: '扫不到 application 文件说明守卫本身失效了');

    final offenders = <String>[];
    for (final file in applicationFiles) {
      final path = normalize(file.path);
      final dependsOnPresentation = importsOf(
        file,
      ).any((uri) => RegExp(r'features/[a-z_]+/presentation/').hasMatch(uri));
      if (dependsOnPresentation &&
          !knownApplicationToPresentation.contains(path)) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'application 反向依赖 presentation 会和 presentation → application 形成'
          '闭环。UI 状态契约应放在 application，发布机制才留在 presentation：\n'
          '${offenders.join('\n')}',
    );
  });

  test('既有反向依赖清单只允许变少', () {
    final stillViolating = <String>{};
    for (final file in dartFilesInLayer('application')) {
      final path = normalize(file.path);
      if (!knownApplicationToPresentation.contains(path)) {
        continue;
      }
      final dependsOnPresentation = importsOf(
        file,
      ).any((uri) => RegExp(r'features/[a-z_]+/presentation/').hasMatch(uri));
      if (dependsOnPresentation) {
        stillViolating.add(path);
      }
    }

    expect(
      stillViolating.length,
      lessThanOrEqualTo(knownApplicationToPresentation.length),
      reason: '清单只减不增',
    );
    for (final resolved in knownApplicationToPresentation.difference(
      stillViolating,
    )) {
      fail('$resolved 已经不再依赖 presentation，请把它从燃尽清单里删掉');
    }
  });

  test('application 不得 import Flutter（目标架构 §12.5）', () {
    final applicationFiles = dartFilesInLayer('application');
    expect(applicationFiles, isNotEmpty, reason: '扫不到 application 文件说明守卫本身失效了');

    final offenders = <String>[];
    for (final file in applicationFiles) {
      final path = normalize(file.path);
      if (knownApplicationFlutterImports.contains(path)) {
        continue;
      }
      if (importsOf(file).any((uri) => uri.startsWith('package:flutter/'))) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'application 只能用纯 Dart：`@immutable` 走 package:meta，集合相等走 '
          'zeta_foundation 的 zeta*Equals，监听走自己的 listener 列表而不是 '
          'ChangeNotifier：\n${offenders.join('\n')}',
    );
  });

  test('application 的 Flutter 依赖清单只允许变少', () {
    final stillImporting = <String>{};
    for (final file in dartFilesInLayer('application')) {
      final path = normalize(file.path);
      if (!knownApplicationFlutterImports.contains(path)) {
        continue;
      }
      if (importsOf(file).any((uri) => uri.startsWith('package:flutter/'))) {
        stillImporting.add(path);
      }
    }

    for (final resolved in knownApplicationFlutterImports.difference(
      stillImporting,
    )) {
      fail('$resolved 已经不再依赖 Flutter，请把它从燃尽清单里删掉');
    }
  });

  test('Riverpod 只允许出现在 presentation / app 组合层', () {
    final offenders = <String>[];
    for (final layer in const <String>['application', 'data', 'domain']) {
      for (final file in dartFilesInLayer(layer)) {
        if (importsOf(file).any((uri) => uri.contains('riverpod'))) {
          offenders.add(normalize(file.path));
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '目标架构 §6.2 把 Riverpod adapter 单列成一层：Provider / Notifier 只能'
          '住在 presentation 或 app 组合层：\n${offenders.join('\n')}',
    );
  });

  test('domain 保持纯 Dart（无 Flutter / dart:io / Riverpod）', () {
    final domainFiles = dartFilesInLayer('domain');
    expect(domainFiles, isNotEmpty, reason: '扫不到 domain 文件说明守卫本身失效了');

    final offenders = <String>[];
    for (final file in domainFiles) {
      final path = normalize(file.path);
      if (knownDomainImpurities.contains(path)) {
        continue;
      }
      final impure = importsOf(file).any(
        (uri) =>
            uri.startsWith('package:flutter/') ||
            uri == 'dart:io' ||
            uri.contains('riverpod'),
      );
      if (impure) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'domain 必须是纯的（G6）：\n${offenders.join('\n')}',
    );
  });
}
