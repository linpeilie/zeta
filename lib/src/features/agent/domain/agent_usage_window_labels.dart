/// Agent 套餐额度窗口的中立时长标签。
///
/// 以 Codex `windowDurationMins` 的展示规则为准（如 300 →「5 小时」、
/// 10080 →「1 周」），Grok 等其它 Provider 在映射时应复用，避免「周额度」
/// 与「1 周」两套文案并存。
library;

/// 由窗口时长（分钟）生成短中文标签；无法识别时返回 null。
String? formatAgentUsageWindowLabelFromMinutes(int? minutes) {
  if (minutes == null || minutes <= 0) {
    return null;
  }
  const weekMinutes = 7 * 24 * 60;
  const dayMinutes = 24 * 60;
  const hourMinutes = 60;

  if (minutes % weekMinutes == 0) {
    final weeks = minutes ~/ weekMinutes;
    return '$weeks 周';
  }
  if (minutes % dayMinutes == 0) {
    final days = minutes ~/ dayMinutes;
    return '$days 天';
  }
  if (minutes % hourMinutes == 0) {
    return '${minutes ~/ hourMinutes} 小时';
  }
  if (minutes > hourMinutes) {
    final hours = minutes ~/ hourMinutes;
    final remaining = minutes % hourMinutes;
    return '$hours 小时 $remaining 分钟';
  }
  return '$minutes 分钟';
}

/// Grok `USAGE_PERIOD_TYPE_*` 在缺少精确时长时的回退标签。
String? formatAgentUsageWindowLabelFromPeriodType(String? periodType) {
  return switch (periodType) {
    'USAGE_PERIOD_TYPE_WEEKLY' => '1 周',
    'USAGE_PERIOD_TYPE_DAILY' => '1 天',
    // 月周期长度不固定，优先用 start/end 算出的分钟标签；此处不臆造「1 月」。
    'USAGE_PERIOD_TYPE_MONTHLY' => null,
    _ => null,
  };
}
