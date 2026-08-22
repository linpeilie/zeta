import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';

/// 单个 Provider 的 Token 历史查询边界。
///
/// CLI 私有文件、远端 API、差分、去重和索引 codec 都由 data 层实现；调用方只消费
/// [AgentTokenUsageSourceSnapshot]。没有注册 source 表示 `unsupported`，读取异常由
/// application 查询层映射为 `unavailable`。
abstract interface class AgentTokenUsageSource {
  String get providerId;

  Future<AgentTokenUsageSourceSnapshot> load(AgentUsageQuery query);
}

/// 根据实际 Provider 配置创建绑定实例的 Token source。
///
/// 具体 kind/id 到 factory 的映射只允许出现在 app/data 组合实现中；application 查询层
/// 仅依赖本接口。返回 null 表示该配置没有 Token 历史能力。
abstract interface class AgentTokenUsageSourceRegistry {
  AgentTokenUsageSource? createFor(AgentProviderConfig config);
}
