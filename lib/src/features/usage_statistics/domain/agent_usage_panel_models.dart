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

/// Agent 统计面板中可选择的 Provider 摘要。
class AgentUsagePanelProvider {
  const AgentUsagePanelProvider({
    required this.providerId,
    required this.providerName,
  });

  final String providerId;
  final String providerName;
}

/// Agent 统计面板渐进式加载事件。
sealed class AgentUsagePanelLoadEvent {
  const AgentUsagePanelLoadEvent();
}

/// 已发现本轮所有可展示的 Provider。
class AgentUsagePanelProvidersDiscovered extends AgentUsagePanelLoadEvent {
  AgentUsagePanelProvidersDiscovered({
    required List<AgentUsagePanelProvider> providers,
  }) : providers = List<AgentUsagePanelProvider>.unmodifiable(providers);

  final List<AgentUsagePanelProvider> providers;
}

/// 单个 Provider 已成功完成加载。
class AgentUsagePanelProviderLoaded extends AgentUsagePanelLoadEvent {
  const AgentUsagePanelProviderLoaded(this.entry);

  final AgentUsagePanelEntry entry;
}

/// 单个 Provider 加载失败，不阻断其他 Provider。
class AgentUsagePanelProviderFailed extends AgentUsagePanelLoadEvent {
  const AgentUsagePanelProviderFailed({
    required this.provider,
    required this.message,
  });

  final AgentUsagePanelProvider provider;
  final String message;
}

/// 本轮所有 Provider 均已结束加载。
class AgentUsagePanelLoadCompleted extends AgentUsagePanelLoadEvent {
  const AgentUsagePanelLoadCompleted(this.refreshedAt);

  final DateTime refreshedAt;
}

/// Agent 统计面板的数据契约。
abstract interface class AgentUsagePanelRepository {
  Stream<AgentUsagePanelLoadEvent> load({bool forceRefresh = false});
}
