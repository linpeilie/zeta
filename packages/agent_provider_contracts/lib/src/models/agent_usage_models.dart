// Usage quota is an optional capability port with one cohesive operation.
// ignore_for_file: one_member_abstracts

import 'package:agent_provider_contracts/src/models/immutable_collections.dart';

/// Why a provider usage limit was reached.
enum AgentUsageLimitReasonCode {
  quotaExhausted,
  rateLimited,
  accountRestricted,
  unknown,
}

/// App-owned quota-window label variants.
enum AgentUsageWindowLabelCode {
  duration,
  fiveHours,
  oneWeek,
  oneDay,
  sonnetOneWeek,
  opusOneWeek,
  planQuota,
  onDemandQuota,
  primaryQuota,
  extraQuota,
}

/// App-owned quota-heading variants.
enum AgentUsageLimitNameCode { claudeCodeSubscriptionQuota }

/// Agent 账号的用量窗口。
final class AgentUsageWindow {
  const AgentUsageWindow({
    required this.usedPercent,
    this.label,
    this.labelCode,
    this.resetsAt,
    this.windowDuration,
  }) : assert(
         label != null || labelCode != null,
         'A provider label or app-owned label code is required.',
       );

  /// provider 返回的窗口名称；缺失时由适配层提供稳定回退名称。
  final String? label;

  /// App-owned fallback label mapped by Presentation.
  final AgentUsageWindowLabelCode? labelCode;

  /// 当前窗口已使用百分比，范围为 0～100。
  final int usedPercent;

  /// 当前窗口重置时间。
  final DateTime? resetsAt;

  /// 当前窗口时长。
  final Duration? windowDuration;
}

/// Agent 账号余额。
final class AgentUsageCredits {
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
final class AgentUsageQuotaSnapshot {
  AgentUsageQuotaSnapshot({
    required this.providerId,
    required this.providerName,
    required List<AgentUsageWindow> windows,
    this.planType,
    this.limitName,
    this.limitNameCode,
    this.credits,
    this.availableResetCreditCount,
    this.reachedReasonCode,
  }) : windows = immutableList(windows);

  final String providerId;
  final String providerName;
  final String? planType;
  final String? limitName;
  final AgentUsageLimitNameCode? limitNameCode;
  final List<AgentUsageWindow> windows;
  final AgentUsageCredits? credits;

  /// 当前可用的限额重置卡数量；null 表示 Provider 未提供该信息。
  final int? availableResetCreditCount;

  final AgentUsageLimitReasonCode? reachedReasonCode;
}

/// Provider 可选的账号套餐读取能力。
abstract interface class AgentUsageQuotaProvider {
  Future<AgentUsageQuotaSnapshot?> readUsageQuota();
}
