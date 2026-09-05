import 'package:zeta_agent_core/zeta_agent_core.dart';
// WP-C 过渡白名单：WP-D 将此注册表改为消费 usage 贡献。
import 'package:zeta_agent_provider_codex/zeta_agent_provider_codex.dart'
    show codexAgentProviderType;
import 'package:zeta_agent_provider_grok/zeta_agent_provider_grok.dart'
    show grokAgentProviderType;
import 'package:zeta_agent_provider_claude_code/zeta_agent_provider_claude_code.dart'
    show claudeCodeAgentProviderType;
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
      codexAgentProviderType => CodexTokenUsageSource(
        config: config,
        partitionStore: _partitionStore,
        textCatalog: _textCatalog,
      ),
      grokAgentProviderType => GrokTokenUsageSource(
        config: config,
        partitionStore: _partitionStore,
        textCatalog: _textCatalog,
      ),
      claudeCodeAgentProviderType => ClaudeCodeTokenUsageSource(
        config: config,
        partitionStore: _partitionStore,
        textCatalog: _textCatalog,
      ),
      _ => null,
    };
  }
}
