import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 查询能力当前可观察的状态。
enum AgentUsageCapabilityStatus { unsupported, available, unavailable }

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
