import 'src/management/contribution.dart';
import 'src/usage/contribution.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

import 'package:zeta_agent_provider_codex/src/codex_static_capabilities.dart';
import 'package:zeta_agent_provider_codex/src/codex_provider_bundle.dart';

/// Codex 内置配置的稳定 id。
const String defaultAgentProviderId = 'codex';

/// providers.json 使用的 Codex 协议域字符串。
const AgentProviderTypeId codexAgentProviderType = AgentProviderTypeId(
  'codexAppServer',
);

/// 默认 Codex CLI 配置。
const AgentProviderConfig defaultCodexAgentProviderConfig = AgentProviderConfig(
  id: defaultAgentProviderId,
  displayName: 'Codex',
  kind: codexAgentProviderType,
  command: 'codex',
  arguments: <String>['app-server'],
);

/// Codex 插件拥有的静态 definition。
const AgentProviderDefinition codexAgentProviderDefinition =
    AgentProviderDefinition(
      providerId: defaultAgentProviderId,
      providerType: codexAgentProviderType,
      defaultConfig: defaultCodexAgentProviderConfig,
      staticCapabilities: codexStaticCapabilities,
      modelCatalogSourceLabel: 'Codex app-server',
      metricLabel: ZetaMetricLabel.constant('codex'),
      isDefault: true,
    );

/// Codex app-server 的显式 compile-time Provider 插件。
final class CodexAgentProviderPlugin implements ZetaSynchronousPluginFactory {
  CodexAgentProviderPlugin({
    this.textCatalog = const FallbackAgentUiTextCatalog(),
  });

  static const String pluginId = 'zeta.agent.codex';

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
      _CodexAgentProviderPluginHandle(
        AgentProviderPluginContribution(
          definition: codexAgentProviderDefinition,
          bundleFactory: _CodexAgentProviderBundleFactory(textCatalog),
        ),
      );
}

final class _CodexAgentProviderBundleFactory
    implements AgentProviderBundleFactory {
  const _CodexAgentProviderBundleFactory(this.textCatalog);

  final AgentUiTextCatalog textCatalog;

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    if (config.kind != codexAgentProviderType) {
      throw UnsupportedError(
        'Codex plugin cannot create configuration ${config.id}',
      );
    }
    return createCodexBundle(config, textCatalog: textCatalog);
  }
}

final class _CodexAgentProviderPluginHandle implements ZetaPluginHandle {
  const _CodexAgentProviderPluginHandle(this._contribution);

  final AgentProviderPluginContribution _contribution;

  @override
  List<ZetaPluginContribution> get contributions => <ZetaPluginContribution>[
    _contribution,
    createCodexManagementContribution(),
    createCodexUsageContribution(),
  ];

  @override
  Future<void> close() async {}
}
