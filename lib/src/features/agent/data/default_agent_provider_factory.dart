import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/grok_acp_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/app_server/codex_app_server_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_agent_provider.dart';

/// 生产环境默认 provider 工厂。
///
/// 已实现 Codex app-server 与 Grok ACP stdio；Claude Code 为空壳（initialize
/// 诚实失败）；Cursor 已从运行时组合中断开。
class DefaultAgentProviderFactory implements AgentProviderFactory {
  const DefaultAgentProviderFactory();

  @override
  AgentProvider create(AgentProviderConfig config) {
    if (CursorRetirementPolicy.isRetiredProvider(config)) {
      throw UnsupportedError(CursorRetirementPolicy.unavailableMessage);
    }
    return switch (config.kind) {
      AgentProviderKind.codexAppServer => CodexAppServerAgentProvider(
        config: config,
      ),
      AgentProviderKind.acp => GrokAcpAgentProvider(config: config),
      AgentProviderKind.cursorAcp => throw UnsupportedError(
        CursorRetirementPolicy.unavailableMessage,
      ),
      AgentProviderKind.claudeCode => ClaudeCodeAgentProvider(config: config),
    };
  }
}
