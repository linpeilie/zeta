import 'package:meta/meta.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

/// 单个 Provider 的侧栏加载阶段。
enum AgentUsagePanelProviderLoadStatus { notLoaded, loading, loaded, failed }

/// 单个 Provider 在 Agent 用量面板中的不可变加载状态。
@immutable
final class AgentUsagePanelProviderState {
  const AgentUsagePanelProviderState({
    required this.provider,
    required this.status,
    this.entry,
    this.loadError,
  });

  final AgentUsagePanelProvider provider;

  /// 最近一次成功数据；刷新失败或刷新期间继续保留。
  final AgentUsagePanelEntry? entry;

  final AgentUsagePanelProviderLoadStatus status;

  /// 仅影响当前 Provider 的加载错误。
  final String? loadError;

  bool get isLoading => status == AgentUsagePanelProviderLoadStatus.loading;
}

const Object _agentUsagePanelUnset = Object();

/// Agent Usage Panel 的不可变 application state。
@immutable
final class AgentUsagePanelSliceState {
  AgentUsagePanelSliceState({
    List<AgentUsagePanelProviderState> providers =
        const <AgentUsagePanelProviderState>[],
    this.preferredProviderId,
    this.selectedProviderId,
    this.lastUpdated,
    this.directoryError,
    this.directoryOperationId,
    Map<String, OperationId> providerOperationIds =
        const <String, OperationId>{},
    this.directoryDiscovered = false,
    this.directoryLoadingVisible = false,
  }) : providers = List<AgentUsagePanelProviderState>.unmodifiable(providers),
       providerOperationIds = Map<String, OperationId>.unmodifiable(
         providerOperationIds,
       );

  final List<AgentUsagePanelProviderState> providers;
  final String? preferredProviderId;
  final String? selectedProviderId;
  final DateTime? lastUpdated;
  final String? directoryError;
  final OperationId? directoryOperationId;
  final Map<String, OperationId> providerOperationIds;
  final bool directoryDiscovered;
  final bool directoryLoadingVisible;

  AgentUsagePanelSliceState copyWith({
    List<AgentUsagePanelProviderState>? providers,
    Object? preferredProviderId = _agentUsagePanelUnset,
    Object? selectedProviderId = _agentUsagePanelUnset,
    Object? lastUpdated = _agentUsagePanelUnset,
    Object? directoryError = _agentUsagePanelUnset,
    Object? directoryOperationId = _agentUsagePanelUnset,
    Map<String, OperationId>? providerOperationIds,
    bool? directoryDiscovered,
    bool? directoryLoadingVisible,
  }) {
    return AgentUsagePanelSliceState(
      providers: providers ?? this.providers,
      preferredProviderId: identical(preferredProviderId, _agentUsagePanelUnset)
          ? this.preferredProviderId
          : preferredProviderId as String?,
      selectedProviderId: identical(selectedProviderId, _agentUsagePanelUnset)
          ? this.selectedProviderId
          : selectedProviderId as String?,
      lastUpdated: identical(lastUpdated, _agentUsagePanelUnset)
          ? this.lastUpdated
          : lastUpdated as DateTime?,
      directoryError: identical(directoryError, _agentUsagePanelUnset)
          ? this.directoryError
          : directoryError as String?,
      directoryOperationId:
          identical(directoryOperationId, _agentUsagePanelUnset)
          ? this.directoryOperationId
          : directoryOperationId as OperationId?,
      providerOperationIds: providerOperationIds ?? this.providerOperationIds,
      directoryDiscovered: directoryDiscovered ?? this.directoryDiscovered,
      directoryLoadingVisible:
          directoryLoadingVisible ?? this.directoryLoadingVisible,
    );
  }
}

/// Agent Usage Panel 的纯 selector。
abstract final class AgentUsagePanelSliceSelectors {
  static AgentUsagePanelProviderState? selectedProvider(
    AgentUsagePanelSliceState state,
  ) {
    if (state.providers.isEmpty) {
      return null;
    }
    for (final providerState in state.providers) {
      if (providerState.provider.providerId == state.selectedProviderId) {
        return providerState;
      }
    }
    return state.providers.first;
  }

  static bool isLoading(AgentUsagePanelSliceState state) {
    return state.directoryLoadingVisible ||
        (selectedProvider(state)?.isLoading ?? false);
  }

  static List<AgentUsagePanelEntry> entries(AgentUsagePanelSliceState state) {
    return List<AgentUsagePanelEntry>.unmodifiable(
      state.providers
          .map((providerState) => providerState.entry)
          .whereType<AgentUsagePanelEntry>(),
    );
  }
}
