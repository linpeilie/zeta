import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/grok_acp_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_acp_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_session_index_store.dart';
import 'package:zeta/src/features/agent/data/datasources/app_server/codex_app_server_agent_provider.dart';

/// 生产环境默认 provider 工厂。
///
/// 已实现 Codex app-server 与 Grok ACP stdio；Claude Code 仍保留配置入口。
class DefaultAgentProviderFactory implements AgentProviderFactory {
  const DefaultAgentProviderFactory({required this.cursorSessionIndexStore});

  /// Zeta 自己维护的 Cursor 最小会话索引；不包含 Cursor 官方 session 正文。
  final CursorSessionIndexStore cursorSessionIndexStore;

  @override
  AgentProvider create(AgentProviderConfig config) {
    return switch (config.kind) {
      AgentProviderKind.codexAppServer => CodexAppServerAgentProvider(
        config: config,
      ),
      AgentProviderKind.acp => GrokAcpAgentProvider(config: config),
      AgentProviderKind.cursorAcp => CursorAcpAgentProvider(
        config: config,
        sessionIndexStore: cursorSessionIndexStore,
      ),
      AgentProviderKind.claudeCode => throw UnsupportedError(
        'Claude Code providers are not implemented yet.',
      ),
    };
  }
}
