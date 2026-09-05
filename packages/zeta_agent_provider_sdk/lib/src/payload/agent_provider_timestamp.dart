/// 宽容解析 adapter 已经选定的时间值；无效或越界时返回 null。
///
/// 只负责“值怎么解析”，不负责“从哪个键取值”。[unit] 必须由具体 Provider
/// adapter 按协议声明；`automatic` 仅用于确实兼容秒/毫秒两种历史格式的字段。
DateTime? tryParseAgentProviderTimestamp(
  Object? value, {
  AgentProviderTimestampUnit unit = AgentProviderTimestampUnit.automatic,
}) {
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
  }
  if (value is! num || !value.isFinite) {
    return null;
  }

  try {
    final numeric = value.toInt();
    final milliseconds = switch (unit) {
      AgentProviderTimestampUnit.seconds =>
        numeric * Duration.millisecondsPerSecond,
      AgentProviderTimestampUnit.milliseconds => numeric,
      AgentProviderTimestampUnit.automatic =>
        numeric.abs() < 1000000000000
            ? numeric * Duration.millisecondsPerSecond
            : numeric,
    };
    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
      isUtc: true,
    ).toLocal();
  } on RangeError {
    return null;
  } on UnsupportedError {
    return null;
  }
}

/// Provider 协议对数值时间戳单位的声明。
enum AgentProviderTimestampUnit { seconds, milliseconds, automatic }
