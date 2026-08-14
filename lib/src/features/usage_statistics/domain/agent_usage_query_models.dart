import 'dart:collection';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

/// Provider 中立的 Token 历史查询。
final class AgentUsageQuery {
  const AgentUsageQuery({required this.earliest, this.forceRefresh = false});

  /// 只返回该时间点及之后开始的回合。
  final DateTime earliest;

  /// 绕过 Provider source 的可重用缓存并重新读取权威来源。
  final bool forceRefresh;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentUsageQuery &&
          earliest == other.earliest &&
          forceRefresh == other.forceRefresh;

  @override
  int get hashCode => Object.hash(earliest, forceRefresh);
}

/// 查询能力当前可观察的状态。
enum AgentUsageCapabilityStatus { unsupported, available, unavailable }

/// Token 历史权威来源中是否发现过可读取的会话。
///
/// 它与查询时间窗内是否有记录是两件事：历史存在但当前时间窗无记录时应展示 0；
/// 完全没有历史时保持“暂无历史”，不能伪造 0。
enum AgentTokenHistoryPresence { absent, present }

/// 可安全展示的非阻断诊断，不包含 Provider raw、路径或原始异常正文。
final class AgentUsageWarning {
  const AgentUsageWarning({required this.code, required this.message});

  final String code;
  final String message;
}

/// 一项可选用量能力的显式结果。
///
/// `unsupported` 表示没有注册该能力；`unavailable` 表示能力存在但本次读取失败，
/// 两者不得用同一个 null 隐式表达。
final class AgentUsageCapabilityResult<T> {
  const AgentUsageCapabilityResult.unsupported()
    : status = AgentUsageCapabilityStatus.unsupported,
      value = null,
      warning = null;

  const AgentUsageCapabilityResult.available(T this.value)
    : status = AgentUsageCapabilityStatus.available,
      warning = null;

  const AgentUsageCapabilityResult.unavailable(this.warning)
    : assert(warning != null),
      status = AgentUsageCapabilityStatus.unavailable,
      value = null;

  final AgentUsageCapabilityStatus status;
  final T? value;
  final AgentUsageWarning? warning;

  bool get isSupported => status != AgentUsageCapabilityStatus.unsupported;
  bool get isAvailable => status == AgentUsageCapabilityStatus.available;
}

/// 单个 Provider Token 历史 source 的中立快照。
final class AgentTokenUsageSourceSnapshot {
  AgentTokenUsageSourceSnapshot({
    required this.providerId,
    required this.providerName,
    required this.historyPresence,
    required List<AgentUsageRecord> records,
    required this.refreshedAt,
    List<AgentUsageWarning> warnings = const <AgentUsageWarning>[],
  }) : records = UnmodifiableListView<AgentUsageRecord>(
         List<AgentUsageRecord>.of(records),
       ),
       warnings = UnmodifiableListView<AgentUsageWarning>(
         List<AgentUsageWarning>.of(warnings),
       );

  final String providerId;
  final String providerName;
  final AgentTokenHistoryPresence historyPresence;
  final List<AgentUsageRecord> records;
  final DateTime refreshedAt;
  final List<AgentUsageWarning> warnings;
}

/// 统一查询对上层公开的 Provider 摘要，不暴露环境变量或 data 配置。
final class AgentUsageProviderDescriptor {
  const AgentUsageProviderDescriptor({
    required this.providerId,
    required this.providerName,
  });

  factory AgentUsageProviderDescriptor.fromConfig(AgentProviderConfig config) {
    return AgentUsageProviderDescriptor(
      providerId: config.id,
      providerName: config.displayName,
    );
  }

  final String providerId;
  final String providerName;
}

/// 单个 Provider 的统一用量读模型；套餐和 Token 历史保持独立状态。
final class AgentUsageProviderSnapshot {
  const AgentUsageProviderSnapshot({
    required this.provider,
    required this.quota,
    required this.tokenHistory,
  });

  final AgentUsageProviderDescriptor provider;
  final AgentUsageCapabilityResult<AgentUsageQuotaSnapshot> quota;
  final AgentUsageCapabilityResult<AgentTokenUsageSourceSnapshot> tokenHistory;
}
