import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_effect.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_intent.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_state.dart';

/// Provider settings 的纯同步 reducer（G3）。
Transition<AgentProviderSettingsSliceState, AgentProviderSettingsSliceEffect>
agentProviderSettingsSliceReduce(
  AgentProviderSettingsSliceState state,
  AgentProviderSettingsSliceIntent intent,
) {
  switch (intent) {
    case ProviderSettingsLoadRequested():
      return Transition(
        state.copyWith(
          loading: true,
          loadOperationId: intent.operationId,
          lastFailure: null,
        ),
        <AgentProviderSettingsSliceEffect>[
          ProviderSettingsLoadEffect(intent.operationId),
        ],
      );

    case ProviderSettingsLoaded():
      if (state.loadOperationId != intent.operationId) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          settings: intent.settings,
          loading: false,
          loadOperationId: null,
          lastFailure: null,
        ),
      );

    case ProviderSettingsLoadFailed():
      if (state.loadOperationId != intent.operationId) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          loading: false,
          loadOperationId: null,
          lastFailure: AgentProviderSettingsSliceFailure(
            kind: AgentProviderSettingsFailureKind.load,
            operationId: intent.operationId,
          ),
        ),
      );

    case ProviderConfigUpdateRequested():
      final previous = _providerById(state.settings, intent.updated.id);
      final providers = <AgentProviderConfig>[
        for (final provider in state.settings.providers)
          if (provider.id == intent.updated.id) intent.updated else provider,
      ];
      if (!providers.any((provider) => provider.id == intent.updated.id)) {
        providers.add(intent.updated);
      }
      return _persist(
        state,
        operationId: intent.operationId,
        settings: AgentProviderSettings(
          providers: List<AgentProviderConfig>.unmodifiable(providers),
          activeProviderId: state.settings.activeProviderId,
        ),
        previousConfig: previous,
        updatedConfig: intent.updated,
        restartProvider: intent.restartProvider,
      );

    case ProviderEnabledToggled():
      final current = _providerById(state.settings, intent.providerId);
      if (current == null) {
        return Transition.none(state);
      }
      if (current.enabled == intent.enabled) {
        return Transition.none(state);
      }
      final updated = current.copyWith(enabled: intent.enabled);
      final providers = <AgentProviderConfig>[
        for (final provider in state.settings.providers)
          if (provider.id == updated.id) updated else provider,
      ];
      if (!providers.any((provider) => provider.id == updated.id)) {
        providers.add(updated);
      }
      var activeProviderId = state.settings.activeProviderId;
      if (!intent.enabled && activeProviderId == updated.id) {
        for (final provider in providers) {
          if (provider.enabled && provider.id != updated.id) {
            activeProviderId = provider.id;
            break;
          }
        }
      }
      return _persist(
        state,
        operationId: intent.operationId,
        settings: AgentProviderSettings(
          providers: List<AgentProviderConfig>.unmodifiable(providers),
          activeProviderId: activeProviderId,
        ),
        previousConfig: current,
        updatedConfig: updated,
        restartProvider: !intent.enabled,
      );

    case ActiveProviderSelected():
      if (state.settings.activeProviderId == intent.providerId &&
          state.settings.activeProvider.id == intent.providerId) {
        return Transition.none(state);
      }
      return _persist(
        state,
        operationId: intent.operationId,
        settings: state.settings.copyWith(activeProviderId: intent.providerId),
      );

    case ProviderModelSelectionPersistRequested():
      final providerId = state.settings.activeProvider.id;
      final providers = <AgentProviderConfig>[
        for (final provider in state.settings.providers)
          if (provider.id == providerId)
            provider.withModelConfiguration(
              selection: intent.selection,
              preferences: intent.preferences,
            )
          else
            provider,
      ];
      return _persist(
        state,
        operationId: intent.operationId,
        settings: AgentProviderSettings(
          providers: List<AgentProviderConfig>.unmodifiable(providers),
          activeProviderId: state.settings.activeProviderId,
        ),
      );

    case ProviderPermissionOptionPersistRequested():
      final providers = <AgentProviderConfig>[
        for (final provider in state.settings.providers)
          if (provider.id == intent.providerId)
            provider.withPermissionPreference(intent.optionId)
          else
            provider,
      ];
      return _persist(
        state,
        operationId: intent.operationId,
        settings: AgentProviderSettings(
          providers: List<AgentProviderConfig>.unmodifiable(providers),
          activeProviderId: state.settings.activeProviderId,
        ),
      );

    case ProviderSettingsPersisted():
      if (state.persistOperationId != intent.operationId) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(persistOperationId: null, lastFailure: null),
      );

    case ProviderSettingsPersistFailed():
      if (state.persistOperationId != intent.operationId) {
        return Transition.none(state);
      }
      // 保留内存候选值，匹配旧 controller 在 save 失败后的 getter 语义。
      return Transition.stateOnly(
        state.copyWith(
          persistOperationId: null,
          lastFailure: AgentProviderSettingsSliceFailure(
            kind: AgentProviderSettingsFailureKind.persist,
            operationId: intent.operationId,
          ),
        ),
      );
  }
}

Transition<AgentProviderSettingsSliceState, AgentProviderSettingsSliceEffect>
_persist(
  AgentProviderSettingsSliceState state, {
  required OperationId operationId,
  required AgentProviderSettings settings,
  AgentProviderConfig? previousConfig,
  AgentProviderConfig? updatedConfig,
  bool restartProvider = false,
}) {
  return Transition(
    state.copyWith(
      settings: settings,
      persistOperationId: operationId,
      lastFailure: null,
    ),
    <AgentProviderSettingsSliceEffect>[
      ProviderSettingsPersistEffect(
        operationId: operationId,
        settings: settings,
        previousConfig: previousConfig,
        updatedConfig: updatedConfig,
        restartProvider: restartProvider,
      ),
    ],
  );
}

AgentProviderConfig? _providerById(
  AgentProviderSettings settings,
  String providerId,
) {
  for (final provider in settings.providers) {
    if (provider.id == providerId) {
      return provider;
    }
  }
  return null;
}
