import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_state.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

/// 左栏 Agent 用量对 application workflow 暴露的稳定操作面。
abstract interface class AgentUsagePanelOperations {
  List<AgentUsagePanelProviderState> get providers;
  String? get preferredProviderId;
  String? get selectedProviderId;
  DateTime? get lastUpdated;
  String? get errorMessage;
  bool get hasDiscoveredProviders;
  bool get isLoading;
  AgentUsagePanelProviderState? get selectedProvider;
  List<AgentUsagePanelEntry> get entries;
  AgentUsagePanelEntry? get selectedEntry;

  Future<void> refresh({bool forceRefresh = true, bool showLoading = true});
  Future<void> synchronizeProviders({bool showLoading = false});
  void selectProvider(String providerId);
  void restorePreferredProviderId(String? providerId);
  void selectProviderFromTurn(String providerId);
}
