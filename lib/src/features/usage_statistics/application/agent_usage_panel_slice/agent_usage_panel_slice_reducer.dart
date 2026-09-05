import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_effect.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_intent.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_state.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

/// Agent Usage Panel 的纯同步 reducer。
Transition<AgentUsagePanelSliceState, AgentUsagePanelSliceEffect>
agentUsagePanelSliceReduce(
  AgentUsagePanelSliceState state,
  AgentUsagePanelSliceIntent intent,
) {
  switch (intent) {
    case AgentUsageDirectoryRequested():
      return Transition(
        state.copyWith(
          directoryOperationId: intent.operationId,
          directoryLoadingVisible:
              state.directoryLoadingVisible ||
              intent.showLoading ||
              state.providers.isEmpty,
          directoryError: null,
        ),
        <AgentUsagePanelSliceEffect>[
          DiscoverAgentUsageProvidersEffect(
            operationId: intent.operationId,
            showLoading: intent.showLoading,
          ),
        ],
      );

    case AgentUsageDirectoryLoaded():
      if (state.directoryOperationId != intent.operationId) {
        return Transition.none(state);
      }
      return _applyDirectory(state, intent.providers);

    case AgentUsageDirectoryFailed():
      if (state.directoryOperationId != intent.operationId) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          directoryOperationId: null,
          directoryLoadingVisible: false,
          directoryError: intent.message,
        ),
      );

    case AgentUsageProviderLoadRequested():
      final current = _stateFor(state.providers, intent.providerId);
      if (current == null) {
        return Transition.none(state);
      }
      final indicateLoading = intent.showLoading || current.entry == null;
      final operations = <String, OperationId>{...state.providerOperationIds}
        ..[intent.providerId] = intent.operationId;
      return Transition(
        state.copyWith(
          providers: _replaceProvider(
            state.providers,
            intent.providerId,
            AgentUsagePanelProviderState(
              provider: current.provider,
              entry: current.entry,
              status: indicateLoading
                  ? AgentUsagePanelProviderLoadStatus.loading
                  : AgentUsagePanelProviderLoadStatus.loaded,
            ),
          ),
          providerOperationIds: operations,
        ),
        <AgentUsagePanelSliceEffect>[
          LoadAgentUsageProviderEffect(
            operationId: intent.operationId,
            providerId: intent.providerId,
            forceRefresh: intent.forceRefresh,
          ),
        ],
      );

    case AgentUsageProviderLoaded():
      if (state.providerOperationIds[intent.providerId] != intent.operationId) {
        return Transition.none(state);
      }
      final current = _stateFor(state.providers, intent.providerId);
      if (current == null) {
        return Transition.none(state);
      }
      final operations = <String, OperationId>{...state.providerOperationIds}
        ..remove(intent.providerId);
      return Transition.stateOnly(
        state.copyWith(
          providers: _replaceProvider(
            state.providers,
            intent.providerId,
            AgentUsagePanelProviderState(
              provider: current.provider,
              entry: intent.result.entry,
              status: AgentUsagePanelProviderLoadStatus.loaded,
            ),
          ),
          providerOperationIds: operations,
          lastUpdated: intent.result.refreshedAt,
        ),
      );

    case AgentUsageProviderFailed():
      if (state.providerOperationIds[intent.providerId] != intent.operationId) {
        return Transition.none(state);
      }
      final current = _stateFor(state.providers, intent.providerId);
      if (current == null) {
        return Transition.none(state);
      }
      final operations = <String, OperationId>{...state.providerOperationIds}
        ..remove(intent.providerId);
      return Transition.stateOnly(
        state.copyWith(
          providers: _replaceProvider(
            state.providers,
            intent.providerId,
            AgentUsagePanelProviderState(
              provider: current.provider,
              entry: current.entry,
              status: AgentUsagePanelProviderLoadStatus.failed,
              loadError: intent.message,
            ),
          ),
          providerOperationIds: operations,
        ),
      );

    case AgentUsageProviderSelected():
      if (!_containsProvider(state.providers, intent.providerId)) {
        return Transition.none(state);
      }
      final changed =
          state.preferredProviderId != intent.providerId ||
          state.selectedProviderId != intent.providerId;
      if (!changed) {
        return Transition.none(state);
      }
      return Transition(
        state.copyWith(
          preferredProviderId: intent.providerId,
          selectedProviderId: intent.providerId,
        ),
        <AgentUsagePanelSliceEffect>[
          PersistAgentUsageSelectionEffect(intent.providerId),
        ],
      );

    case AgentUsagePreferredProviderRestored():
      final restored = state.copyWith(preferredProviderId: intent.providerId);
      if (!state.directoryDiscovered) {
        return Transition.stateOnly(restored);
      }
      return _resolveSelection(restored, persistFallback: true);

    case AgentUsageProviderSelectedFromTurn():
      if (state.preferredProviderId == intent.providerId) {
        return Transition.none(state);
      }
      if (!state.directoryDiscovered) {
        return Transition(
          state.copyWith(preferredProviderId: intent.providerId),
          <AgentUsagePanelSliceEffect>[
            PersistAgentUsageSelectionEffect(intent.providerId),
          ],
        );
      }
      if (_containsProvider(state.providers, intent.providerId)) {
        return Transition(
          state.copyWith(
            preferredProviderId: intent.providerId,
            selectedProviderId: intent.providerId,
          ),
          <AgentUsagePanelSliceEffect>[
            PersistAgentUsageSelectionEffect(intent.providerId),
          ],
        );
      }
      return _resolveSelection(
        state.copyWith(preferredProviderId: intent.providerId),
        persistFallback: true,
      );
  }
}

Transition<AgentUsagePanelSliceState, AgentUsagePanelSliceEffect>
_applyDirectory(
  AgentUsagePanelSliceState state,
  List<AgentUsagePanelProvider> providers,
) {
  final previous = <String, AgentUsagePanelProviderState>{
    for (final providerState in state.providers)
      providerState.provider.providerId: providerState,
  };
  final providerIds = providers.map((provider) => provider.providerId).toSet();
  final operations = <String, OperationId>{...state.providerOperationIds}
    ..removeWhere((providerId, _) => !providerIds.contains(providerId));
  final next = <AgentUsagePanelProviderState>[
    for (final provider in providers)
      AgentUsagePanelProviderState(
        provider: provider,
        entry: previous[provider.providerId]?.entry,
        status:
            previous[provider.providerId]?.status ??
            AgentUsagePanelProviderLoadStatus.notLoaded,
        loadError: previous[provider.providerId]?.loadError,
      ),
  ];
  return _resolveSelection(
    state.copyWith(
      providers: next,
      providerOperationIds: operations,
      directoryDiscovered: true,
      directoryOperationId: null,
      directoryLoadingVisible: false,
      directoryError: null,
    ),
    persistFallback: true,
  );
}

Transition<AgentUsagePanelSliceState, AgentUsagePanelSliceEffect>
_resolveSelection(
  AgentUsagePanelSliceState state, {
  required bool persistFallback,
}) {
  final preferred = state.preferredProviderId;
  if (preferred != null && _containsProvider(state.providers, preferred)) {
    return Transition.stateOnly(state.copyWith(selectedProviderId: preferred));
  }
  final fallback = state.providers.isEmpty
      ? null
      : state.providers.first.provider.providerId;
  final preferenceChanged = fallback != preferred;
  final next = state.copyWith(
    preferredProviderId: fallback,
    selectedProviderId: fallback,
  );
  if (!persistFallback || !preferenceChanged) {
    return Transition.stateOnly(next);
  }
  return Transition(next, <AgentUsagePanelSliceEffect>[
    PersistAgentUsageSelectionEffect(fallback),
  ]);
}

bool _containsProvider(
  List<AgentUsagePanelProviderState> providers,
  String providerId,
) => providers.any((state) => state.provider.providerId == providerId);

AgentUsagePanelProviderState? _stateFor(
  List<AgentUsagePanelProviderState> providers,
  String providerId,
) {
  for (final state in providers) {
    if (state.provider.providerId == providerId) {
      return state;
    }
  }
  return null;
}

List<AgentUsagePanelProviderState> _replaceProvider(
  List<AgentUsagePanelProviderState> providers,
  String providerId,
  AgentUsagePanelProviderState replacement,
) {
  return <AgentUsagePanelProviderState>[
    for (final state in providers)
      if (state.provider.providerId == providerId) replacement else state,
  ];
}
