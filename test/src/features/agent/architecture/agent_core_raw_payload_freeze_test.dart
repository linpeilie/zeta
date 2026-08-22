import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 中立内核里 Provider raw payload 的守卫。
///
/// **结论（2026-08-21 落地）**：目标架构 §4.1 说 `zeta_agent_core` 不拥有
/// Provider raw payload。产品侧确认上下文面板的"原始消息"卡片要保留，于是采取
/// 折中方案——原文继续在上下文面板里以 **JSON 文本**展示，但**不能再被取值**：
///
/// 1. 原文类型换成不透明的 `AgentProviderRawPayload`（无 `operator []`、无
///    `keys`、无 `toMap()`），任何 `raw['x']` 都是编译错误；
/// 2. 只有上下文面板会调用唯一的内容出口 `toPrettyJson()`；
/// 3. 只有 `zeta_agent_providers` 能用 `AgentProviderRawPayload.wrap` 造原文；
/// 4. 面板不展示的模型，`raw` 字段**直接删掉**（Map 版本清零），需要的语义改成
///    adapter 显式声明的 typed 字段（`appendsProgress` / `inputDetail` /
///    `sourceLabel` / `sessionPath` / `sourceItemId` / `AgentFileChangeSnapshot`）。
///
/// 本守卫把这四条钉住。
void main() {
  /// 仍然携带原文的中立模型字段数（只允许变少）。
  ///
  /// 当前 12 处：面板展示的 message / permission / question / planApproval /
  /// historyEvent 的 `raw`，工具的 `rawInput` / `rawOutput`，以及内部 mutation
  /// 与 timeline store 的传递字段。
  const int rawPayloadFieldBaseline = 12;

  /// 允许调用唯一内容出口的生产文件。
  const String contextPanelPath =
      'lib/src/features/agent/presentation/widgets/agent_pane_context_panel.dart';

  Iterable<File> dartFilesIn(String path) => Directory(path)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));

  String normalize(String path) => path.replaceAll(r'\', '/');

  test('中立内核不再有 Map 形态的原文字段', () {
    final pattern = RegExp(
      r'final Map<String, Object\?> (raw|rawInput|rawOutput)\b',
    );
    final offenders = <String>[];
    for (final file in dartFilesIn('packages/zeta_agent_core/lib')) {
      final hits = pattern.allMatches(file.readAsStringSync()).length;
      if (hits > 0) {
        offenders.add('${normalize(file.path)}: $hits');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '原文只能是不透明的 AgentProviderRawPayload；Map 形态等于把协议原文'
          '重新变成可取值的内核 API：\n${offenders.join('\n')}',
    );
  });

  test('携带原文的字段只允许减少', () {
    final pattern = RegExp(r'final AgentProviderRawPayload ');
    var total = 0;
    final byFile = <String, int>{};
    for (final file in dartFilesIn('packages/zeta_agent_core/lib')) {
      final hits = pattern.allMatches(file.readAsStringSync()).length;
      if (hits > 0) {
        byFile[normalize(file.path)] = hits;
        total += hits;
      }
    }

    expect(
      total,
      lessThanOrEqualTo(rawPayloadFieldBaseline),
      reason:
          '中立内核不该新增原文字段。需要更多协议信息时，请让 Provider adapter '
          '产出 typed evidence：\n'
          '${byFile.entries.map((e) => '${e.key}: ${e.value}').join('\n')}',
    );
  });

  test('AgentProviderRawPayload 保持不透明', () {
    final source = File(
      'packages/zeta_agent_core/lib/src/domain/agent_provider_raw_payload.dart',
    ).readAsStringSync();

    for (final leak in const <String>[
      'operator [](',
      'Iterable<String> get keys',
      'Map<String, Object?> toMap(',
      'Map<String, Object?> get json',
    ]) {
      expect(source, isNot(contains(leak)), reason: '$leak 会让原文重新可取值，整套约束就白做了');
    }
    // 唯一内容出口。
    expect(source, contains('String toPrettyJson()'));
    // toString 不得带内容，避免误插值把整份 payload 写进日志。
    expect(source, contains("'AgentProviderRawPayload(\$entryCount entries)'"));
  });

  test('只有 zeta_agent_providers 能构造原文', () {
    final offenders = <String>[];
    for (final root in const <String>[
      'lib',
      'packages/zeta_agent_core/lib',
      'packages/zeta_ui/lib',
      'packages/zeta_foundation/lib',
      'packages/zeta_plugin_kernel/lib',
    ]) {
      for (final file in dartFilesIn(root)) {
        final path = normalize(file.path);
        if (path.endsWith('agent_provider_raw_payload.dart')) {
          continue;
        }
        if (file.readAsStringSync().contains('AgentProviderRawPayload.wrap')) {
          offenders.add(path);
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '原文只能由协议适配层产出（G1/G2）：\n${offenders.join('\n')}',
    );
  });

  test('适配层统一经 wrapAgentProviderPayload 包装原文', () {
    // 直接调构造会绕过报文时间推导，面板的时间列就会退回 '—'。
    final offenders = <String>[];
    for (final file in dartFilesIn('packages/zeta_agent_providers/lib')) {
      final path = normalize(file.path);
      if (path.endsWith('mappers/agent_provider_payload.dart')) {
        continue;
      }
      if (file.readAsStringSync().contains('AgentProviderRawPayload.wrap')) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '请改用 wrapAgentProviderPayload(...)，它会顺带算出 capturedAt：\n'
          '${offenders.join('\n')}',
    );
  });

  test('原文的唯一渲染出口是上下文面板', () {
    final offenders = <String>[];
    for (final root in const <String>[
      'lib',
      'packages/zeta_agent_core/lib',
      'packages/zeta_agent_providers/lib',
      'packages/zeta_ui/lib',
      'packages/zeta_foundation/lib',
      'packages/zeta_plugin_kernel/lib',
    ]) {
      for (final file in dartFilesIn(root)) {
        final path = normalize(file.path);
        if (path == contextPanelPath ||
            path.endsWith('agent_provider_raw_payload.dart')) {
          continue;
        }
        if (file.readAsStringSync().contains('toPrettyJson()')) {
          offenders.add(path);
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '原文只在上下文面板里展示；进日志 / 落盘 / 拼进业务文案都不允许：\n'
          '${offenders.join('\n')}',
    );
  });

  test('raw payload 不进入持久化与指标白名单', () {
    // 落盘/指标是 raw 泄露的两条主要通道，这里做一次源码级复核（G7）。
    final persistence = <File>[
      ...dartFilesIn('lib/src/features/agent/data'),
      ...dartFilesIn('packages/zeta_foundation/lib'),
    ];

    for (final file in persistence) {
      final source = file.readAsStringSync();
      final path = normalize(file.path);
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
