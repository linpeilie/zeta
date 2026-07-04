import '../../domain/agent/agent_models.dart';
import '../../domain/agent/agent_provider.dart';
import 'codex_app_server_provider.dart';

/// 生产环境默认 provider 工厂。
///
/// V1 只真正实现 Codex app-server；其他类型先保留配置入口，避免 UI 核心再改。
class DefaultAgentProviderFactory implements AgentProviderFactory {
  const DefaultAgentProviderFactory();

  @override
  AgentProvider create(AgentProviderConfig config) {
    return switch (config.kind) {
      AgentProviderKind.codexAppServer => CodexAppServerAgentProvider(
        config: config,
      ),
      AgentProviderKind.acp => throw UnsupportedError(
        'ACP providers are not implemented yet.',
      ),
      AgentProviderKind.claudeCode => throw UnsupportedError(
        'Claude Code providers are not implemented yet.',
      ),
    };
  }
}
