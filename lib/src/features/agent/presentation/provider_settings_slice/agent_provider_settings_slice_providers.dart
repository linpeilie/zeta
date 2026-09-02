import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_store.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_state.dart';

/// Provider Settings application owner 的只读 presentation selectors。

final agentProviderSettingsValueProvider = Provider<AgentProviderSettings>(
  (ref) => ref.watch(
    agentProviderSettingsSliceProvider.select((state) => state.settings),
  ),
  name: 'agentProviderSettingsValue',
);

final activeAgentProviderConfigProvider = Provider<AgentProviderConfig>(
  (ref) => ref.watch(
    agentProviderSettingsSliceProvider.select(
      AgentProviderSettingsSelectors.activeProviderConfig,
    ),
  ),
  name: 'activeAgentProviderConfig',
);

final enabledAgentProviderConfigsProvider = Provider<List<AgentProviderConfig>>(
  (ref) => ref.watch(
    agentProviderSettingsSliceProvider.select(
      AgentProviderSettingsSelectors.enabledProviders,
    ),
  ),
  name: 'enabledAgentProviderConfigs',
);
