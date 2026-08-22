import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 包装 Provider 原文，并顺带算出报文时间。
///
/// 中立层拿到的是不可取值的 [AgentProviderRawPayload]，所以"这份报文是什么时候
/// 的"必须在**这里**算好——上下文面板只读 `capturedAt`，不再翻 JSON 猜键名。
///
/// [capturedAt] 显式传入时优先；否则从原文里宽容推导（见
/// [deriveAgentPayloadCapturedAt]）。
AgentProviderRawPayload wrapAgentProviderPayload(
  Map<String, Object?> json, {
  DateTime? capturedAt,
}) {
  return AgentProviderRawPayload.wrap(
    json,
    capturedAt: capturedAt ?? deriveAgentPayloadCapturedAt(json),
  );
}

/// 从 wire payload 里宽容推导报文时间；推不出来就是 null。
///
/// 这是**对 wire 形状的启发式猜测**：候选键名来自三个 CLI 的实际报文，因此属于
/// Provider 语义，住在适配层（G2）。中立层与 UI 只接受算好的
/// `AgentProviderRawPayload.capturedAt`。
///
/// 刻意**不做 `DateTime.now()` 兜底**：协议没给时间就是没有，编造一个"现在"会让
/// 历史回放和实时流显示出不同的时间。
DateTime? deriveAgentPayloadCapturedAt(Map<String, Object?> json) {
  if (json.isEmpty) {
    return null;
  }

  const topLevelKeys = <String>[
    'timestamp',
    'startedAt',
    'started_at',
    'completedAt',
    'completed_at',
    'createdAt',
    'created_at',
  ];
  for (final key in topLevelKeys) {
    final parsed = _toDateTime(json[key]);
    if (parsed != null) {
      return parsed;
    }
  }

  // 部分协议把时间戳放在内嵌 payload 里（Codex JSONL、ACP `_meta`）。
  const nestedKeys = <String>['payload', '_meta'];
  const nestedTimeKeys = <String>[
    'agentTimestampMs',
    'timestamp',
    'started_at',
    'startedAt',
    'completed_at',
    'completedAt',
  ];
  for (final container in nestedKeys) {
    final nested = json[container];
    if (nested is! Map) {
      continue;
    }
    for (final key in nestedTimeKeys) {
      final parsed = _toDateTime(nested[key]);
      if (parsed != null) {
        return parsed;
      }
    }
  }

  return null;
}

/// 兼容秒/毫秒整数与 ISO 字符串。
DateTime? _toDateTime(Object? value) {
  if (value is int) {
    // 小于 10^12 视为秒级时间戳，统一换算到毫秒。
    final millis = value < 1000000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
  }
  if (value is num) {
    return _toDateTime(value.toInt());
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}
