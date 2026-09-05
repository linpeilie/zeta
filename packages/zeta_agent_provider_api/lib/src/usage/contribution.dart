import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';
import 'source.dart';
import 'partition.dart';
import 'text_catalog.dart';

/// 用量插件仅可读写自己的不透明索引分区。
final class AgentUsageHostServices {
  const AgentUsageHostServices({
    required this.partitionPort,
    this.textCatalog = const FallbackAgentUsageSourceTextCatalog(),
  });
  final AgentUsagePartitionPort partitionPort;
  final AgentUsageSourceTextCatalog textCatalog;
}

/// 以 Provider 协议类型路由的用量源贡献。
final class AgentUsageContribution extends ZetaPluginContribution {
  const AgentUsageContribution({
    required this.providerType,
    required this.createSource,
  });
  final AgentProviderTypeId providerType;
  final AgentTokenUsageSource Function(
    AgentUsageHostServices services,
    AgentProviderConfig config,
  )
  createSource;
  @override
  String get contributionKind => 'zeta.agent.token-usage-source';
}
