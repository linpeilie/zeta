import 'package:zeta_foundation/zeta_foundation.dart';

/// Agent Usage Panel 的副作用描述。
sealed class AgentUsagePanelSliceEffect {
  const AgentUsagePanelSliceEffect();
}

final class DiscoverAgentUsageProvidersEffect
    extends AgentUsagePanelSliceEffect {
  const DiscoverAgentUsageProvidersEffect({
    required this.operationId,
    required this.showLoading,
  });

  final OperationId operationId;
  final bool showLoading;
}

final class LoadAgentUsageProviderEffect extends AgentUsagePanelSliceEffect {
  const LoadAgentUsageProviderEffect({
    required this.operationId,
    required this.providerId,
    required this.forceRefresh,
  });

  final OperationId operationId;
  final String providerId;
  final bool forceRefresh;
}

/// 将统计选择回写 Workbench layout；恢复 seed 本身不产生此 effect。
final class PersistAgentUsageSelectionEffect
    extends AgentUsagePanelSliceEffect {
  const PersistAgentUsageSelectionEffect(this.providerId);

  final String? providerId;
}
