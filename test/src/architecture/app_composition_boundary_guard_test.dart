import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `MainApp` / `IdeHome` 的组合边界守卫。
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

  test('lib/src/ui 不得 import 或构造 feature data', () {
    // UI 层直接 new Repository 会把工作台钉死在具体 Provider 的 data 实现上（G6）。
    // 装配决策属于 app 层的 IdeWorkbenchComposition。
    final uiFiles = Directory('lib/src/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    final dataImports = <String>[];
    final repositoryConstructions = <String>[];
    for (final file in uiFiles) {
      for (final line in _codeLinesOf(file)) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('import ') &&
            RegExp(r'features/[^/]+/data/').hasMatch(trimmed)) {
          dataImports.add('${file.path}: $trimmed');
        }
        // 与验收用的 grep 同一口径（朴素子串），避免守卫和验收检查各说各话。
        if (line.contains('Repository(')) {
          repositoryConstructions.add('${file.path}: ${line.trim()}');
        }
      }
    }

    expect(
      dataImports,
      isEmpty,
      reason: 'lib/src/ui 不得 import feature data：$dataImports',
    );
    expect(
      repositoryConstructions,
      isEmpty,
      reason: 'lib/src/ui 不得构造 Repository：$repositoryConstructions',
    );
  });

  test('presentation 与 UI 层不得触达 Repository', () {
    // 异步 IO 只经 typed operation/effect runner；Repository 只在
    // composition / runner / data 出现。
    final presentationFiles = <File>[
      for (final feature in Directory(
        'lib/src/features',
      ).listSync().whereType<Directory>())
        ...(() {
          final dir = Directory(
            '${feature.path}${Platform.pathSeparator}presentation',
          );
          return dir.existsSync()
              ? dir.listSync(recursive: true).whereType<File>()
              : const <File>[];
        })(),
      ...Directory('lib/src/ui').listSync(recursive: true).whereType<File>(),
    ].where((file) => file.path.endsWith('.dart')).toList();

    final offenders = <String>[
      for (final file in presentationFiles)
        for (final line in _codeLinesOf(file))
          if (line.contains('Repository')) '${file.path}: ${line.trim()}',
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'presentation / UI 不得引用 Repository：$offenders',
    );
  });

  test('已收口的 callback seam 不得在生产代码里复活', () {
    // 旧实现用 sessionLoader/sessionSaver 是否为 null 推断"这是不是测试宿主"，
    // 一处推断同时控制持久化、本机 CLI 探测与用量刷新三件事。
    const forbidden = <String>[
      'sessionLoader',
      'sessionSaver',
      'CallbackIdeSessionStore',
      '_usesCallbackPersistence',
      // Shell 曾用四个闭包拼 @mention 语料端口，等于把 Workspace 的索引就绪语义
      // 和目录树回退规则搬进了 Shell。现在由 WorkspaceSliceFileCorpus 自己组装。
      'CallbackWorkspaceFileCorpusPort',
      // Project Threads 曾是 controller → adapter → store 三层一比一转发；
      // 业务副作用现在直接在 ProjectThreadsSliceRunner 里执行。
      'ProjectThreadsController',
      'ProjectThreadsSliceRunnerAdapter',
      // Conversation 切片组合现在只依赖 region / command 两个窄端口，
      // 不再持有整个 ViewModel。
      'AgentConversationSliceBinding',
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
        reason: '$symbol 是已经收口的 callback seam，生产代码不得重新引入：$offenders',
      );
    }
  });
}

/// 去掉注释行后的源码。
///
/// 文档注释里提到已废弃的名字是**允许的**——解释"以前为什么这么写、现在为什么不"
/// 恰恰是有价值的；守卫只该拦真正的代码引用。
String _codeOf(File file) => _codeLinesOf(file).join('\n');

/// 去掉注释行后的源码行。
List<String> _codeLinesOf(File file) {
  return file.readAsLinesSync().where((line) {
    final trimmed = line.trimLeft();
    return !trimmed.startsWith('///') &&
        !trimmed.startsWith('//') &&
        !trimmed.startsWith('*');
  }).toList();
}
