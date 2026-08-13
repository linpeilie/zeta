import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_cli_metadata_coordinator.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_hidden_thread_store.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_permission_policy_adapter.dart';
import 'package:zeta/src/features/agent/data/native_agent_provider_bundles.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';

/// 生产环境默认 provider 工厂。
///
/// 已实现 Codex app-server、Grok ACP stdio 与 Claude Code stream-json；
/// Cursor 已从运行时组合中断开。
class DefaultAgentProviderFactory implements AgentProviderBundleFactory {
  const DefaultAgentProviderFactory({
    this.claudeCodeSessionDecisionStoreFactory,
    this.claudeCodeHiddenThreadStore,
    this.claudeCodeMetadataLoader,
  });

  /// Claude Code 会话级 always 决策存储；生产由 app 组合层注入具体文件。
  final ClaudeCodeSessionDecisionStoreFactory?
  claudeCodeSessionDecisionStoreFactory;

  /// Claude Code 本地历史隐藏列表；生产由 app 组合层注入 `~/.zeta` 文件。
  final ClaudeCodeHiddenThreadStore? claudeCodeHiddenThreadStore;

  /// 测试或宿主注入的 Claude CLI metadata loader；生产默认创建独立 probe。
  final ClaudeCodeCliMetadataLoader? claudeCodeMetadataLoader;

  /// 原生 Bundle 创建入口。
  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    if (CursorRetirementPolicy.isRetiredProvider(config)) {
      throw UnsupportedError(CursorRetirementPolicy.unavailableMessage);
    }
    return switch (config.kind) {
      AgentProviderKind.codexAppServer => createCodexBundle(config),
      AgentProviderKind.acp => createGrokBundle(config),
      AgentProviderKind.cursorAcp => throw UnsupportedError(
        CursorRetirementPolicy.unavailableMessage,
      ),
      AgentProviderKind.claudeCode => createClaudeCodeBundle(
        config,
        metadataLoader: claudeCodeMetadataLoader,
        sessionDecisionStoreFactory: claudeCodeSessionDecisionStoreFactory,
        hiddenThreadStore: claudeCodeHiddenThreadStore,
      ),
    };
  }
}
