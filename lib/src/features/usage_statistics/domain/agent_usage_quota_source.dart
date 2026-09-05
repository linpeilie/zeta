import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';

/// 统一查询层读取 Provider 套餐额度的中立边界。
///
/// 生产实现后续在 data 层包装 `AgentProviderGlobalRuntime` 与既有 bundle 端口；
/// application 不接触 Provider 生命周期或实现类型。
abstract interface class AgentUsageQuotaSource {
  Future<AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>> loadQuota(
    AgentProviderConfig config,
  );
}
