import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

sealed class AgentProviderSettingsSliceIntent {
  const AgentProviderSettingsSliceIntent();
}

final class ProviderSettingsLoadRequested
    extends AgentProviderSettingsSliceIntent {
  const ProviderSettingsLoadRequested(this.operationId);

  final OperationId operationId;
}

final class ProviderSettingsLoaded extends AgentProviderSettingsSliceIntent {
  const ProviderSettingsLoaded(this.operationId, this.settings);

  final OperationId operationId;
  final AgentProviderSettings settings;
}

final class ProviderSettingsLoadFailed
    extends AgentProviderSettingsSliceIntent {
  const ProviderSettingsLoadFailed(this.operationId);

  final OperationId operationId;
}

final class ProviderConfigUpdateRequested
    extends AgentProviderSettingsSliceIntent {
  const ProviderConfigUpdateRequested(
    this.operationId,
    this.updated, {
    required this.restartProvider,
  });

  final OperationId operationId;
  final AgentProviderConfig updated;
  final bool restartProvider;
}

final class ProviderEnabledToggled extends AgentProviderSettingsSliceIntent {
  const ProviderEnabledToggled(this.operationId, this.providerId, this.enabled);

  final OperationId operationId;
  final String providerId;
  final bool enabled;
}

final class ActiveProviderSelected extends AgentProviderSettingsSliceIntent {
  const ActiveProviderSelected(this.operationId, this.providerId);

  final OperationId operationId;
  final String providerId;
}

final class ProviderModelSelectionPersistRequested
    extends AgentProviderSettingsSliceIntent {
  const ProviderModelSelectionPersistRequested(
    this.operationId,
    this.selection,
    this.preferences,
  );

  final OperationId operationId;
  final AgentModelSelection selection;
  final Map<String, AgentModelPreference> preferences;
}

final class ProviderPermissionOptionPersistRequested
    extends AgentProviderSettingsSliceIntent {
  const ProviderPermissionOptionPersistRequested(
    this.operationId,
    this.providerId,
    this.optionId,
  );

  final OperationId operationId;
  final String providerId;
  final String optionId;
}

final class ProviderSettingsPersisted extends AgentProviderSettingsSliceIntent {
  const ProviderSettingsPersisted(this.operationId);

  final OperationId operationId;
}

final class ProviderSettingsPersistFailed
    extends AgentProviderSettingsSliceIntent {
  const ProviderSettingsPersistFailed(this.operationId);

  final OperationId operationId;
}
