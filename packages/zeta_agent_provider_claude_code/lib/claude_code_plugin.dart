import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

import 'package:zeta_agent_provider_claude_code/src/claude_code_static_capabilities.dart';
import 'package:zeta_agent_provider_claude_code/src/datasources/claude_code/claude_code_cli_metadata_coordinator.dart';
import 'package:zeta_agent_provider_claude_code/src/datasources/claude_code/claude_code_hidden_thread_store.dart';
import 'package:zeta_agent_provider_claude_code/src/datasources/claude_code/claude_code_permission_policy_adapter.dart';
import 'package:zeta_agent_provider_claude_code/src/datasources/claude_code/claude_code_provider_config.dart';
import 'package:zeta_agent_provider_claude_code/src/claude_code_provider_bundle.dart';

export 'package:zeta_agent_provider_claude_code/src/datasources/claude_code/claude_code_provider_config.dart'
    show claudeCodeAccountDataEnrichmentKey;

/// Claude Code 内置配置的稳定 id。
const String defaultClaudeCodeProviderId = 'claude_code';

/// providers.json V2 沿用的 Claude Code 协议域字符串。
const AgentProviderTypeId claudeCodeAgentProviderType = AgentProviderTypeId(
  'claudeCode',
);

/// 默认 Claude Code CLI stream-json 配置。
const AgentProviderConfig defaultClaudeCodeAgentProviderConfig =
    AgentProviderConfig(
      id: defaultClaudeCodeProviderId,
      displayName: 'Claude',
      kind: claudeCodeAgentProviderType,
      command: 'claude',
    );

/// Claude Code 插件拥有的静态 definition。
const AgentProviderDefinition claudeCodeAgentProviderDefinition =
    AgentProviderDefinition(
      providerId: defaultClaudeCodeProviderId,
      providerType: claudeCodeAgentProviderType,
      defaultConfig: defaultClaudeCodeAgentProviderConfig,
      staticCapabilities: claudeCodeStaticCapabilities,
      modelCatalogSourceLabel: 'Claude Code',
      metricLabel: ZetaMetricLabel.constant('claude_code'),
      modelCatalogFingerprintExtraKeys: <String>{
        claudeCodeAccountDataEnrichmentKey,
      },
    );

/// Claude Code stream-json 的显式 compile-time Provider 插件。
final class ClaudeCodeAgentProviderPlugin
    implements ZetaSynchronousPluginFactory {
  ClaudeCodeAgentProviderPlugin({
    this.sessionDecisionStoreFactory,
    this.hiddenThreadStore,
    this.metadataLoader,
    this.textCatalog = const FallbackAgentUiTextCatalog(),
  });

  static const String pluginId = 'zeta.agent.claude-code';

  final ClaudeCodeSessionDecisionStoreFactory? sessionDecisionStoreFactory;
  final ClaudeCodeHiddenThreadStore? hiddenThreadStore;
  final ClaudeCodeCliMetadataLoader? metadataLoader;
  final AgentUiTextCatalog textCatalog;

  @override
  final ZetaPluginDescriptor descriptor = ZetaPluginDescriptor(
    id: pluginId,
    apiVersion: ZetaPluginApiVersion.current,
    essential: true,
  );

  @override
  Future<ZetaPluginHandle> activate(ZetaPluginContext context) async =>
      activateSynchronously(context);

  @override
  ZetaPluginHandle activateSynchronously(ZetaPluginContext context) =>
      _ClaudeCodeAgentProviderPluginHandle(
        AgentProviderPluginContribution(
          definition: claudeCodeAgentProviderDefinition,
          bundleFactory: _ClaudeCodeAgentProviderBundleFactory(
            sessionDecisionStoreFactory: sessionDecisionStoreFactory,
            hiddenThreadStore: hiddenThreadStore,
            metadataLoader: metadataLoader,
            textCatalog: textCatalog,
          ),
        ),
      );
}

final class _ClaudeCodeAgentProviderBundleFactory
    implements AgentProviderBundleFactory {
  const _ClaudeCodeAgentProviderBundleFactory({
    required this.sessionDecisionStoreFactory,
    required this.hiddenThreadStore,
    required this.metadataLoader,
    required this.textCatalog,
  });

  final ClaudeCodeSessionDecisionStoreFactory? sessionDecisionStoreFactory;
  final ClaudeCodeHiddenThreadStore? hiddenThreadStore;
  final ClaudeCodeCliMetadataLoader? metadataLoader;
  final AgentUiTextCatalog textCatalog;

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    if (config.kind != claudeCodeAgentProviderType) {
      throw UnsupportedError(
        'Claude Code plugin cannot create configuration ${config.id}',
      );
    }
    return createClaudeCodeBundle(
      config,
      metadataLoader: metadataLoader,
      sessionDecisionStoreFactory: sessionDecisionStoreFactory,
      hiddenThreadStore: hiddenThreadStore,
      textCatalog: textCatalog,
    );
  }
}

final class _ClaudeCodeAgentProviderPluginHandle implements ZetaPluginHandle {
  const _ClaudeCodeAgentProviderPluginHandle(this._contribution);

  final AgentProviderPluginContribution _contribution;

  @override
  List<ZetaPluginContribution> get contributions => <ZetaPluginContribution>[
    _contribution,
  ];

  @override
  Future<void> close() async {}
}
