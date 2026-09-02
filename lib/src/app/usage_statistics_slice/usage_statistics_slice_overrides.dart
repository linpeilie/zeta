import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/app/localization/zeta_text_catalog_providers.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/app/usage_statistics_slice/usage_statistics_providers.dart';
import 'package:zeta/src/app/usage_statistics_slice/usage_statistics_slice_runner.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_store.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_store.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_query_service.dart';
import 'package:zeta/src/features/usage_statistics/application/query_agent_usage_panel_repository.dart';
import 'package:zeta/src/features/usage_statistics/application/query_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_store.dart';
import 'package:zeta/src/features/usage_statistics/data/built_in_agent_token_usage_source_registry.dart';
import 'package:zeta/src/features/usage_statistics/data/global_runtime_agent_usage_quota_source.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';

/// 两个统计切片共享的查询服务。
///
/// 共享是口径要求：服务内部带历史聚合缓存，完整统计页和侧栏若各建一份，会产生
/// 两套缓存与刷新时序。Provider 私有来源仍只存在于 data 实现中。
final _agentUsageQueryServiceProvider = Provider<AgentUsageQueryService>((ref) {
  final providerSettings = ref.watch(
    agentProviderSettingsSliceProvider.notifier,
  );
  return AgentUsageQueryService(
    () async {
      await providerSettings.loadSettings();
      return providerSettings.enabledProviders;
    },
    GlobalRuntimeAgentUsageQuotaSource(
      AgentProviderGlobalRuntime(
        runtimeRegistry: ref.watch(agentProviderRuntimeRegistryProvider),
      ),
    ),
    BuiltInAgentTokenUsageSourceRegistry(
      ref.watch(usageStatisticsPartitionStoreProvider),
    ),
  );
}, name: 'agentUsageQueryService');

final _usageStatisticsRepositoryProvider = Provider<UsageStatisticsRepository>(
  (ref) => QueryUsageStatisticsRepository(
    ref.watch(_agentUsageQueryServiceProvider),
  ),
  name: 'usageStatisticsRepository',
);

final _resolvedAgentUsagePanelRepositoryProvider =
    Provider<AgentUsagePanelRepository>(
      (ref) =>
          ref.watch(agentUsagePanelRepositoryProvider) ??
          QueryAgentUsagePanelRepository(
            ref.watch(_agentUsageQueryServiceProvider),
          ),
      name: 'resolvedAgentUsagePanelRepository',
    );

/// Usage Statistics 两个 app-session Notifier 的生产装配。
List<Override> usageStatisticsSliceOverrides() {
  return <Override>[
    usageStatisticsSliceDependenciesProvider.overrideWith((ref) {
      return UsageStatisticsSliceDependencies(
        repository: ref.watch(_usageStatisticsRepositoryProvider),
      );
    }),
    usageStatisticsSliceEffectRunnerFactoryProvider.overrideWith((ref) {
      final repository = ref.watch(_usageStatisticsRepositoryProvider);
      final textCatalog = ref.watch(usageStatisticsTextCatalogProvider);
      return (notifier) => UsageStatisticsSliceRunnerAdapter(
        repository: repository,
        textCatalog: textCatalog,
        notifier: notifier,
      );
    }),
    agentUsagePanelSliceDependenciesProvider.overrideWith((ref) {
      return AgentUsagePanelSliceDependencies(
        repository: ref.watch(_resolvedAgentUsagePanelRepositoryProvider),
      );
    }),
    agentUsagePanelSliceEffectRunnerFactoryProvider.overrideWith((ref) {
      final repository = ref.watch(_resolvedAgentUsagePanelRepositoryProvider);
      final textCatalog = ref.watch(usageStatisticsTextCatalogProvider);
      final ideSession = ref.watch(ideSessionSliceProvider.notifier);
      return (notifier) => AgentUsagePanelSliceRunnerAdapter(
        repository: repository,
        textCatalog: textCatalog,
        notifier: notifier,
        persistSelection: (providerId) {
          final current = ideSession.state.workbenchLayout;
          final next = current.copyWith(
            selectedAgentUsageProviderId: providerId,
          );
          if (next != current) {
            ideSession.setWorkbenchLayout(next);
          }
        },
      );
    }),
  ];
}
