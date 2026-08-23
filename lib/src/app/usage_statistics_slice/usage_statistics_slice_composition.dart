import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/app/usage_statistics_slice/usage_statistics_slice_runner.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_state.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_store.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_query_service.dart';
import 'package:zeta/src/features/usage_statistics/application/query_agent_usage_panel_repository.dart';
import 'package:zeta/src/features/usage_statistics/application/query_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_state.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_store.dart';
import 'package:zeta/src/features/usage_statistics/data/built_in_agent_token_usage_source_registry.dart';
import 'package:zeta/src/features/usage_statistics/data/global_runtime_agent_usage_quota_source.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

/// Phase 3 第 3 批 3b 的 app 组合。
///
/// QueryService/repository/source registry 的行为不变，只把创建与释放从 Shell
/// 上移；两个 store 分别是完整统计页与左栏的唯一 owner。
final class UsageStatisticsSliceComposition {
  UsageStatisticsSliceComposition._({
    required this.usageStatisticsStore,
    required this.agentUsagePanelStore,
    required this._usageRunner,
    required this._panelRunner,
  });

  final UsageStatisticsSliceStore usageStatisticsStore;
  final AgentUsagePanelSliceStore agentUsagePanelStore;
  final UsageStatisticsSliceRunnerAdapter _usageRunner;
  final AgentUsagePanelSliceRunnerAdapter _panelRunner;

  factory UsageStatisticsSliceComposition.create({
    required AgentProviderSettingsPort providerSettings,
    required AgentProviderRuntimeRegistry runtimeRegistry,
    required UsageStatisticsPartitionStore partitionStore,
    required UsageStatisticsTextCatalog textCatalog,
    AgentUsagePanelRepository? agentUsagePanelRepository,
    DateTime Function()? clock,
  }) {
    final now = clock ?? DateTime.now;
    final queryService = AgentUsageQueryService(
      () async {
        await providerSettings.loadSettings();
        return providerSettings.enabledProviders;
      },
      GlobalRuntimeAgentUsageQuotaSource(
        AgentProviderGlobalRuntime(runtimeRegistry: runtimeRegistry),
      ),
      BuiltInAgentTokenUsageSourceRegistry(partitionStore),
      clock: now,
    );
    final usageRepository = QueryUsageStatisticsRepository(
      queryService,
      clock: now,
    );
    final panelRepository =
        agentUsagePanelRepository ??
        QueryAgentUsagePanelRepository(queryService, clock: now);
    final usageRunner = UsageStatisticsSliceRunnerAdapter(
      repository: usageRepository,
      textCatalog: textCatalog,
    );
    final panelRunner = AgentUsagePanelSliceRunnerAdapter(
      repository: panelRepository,
      textCatalog: textCatalog,
    );
    final usageStore = UsageStatisticsSliceStore(
      initialState: const UsageStatisticsSliceState(),
      effectRunner: usageRunner,
      clock: now,
    );
    final panelStore = AgentUsagePanelSliceStore(
      initialState: AgentUsagePanelSliceState(),
      effectRunner: panelRunner,
    );
    usageRunner.store = usageStore;
    panelRunner.store = panelStore;
    return UsageStatisticsSliceComposition._(
      usageStatisticsStore: usageStore,
      agentUsagePanelStore: panelStore,
      usageRunner: usageRunner,
      panelRunner: panelRunner,
    );
  }

  /// Shell 恢复完成后绑定 Workbench layout 回写；组合仍持有 runner 生命周期。
  void bindSelectionPersistence(void Function(String? providerId)? handler) {
    _panelRunner.selectionPersistenceHandler = handler;
  }

  void dispose() {
    usageStatisticsStore.close();
    agentUsagePanelStore.close();
    _usageRunner.close();
    _panelRunner.close();
  }
}
