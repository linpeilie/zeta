import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Feature 内部分层守卫（G6）。
///
/// `AGENTS.md` G6 的依赖方向是 `presentation/application → domain`：presentation
/// 与 application 是**平级**，谁都不该反过来依赖对方。Riverpod 只用
/// `flutter_riverpod` 一个包，允许出现在 application 及以上；`data` 与 `domain`
/// 不持有状态，两层都禁。正文见工程规范 §3.0。
///
/// 这两条以前只写在文档里：仓库有 Package 边界守卫，却没有 feature 内部的分层
/// 守卫，于是 Phase 2 切片一度把五个 region state 从 presentation import 进
/// application，形成闭环，而 analyze 与全量测试都是绿的。本守卫补上这个缺口。
void main() {
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
      if (dependsOnPresentation) {
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

  test('application 不得 import Flutter（G6）', () {
    final applicationFiles = dartFilesInLayer('application');
    expect(applicationFiles, isNotEmpty, reason: '扫不到 application 文件说明守卫本身失效了');

    final offenders = <String>[];
    for (final file in applicationFiles) {
      final path = normalize(file.path);
      if (importsOf(file).any((uri) => uri.startsWith('package:flutter/'))) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'application 只能用纯 Dart：`@immutable` 走 package:meta，集合相等走 '
          'zeta_foundation 的 zeta*Equals，状态发布走 package:riverpod 的 Notifier '
          '而不是 ChangeNotifier：\n${offenders.join('\n')}',
    );
  });

  test('Riverpod 不得出现在 data / domain', () {
    final offenders = <String>[];
    for (final layer in const <String>['data', 'domain']) {
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
          'data 是仓储与 codec、domain 只有不可变模型与端口：两层都由 application '
          '装配，自己不订阅也不发布状态（工程规范 §3.0）：\n${offenders.join('\n')}',
    );
  });

  test('Riverpod 只用 flutter_riverpod 一个 barrel', () {
    // `riverpod` 核心包不是根 pubspec 的直接依赖，只是 flutter_riverpod 的传递
    // 依赖。两个包导出的是同一批声明（flutter_riverpod 直接再导出 riverpod），
    // 因此从核心包 import 不会类型不匹配，但会让「该 import 哪个」变成一次次的
    // 临时判断，而且属于未声明依赖，pub 升级时随时可能断（工程规范 §3.0）。
    final production = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList(growable: false);

    expect(production, isNotEmpty, reason: '扫不到生产文件说明守卫本身失效了');

    final offenders = <String>[
      for (final file in production)
        if (importsOf(file).any((uri) => uri.startsWith('package:riverpod/')))
          normalize(file.path),
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          '改从 package:flutter_riverpod 导入；需要 `Override` 这类只在 misc.dart '
          '里导出的类型时用 `package:flutter_riverpod/misc.dart`：\n'
          '${offenders.join('\n')}',
    );
  });

  test('application/domain 不得依赖具体 Provider package', () {
    final offenders = <String>[];
    for (final layer in const <String>['application', 'domain']) {
      for (final file in dartFilesInLayer(layer)) {
        if (importsOf(file).any(
          (uri) => const <String>['codex', 'grok', 'claude_code'].any(
            (vendor) => uri.startsWith('package:zeta_agent_provider_$vendor/'),
          ),
        )) {
          offenders.add(normalize(file.path));
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Provider identity/私有配置只能由 data 或 app 组合层投影：\n'
          '${offenders.join('\n')}',
    );
  });

  test('agent presentation 不得依赖具体 Provider package', () {
    // WP-7 T3 / WP-1 D1：scheduler 的指标标签必须由组合层注入，presentation
    // 不能再直接 import Provider 插件包，否则无法下沉到 application。
    final presentationFiles = Directory('lib/src/features/agent/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final offenders = <String>[
      for (final file in presentationFiles)
        if (importsOf(file).any(
          (uri) => const <String>['codex', 'grok', 'claude_code'].any(
            (vendor) => uri.startsWith('package:zeta_agent_provider_$vendor/'),
          ),
        ))
          normalize(file.path),
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'agent presentation 的 Provider 身份标签只能由 data/app 组合层注入：\n'
          '${offenders.join('\n')}',
    );
  });

  test('domain 保持纯 Dart（无 Flutter / dart:io / Riverpod）', () {
    final domainFiles = dartFilesInLayer('domain');
    expect(domainFiles, isNotEmpty, reason: '扫不到 domain 文件说明守卫本身失效了');

    final offenders = <String>[];
    for (final file in domainFiles) {
      final path = normalize(file.path);
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
