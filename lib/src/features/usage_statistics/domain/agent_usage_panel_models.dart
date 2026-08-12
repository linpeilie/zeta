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

  /// 折叠摘要使用的额度窗口。
  ///
  /// 仅付费套餐参与；优先正周期最短的窗口，等周期保持 Provider 原始顺序。
  /// 所有周期均未知或无效时回退第一项。
  AgentUsageWindow? get compactQuotaWindow {
    if (!hasSubscriptionPlan) {
      return null;
    }
    final windows = quota?.windows ?? const <AgentUsageWindow>[];
    if (windows.isEmpty) {
      return null;
    }

    AgentUsageWindow? shortest;
    Duration? shortestDuration;
    for (final window in windows) {
      final duration = window.windowDuration;
      if (duration == null || duration <= Duration.zero) {
        continue;
      }
      if (shortestDuration == null || duration < shortestDuration) {
        shortest = window;
        shortestDuration = duration;
      }
    }
    return shortest ?? windows.first;
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

/// 单个 Provider 的侧栏读取结果。
class AgentUsagePanelProviderResult {
  const AgentUsagePanelProviderResult({
    required this.entry,
    required this.refreshedAt,
  });

  final AgentUsagePanelEntry entry;
  final DateTime refreshedAt;
}

/// Agent 统计面板的数据契约。
abstract interface class AgentUsagePanelRepository {
  /// 只发现可展示目录，不读取任何 Provider 的套餐或 Token 数据。
  Future<List<AgentUsagePanelProvider>> discoverProviders();

  /// 只读取指定 Provider；返回 null 表示它已不在启用目录中。
  Future<AgentUsagePanelProviderResult?> loadProvider(
    String providerId, {
    bool forceRefresh = false,
  });
}
