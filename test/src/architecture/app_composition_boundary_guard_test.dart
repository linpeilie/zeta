import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `MainApp` 的组合边界守卫。
///
/// `MainApp` 只负责 Flutter / 窗口生命周期与组合输入；**具体 feature data 用文件还是
/// 内存**由 `ZetaApplicationComposition` 按 `ZetaHostMode` 决定。这条边界一旦破了，
/// "哪个 store 落盘"的决策就会重新散回 Widget，也会再次出现"从有没有传回调反推
/// 测试模式"那种隐式耦合。
void main() {
  final appSource = File('lib/src/app/app.dart').readAsStringSync();

  test('MainApp 不直接构造 feature data store', () {
    // 允许出现类型名（字段与参数类型），但不允许出现构造调用。
    const forbiddenConstructions = <String>[
      'FileIdeSessionStore(',
      'MemoryIdeSessionStore(',
      'FileUsageStatisticsPartitionStore(',
      'MemoryUsageStatisticsPartitionStore(',
      'FileAgentModelCatalogCacheStore(',
      'MemoryAgentModelCatalogCacheStore(',
      'FileAgentTurnContextStore(',
      'MemoryAgentTurnContextStore(',
      'FileAgentProviderConfigStore(',
      'MemoryAgentProviderConfigStore(',
      'FileClaudeCodeSessionDecisionStore(',
      'FileClaudeCodeHiddenThreadStore(',
      'AgentModelCatalogRepository(',
    ];

    final offenders = <String>[
      for (final construction in forbiddenConstructions)
        if (appSource.contains(construction)) construction,
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'lib/src/app/app.dart 直接构造了 feature data：$offenders\n'
          '请改由 ZetaApplicationComposition 按 ZetaHostMode 组装。',
    );
  });

  test('宿主模式不得退回成从 session 回调反推', () {
    // 旧实现用 sessionLoader/sessionSaver 是否为 null 推断"这是不是测试宿主"，
    // 一处推断同时控制持久化、本机 CLI 探测与用量刷新三件事。
    const forbidden = <String>[
      'sessionLoader',
      'sessionSaver',
      'CallbackIdeSessionStore',
      '_usesCallbackPersistence',
    ];

    final production = <File>[
      ...Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];

    for (final symbol in forbidden) {
      final offenders = <String>[
        for (final file in production)
          if (_codeOf(file).contains(symbol)) file.path,
      ];
      expect(
        offenders,
        isEmpty,
        reason: '$symbol 已被显式 ZetaHostMode 取代，不得重新引入：$offenders',
      );
    }
  });
}

/// 去掉注释行后的源码。
///
/// 文档注释里提到已废弃的名字是**允许的**——解释"以前为什么这么写、现在为什么不"
/// 恰恰是有价值的；守卫只该拦真正的代码引用。
String _codeOf(File file) {
  return file
      .readAsLinesSync()
      .where((line) {
        final trimmed = line.trimLeft();
        return !trimmed.startsWith('///') &&
            !trimmed.startsWith('//') &&
            !trimmed.startsWith('*');
      })
      .join('\n');
}
