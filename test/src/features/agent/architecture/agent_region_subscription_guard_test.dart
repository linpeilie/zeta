import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// region 订阅必须经 `AgentRegionBuilder`（Phase 2 E 步）。
///
/// 直接订阅 `viewModel.<region>StateListenable` 会绕过唯一 Slice owner，形成
/// 第二条渲染路径，因此用守卫钉住。
void main() {
  const paneRoot = 'lib/src/features/agent/presentation';
  const regionListenables = <String>[
    'headerStateListenable',
    'composerStateListenable',
    'pendingInteractionStateListenable',
    'expansionStateListenable',
    'historyStateListenable',
  ];

  const seamPath = '$paneRoot/conversation_slice/agent_region_builder.dart';

  /// 另外两处按职责豁免：
  /// - ViewModel 是这些 listenable 的**定义方**；
  /// - 切片 binding 订阅它们是 **ingress**——切片正是靠这条线拿到 region 更新的。
  const allowedPaths = <String>{
    '$paneRoot/agent_conversation_view_model.dart',
    '$paneRoot/conversation_slice/agent_conversation_slice_binding.dart',
  };

  test('presentation 只经 AgentRegionBuilder 订阅 region', () {
    final files = Directory(paneRoot)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => !allowedPaths.contains(file.path.replaceAll(r'\', '/')),
        );
    expect(files, isNotEmpty, reason: '扫不到 presentation 文件，守卫失效了');

    final offenders = <String>[];
    for (final file in files) {
      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i];
        if (!regionListenables.any(line.contains)) {
          continue;
        }
        offenders.add(
          '${file.path.replaceAll(r'\', '/')}:${i + 1}: ${line.trim()}',
        );
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'region 订阅必须走 AgentRegionBuilder：\n${offenders.join('\n')}',
    );
  });

  test('接缝只保留 Riverpod selector 路径', () {
    final source = File(seamPath).readAsStringSync();

    expect(
      source,
      contains('ref.watch(selector(key))'),
      reason: '接缝必须按 BindingKey 读取 selector',
    );
    expect(
      source,
      isNot(contains('ValueListenableBuilder')),
      reason: '第 5 批关批后不允许恢复旧 region 订阅路径',
    );
    expect(source, isNot(contains('legacyListenable')));
    expect(source, isNot(contains('agentConversationSliceEnabledProvider')));
  });
}
