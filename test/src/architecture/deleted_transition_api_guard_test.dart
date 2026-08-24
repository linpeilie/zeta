import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 已删除的过渡 API 不得重新出现在生产代码里。
///
/// 这是零容忍守卫：没有 allowlist，也不接受"先加回来再慢慢改"。
/// 每个符号在删除时都已确认生产调用者为 0（见
/// `.workflow/refactor/2026-08-24-phase4-transition-cleanup/02-现状测绘.md`），
/// 重新出现只可能是有人又把旧路径接了回去。
void main() {
  final production = _productionDartFiles();

  test('已删除的过渡符号不得重新出现在 lib/ 与 packages/', () {
    // 注意：这里只能放**唯一归属**于被删路径的名字。
    // `displayTitle` 故意不在名单里——它同时是 AgentToolCallUiText 的活 API，
    // 按名字断言会误伤（见 02-现状测绘.md §1.1）。
    const deleted = <String>[
      // 修订号别名：统一到 contentRevision
      'renderRevision',
      // 设计 token 别名：统一到 textSecondary
      'mutedText',
      // Shell 兼容 getter：统一到 selectedAgentViewModel
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
    // 分层边界看不出来。当前只保留 generated l10n 这一条。
    const allowed = 'lib/src/ui/localization/app_localizations_x.dart';

    final offenders = <String>[
      for (final file in production)
        if (file.path.startsWith('lib${Platform.pathSeparator}src') &&
            _normalize(file.path) != allowed &&
            file.readAsLinesSync().any((line) => line.startsWith('export ')))
          _normalize(file.path),
    ];

    expect(offenders, isEmpty, reason: '这些文件新增了过渡 re-export：$offenders');
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
