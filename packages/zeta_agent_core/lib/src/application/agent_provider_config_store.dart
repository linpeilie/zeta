import 'package:zeta_agent_core/src/domain/agent_provider_models.dart';

/// 全局 Provider 设置的持久化端口。
abstract interface class AgentProviderConfigStore {
  Future<AgentProviderSettings> load();

  Future<void> save(AgentProviderSettings settings);
}
