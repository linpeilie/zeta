import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

/// Context 面板中单个 Provider 配置实例的轻量用量快照。
class AgentUsagePanelEntry {
  const AgentUsagePanelEntry({
    required this.providerId,
    required this.providerName,
    this.todayTokens,
    this.quota,
    this.message,
  });

  final String providerId;
  final String providerName;

  /// 本地当天、跨项目聚合的 Token；为 null 表示该 Provider 暂不支持统计。
  final UsageTokenBreakdown? todayTokens;

  /// Provider 实时返回的套餐与限额；不提供时保持为空。
  final AgentUsageQuotaSnapshot? quota;

  /// 单个 Provider 的非阻断读取提示。
  final String? message;

  bool get hasSubscriptionPlan {
    final planType = quota?.planType?.trim().toLowerCase();
    return planType != null && planType.isNotEmpty && planType != 'free';
  }
}

/// Agent 统计面板的一次完整刷新结果。
class AgentUsagePanelSnapshot {
  AgentUsagePanelSnapshot({
    required List<AgentUsagePanelEntry> entries,
    required this.refreshedAt,
  }) : entries = List<AgentUsagePanelEntry>.unmodifiable(entries);

  final List<AgentUsagePanelEntry> entries;
  final DateTime refreshedAt;
}

/// Agent 统计面板的数据契约。
abstract interface class AgentUsagePanelRepository {
  Future<AgentUsagePanelSnapshot> load({bool forceRefresh = false});
}
