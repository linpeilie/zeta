/// Agent 套餐额度窗口的中立时长标签。
///
/// 以 Codex `windowDurationMins` 的展示规则为准（如 300 →「5 小时」、
/// 10080 →「1 周」），Grok 等其它 Provider 在映射时应复用，避免「周额度」
/// 与「1 周」两套文案并存。算法与语言无关，只翻译外围静态 token。
library;

import 'package:zeta_agent_core/src/domain/agent_ui_text_catalog.dart';
import 'package:zeta_agent_core/src/domain/fallback_agent_ui_text_catalog.dart';

/// 由窗口时长（分钟）生成短标签；无法识别时返回 null。
String? formatAgentUsageWindowLabelFromMinutes(
  int? minutes, {
  AgentUiTextCatalog catalog = const FallbackAgentUiTextCatalog(),
}) {
  if (minutes == null || minutes <= 0) {
    return null;
  }
  const weekMinutes = 7 * 24 * 60;
  const dayMinutes = 24 * 60;
  const hourMinutes = 60;

  if (minutes % weekMinutes == 0) {
    final weeks = minutes ~/ weekMinutes;
    return catalog.usageWindowWeeks('$weeks');
  }
  if (minutes % dayMinutes == 0) {
    final days = minutes ~/ dayMinutes;
    return catalog.usageWindowDays('$days');
  }
  if (minutes % hourMinutes == 0) {
    return catalog.usageWindowHours('${minutes ~/ hourMinutes}');
  }
  if (minutes > hourMinutes) {
    final hours = minutes ~/ hourMinutes;
    final remaining = minutes % hourMinutes;
    return catalog.usageWindowHoursMinutes('$hours', '$remaining');
  }
  return catalog.usageWindowMinutes('$minutes');
}

/// Grok `USAGE_PERIOD_TYPE_*` 在缺少精确时长时的回退标签。
String? formatAgentUsageWindowLabelFromPeriodType(
  String? periodType, {
  AgentUiTextCatalog catalog = const FallbackAgentUiTextCatalog(),
}) {
  return switch (periodType) {
    'USAGE_PERIOD_TYPE_WEEKLY' => catalog.usageWindowOneWeek,
    'USAGE_PERIOD_TYPE_DAILY' => catalog.usageWindowOneDay,
    // 月周期长度不固定，优先用 start/end 算出的分钟标签；此处不臆造「1 月」。
    'USAGE_PERIOD_TYPE_MONTHLY' => null,
    _ => null,
  };
}
