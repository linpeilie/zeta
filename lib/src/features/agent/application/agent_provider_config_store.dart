import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 全局 Provider 设置的持久化端口。
abstract interface class AgentProviderConfigStore {
  Future<AgentProviderSettings> load();

  Future<void> save(AgentProviderSettings settings);
}
