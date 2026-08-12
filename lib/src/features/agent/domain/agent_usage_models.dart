/// Agent 账号的用量窗口。
class AgentUsageWindow {
  const AgentUsageWindow({
    required this.label,
    required this.usedPercent,
    this.resetsAt,
    this.windowDuration,
  });

  /// provider 返回的窗口名称；缺失时由适配层提供稳定回退名称。
  final String label;

  /// 当前窗口已使用百分比，范围为 0～100。
  final int usedPercent;

  /// 当前窗口重置时间。
  final DateTime? resetsAt;

  /// 当前窗口时长。
  final Duration? windowDuration;
}

/// Agent 账号余额。
class AgentUsageCredits {
  const AgentUsageCredits({
    required this.hasCredits,
    required this.unlimited,
    this.balance,
  });

  final bool hasCredits;
  final bool unlimited;

  /// provider 原样返回的余额文本，避免客户端臆测币种或单位。
  final String? balance;
}

/// Agent 账号套餐与限额快照。
class AgentUsageQuotaSnapshot {
  const AgentUsageQuotaSnapshot({
    required this.providerId,
    required this.providerName,
    required this.windows,
    this.planType,
    this.limitName,
    this.credits,
    this.availableResetCreditCount,
    this.reachedReason,
  });

  final String providerId;
  final String providerName;
  final String? planType;
  final String? limitName;
  final List<AgentUsageWindow> windows;
  final AgentUsageCredits? credits;

  /// 当前可用的限额重置卡数量；null 表示 Provider 未提供该信息。
  final int? availableResetCreditCount;

  final String? reachedReason;
}

/// Provider 可选的账号套餐读取能力。
abstract interface class AgentUsageQuotaProvider {
  Future<AgentUsageQuotaSnapshot?> readUsageQuota();
}
