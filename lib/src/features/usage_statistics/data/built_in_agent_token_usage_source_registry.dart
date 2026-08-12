import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/codex/codex_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/grok/grok_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_token_usage_source.dart';

/// app 组合点使用的内置 Token source registry。
///
/// 具体 kind → 实现的选择只存在于 data/composition 边界；query service 与 UI 不分支。
final class BuiltInAgentTokenUsageSourceRegistry
    implements AgentTokenUsageSourceRegistry {
  const BuiltInAgentTokenUsageSourceRegistry(this._partitionStore);

  final UsageStatisticsPartitionStore _partitionStore;

  @override
  AgentTokenUsageSource? createFor(AgentProviderConfig config) {
    return switch (config.kind) {
      AgentProviderKind.codexAppServer => CodexTokenUsageSource(
        config: config,
        partitionStore: _partitionStore,
      ),
      AgentProviderKind.acp => GrokTokenUsageSource(
        config: config,
        partitionStore: _partitionStore,
      ),
      AgentProviderKind.cursorAcp || AgentProviderKind.claudeCode => null,
    };
  }
}
