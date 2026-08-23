import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

sealed class AgentUsagePanelSliceIntent {
  const AgentUsagePanelSliceIntent();
}

final class AgentUsageDirectoryRequested extends AgentUsagePanelSliceIntent {
  const AgentUsageDirectoryRequested({
    required this.operationId,
    required this.showLoading,
  });

  final OperationId operationId;
  final bool showLoading;
}

final class AgentUsageDirectoryLoaded extends AgentUsagePanelSliceIntent {
  const AgentUsageDirectoryLoaded({
    required this.operationId,
    required this.providers,
  });

  final OperationId operationId;
  final List<AgentUsagePanelProvider> providers;
}

final class AgentUsageDirectoryFailed extends AgentUsagePanelSliceIntent {
  const AgentUsageDirectoryFailed({
    required this.operationId,
    required this.message,
  });

  final OperationId operationId;
  final String message;
}

final class AgentUsageProviderLoadRequested extends AgentUsagePanelSliceIntent {
  const AgentUsageProviderLoadRequested({
    required this.operationId,
    required this.providerId,
    required this.forceRefresh,
    required this.showLoading,
  });

  final OperationId operationId;
  final String providerId;
  final bool forceRefresh;
  final bool showLoading;
}

final class AgentUsageProviderLoaded extends AgentUsagePanelSliceIntent {
  const AgentUsageProviderLoaded({
    required this.operationId,
    required this.providerId,
    required this.result,
  });

  final OperationId operationId;
  final String providerId;
  final AgentUsagePanelProviderResult result;
}

final class AgentUsageProviderFailed extends AgentUsagePanelSliceIntent {
  const AgentUsageProviderFailed({
    required this.operationId,
    required this.providerId,
    required this.message,
  });

  final OperationId operationId;
  final String providerId;
  final String message;
}

final class AgentUsageProviderSelected extends AgentUsagePanelSliceIntent {
  const AgentUsageProviderSelected(this.providerId);

  final String providerId;
}

final class AgentUsagePreferredProviderRestored
    extends AgentUsagePanelSliceIntent {
  const AgentUsagePreferredProviderRestored(this.providerId);

  final String? providerId;
}

final class AgentUsageProviderSelectedFromTurn
    extends AgentUsagePanelSliceIntent {
  const AgentUsageProviderSelectedFromTurn(this.providerId);

  final String providerId;
}
