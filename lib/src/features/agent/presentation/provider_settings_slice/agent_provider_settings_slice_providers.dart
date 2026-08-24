import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_state.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_store.dart';

/// app 组合层注入的 Provider settings store。
///
/// store 的生命周期归组合层；缺失覆盖表示根接线不完整，必须立即失败，不能
/// 伪造一份默认 Provider 设置掩盖错误。
final agentProviderSettingsSliceStoreProvider =
    Provider<AgentProviderSettingsSliceStore>(
      (ref) => throw StateError('Provider settings slice is not installed'),
    );

/// Provider settings store 的只读 Riverpod 镜像。
final agentProviderSettingsSliceProvider =
    NotifierProvider<
      AgentProviderSettingsSliceNotifier,
      AgentProviderSettingsSliceState
    >(
      AgentProviderSettingsSliceNotifier.new,
      name: 'agentProviderSettingsSlice',
    );

final class AgentProviderSettingsSliceNotifier
    extends Notifier<AgentProviderSettingsSliceState> {
  @override
  AgentProviderSettingsSliceState build() {
    final store = ref.watch(agentProviderSettingsSliceStoreProvider);
    final unsubscribe = store.subscribe(() => state = store.state);
    ref.onDispose(unsubscribe);
    return store.state;
  }
}

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
