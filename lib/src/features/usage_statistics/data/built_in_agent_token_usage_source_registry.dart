import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/claude_code/claude_code_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/codex/codex_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/grok/grok_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

/// app 组合点使用的内置 Token source registry。
///
/// 具体 kind → 实现的选择只存在于 data/composition 边界；query service 与 UI 不分支。
final class BuiltInAgentTokenUsageSourceRegistry
    implements AgentTokenUsageSourceRegistry {
  const BuiltInAgentTokenUsageSourceRegistry(
    this._partitionStore, {
    UsageStatisticsTextCatalog? textCatalog,
  }) : _textCatalog = textCatalog ?? const FallbackUsageStatisticsTextCatalog();

  final UsageStatisticsPartitionStore _partitionStore;
  final UsageStatisticsTextCatalog _textCatalog;

  @override
  AgentTokenUsageSource? createFor(AgentProviderConfig config) {
    return switch (config.kind) {
      AgentProviderKind.codexAppServer => CodexTokenUsageSource(
        config: config,
        partitionStore: _partitionStore,
        textCatalog: _textCatalog,
      ),
      AgentProviderKind.acp => GrokTokenUsageSource(
        config: config,
        partitionStore: _partitionStore,
        textCatalog: _textCatalog,
      ),
      AgentProviderKind.claudeCode => ClaudeCodeTokenUsageSource(
        config: config,
        partitionStore: _partitionStore,
        textCatalog: _textCatalog,
      ),
      AgentProviderKind.cursorAcp => null,
    };
  }
}
