import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 中立内核里 Provider raw payload 的冻结守卫。
///
/// 目标架构 §4.1 明确写着 `zeta_agent_core`**不拥有** Provider raw payload，但
/// 现状是 36 个中立模型字段（21 个事件的 `raw`，工具的 `rawInput` / `rawOutput`
/// 等）把协议原文固定成了内核的公开 API。风险：
///
/// - application / presentation 直接读协议字段，绕过 typed domain model；
/// - Provider 协议升级顺着 raw 扩散进内核 API；
/// - raw 内容进入缓存、错误与日志链路；
/// - 拆 `zeta_agent_providers` 时无法在编译期切开 Provider 与内核。
///
/// 这是拆包前的既有设计，本守卫**只冻结不清算**：数量只允许变少。真正的替换按
/// 仓库已有的成功范式做——文件变更证据早就从 raw 演进成了 typed
/// `AgentFileChangeSnapshot`，其余事件照此逐类替换（Phase 2/3）。
///
/// 另有一个需要产品决定的点：上下文面板的"原始消息"卡片当前直接渲染 `item.raw`。
/// 它是真实能力，但应该改成由 Provider adapter 按需提供的 typed 诊断通道，而不是
/// 每个中立事件都常驻一份原文。在拆 `zeta_agent_providers` 之前必须有结论。
void main() {
  /// 当前中立模型里携带 Provider 原文的字段总数。
  const int rawPayloadFieldBaseline = 36;

  test('内核携带 raw payload 的字段只允许减少', () {
    final pattern = RegExp(
      r'final Map<String, Object\?> (raw|rawInput|rawOutput)\b',
    );
    var total = 0;
    final byFile = <String, int>{};
    for (final file
        in Directory('packages/zeta_agent_core/lib/src/domain')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final hits = pattern.allMatches(file.readAsStringSync()).length;
      if (hits > 0) {
        byFile[file.path.replaceAll(r'\', '/')] = hits;
        total += hits;
      }
    }

    expect(
      total,
      lessThanOrEqualTo(rawPayloadFieldBaseline),
      reason:
          '中立内核不该新增 Provider raw payload 字段。'
          '需要更多协议信息时，请让 Provider adapter 产出 typed evidence：\n'
          '${byFile.entries.map((e) => '${e.key}: ${e.value}').join('\n')}',
    );
  });

  test('raw payload 不进入持久化与指标白名单', () {
    // 落盘/指标是 raw 泄露的两条主要通道，这里做一次源码级复核（G7）。
    final persistence = <File>[
      ...Directory(
        'lib/src/features/agent/data',
      ).listSync(recursive: true).whereType<File>(),
      ...Directory(
        'packages/zeta_foundation/lib',
      ).listSync(recursive: true).whereType<File>(),
    ].where((file) => file.path.endsWith('.dart'));

    for (final file in persistence) {
      final source = file.readAsStringSync();
      final path = file.path.replaceAll(r'\', '/');
      if (!path.contains('turn_context') && !path.contains('metric')) {
        continue;
      }
      expect(
        source.contains("'raw'"),
        isFalse,
        reason: '$path 把 raw 写进了持久化或指标序列',
      );
    }
  });
}
