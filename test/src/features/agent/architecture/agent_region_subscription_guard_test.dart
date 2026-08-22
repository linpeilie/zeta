import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// region 订阅必须经 `AgentRegionBuilder`（Phase 2 E 步）。
///
/// 直接订阅 `viewModel.<region>StateListenable` 会绕过切片：功能看起来正常
/// （两条路径给的是同一批对象），但那个组件就永远留在旧路径上，flag 打开也不会
/// 走 selector——**正是这种"看起来对"的偏差最难发现**，所以用守卫钉住。
void main() {
  const paneRoot = 'lib/src/features/agent/presentation';
  const regionListenables = <String>[
    'headerStateListenable',
    'composerStateListenable',
    'pendingInteractionStateListenable',
    'expansionStateListenable',
    'historyStateListenable',
  ];

  /// 唯一允许直接引用 region listenable 的地方：接缝自己，以及作为
  /// `legacyListenable:` 参数传进接缝。
  const seamPath = '$paneRoot/conversation_slice/agent_region_builder.dart';

  /// 另外两处按职责豁免：
  /// - ViewModel 是这些 listenable 的**定义方**；
  /// - 切片 binding 订阅它们是 **ingress**——切片正是靠这条线拿到 region 更新的。
  const allowedPaths = <String>{
    seamPath,
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
        // formatter 会把 `legacyListenable: widget.viewModel.xxxListenable,`
        // 拆成最多三行，因此向前回看三行才不会误报。
        final lookback = lines.sublist(i - 3 < 0 ? 0 : i - 3, i + 1).join('\n');
        final isSeamArgument = lookback.contains('legacyListenable:');
        if (!isSeamArgument) {
          offenders.add(
            '${file.path.replaceAll(r'\', '/')}:${i + 1}: ${line.trim()}',
          );
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'region 订阅必须走 AgentRegionBuilder，否则该组件在 flag 打开时仍停留在'
          '旧路径：\n${offenders.join('\n')}',
    );
  });

  test('接缝本身同时保留两条路径', () {
    final source = File(seamPath).readAsStringSync();

    expect(
      source,
      contains('agentConversationSliceEnabledProvider'),
      reason: '接缝必须按 entry 判定是否启用切片',
    );
    expect(
      source,
      contains('ValueListenableBuilder<T>'),
      reason: '回退路径必须保留：feature flag 的回退侧要一直可用',
    );
  });
}
