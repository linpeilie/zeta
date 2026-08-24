import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

import 'package:zeta_agent_providers/src/agent_provider_definition.dart';
import 'package:zeta_agent_providers/src/agent_provider_plugin_contribution.dart';
import 'package:zeta_agent_providers/src/agent_provider_static_capabilities.dart';
import 'package:zeta_agent_providers/src/native_agent_provider_bundles.dart';

/// Grok 内置配置的稳定 id。
const String grokAgentProviderId = 'grok';

/// providers.json 使用的 Grok ACP 协议域字符串。
const AgentProviderTypeId grokAgentProviderType = AgentProviderTypeId('acp');

/// 默认 Grok CLI ACP stdio 配置。
const AgentProviderConfig defaultGrokAgentProviderConfig = AgentProviderConfig(
  id: grokAgentProviderId,
  displayName: 'Grok',
  kind: grokAgentProviderType,
  command: 'grok',
  arguments: <String>['agent', 'stdio'],
);

/// Grok 插件拥有的静态 definition。
const AgentProviderDefinition grokAgentProviderDefinition =
    AgentProviderDefinition(
      providerId: grokAgentProviderId,
      providerType: grokAgentProviderType,
      defaultConfig: defaultGrokAgentProviderConfig,
      staticCapabilities: AgentProviderStaticCapabilities.grokAcp,
      modelCatalogSourceLabel: 'Grok ACP',
    );

/// Grok ACP 的显式 compile-time Provider 插件。
final class GrokAgentProviderPlugin implements ZetaSynchronousPluginFactory {
  GrokAgentProviderPlugin({
    this.textCatalog = const FallbackAgentUiTextCatalog(),
  });

  static const String pluginId = 'zeta.agent.grok';

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
      _GrokAgentProviderPluginHandle(
        AgentProviderPluginContribution(
          definition: grokAgentProviderDefinition,
          bundleFactory: _GrokAgentProviderBundleFactory(textCatalog),
        ),
      );
}

final class _GrokAgentProviderBundleFactory
    implements AgentProviderBundleFactory {
  const _GrokAgentProviderBundleFactory(this.textCatalog);

  final AgentUiTextCatalog textCatalog;

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    if (config.kind != grokAgentProviderType) {
      throw UnsupportedError(
        'Grok plugin cannot create configuration ${config.id}',
      );
    }
    return createGrokBundle(config, textCatalog: textCatalog);
  }
}

final class _GrokAgentProviderPluginHandle implements ZetaPluginHandle {
  const _GrokAgentProviderPluginHandle(this._contribution);

  final AgentProviderPluginContribution _contribution;

  @override
  List<ZetaPluginContribution> get contributions => <ZetaPluginContribution>[
    _contribution,
  ];

  @override
  Future<void> close() async {}
}
