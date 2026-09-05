import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/app/usage_statistics_slice/usage_statistics_slice_runner.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_state.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_store.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_state.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

final Expando<ProviderContainer> _usageContainers = Expando<ProviderContainer>(
  'usageStatisticsTestContainer',
);
final Expando<ProviderContainer> _panelContainers = Expando<ProviderContainer>(
  'agentUsagePanelTestContainer',
);

/// Usage Statistics application notifier 的容器化测试夹具。
final class UsageStatisticsTestBindings {
  UsageStatisticsTestBindings({
    required UsageStatisticsRepository repository,
    UsageStatisticsSliceState initialState = const UsageStatisticsSliceState(),
    UsageStatisticsTextCatalog textCatalog =
        const FallbackUsageStatisticsTextCatalog(),
    DateTime Function()? clock,
    OperationIdGenerator? operationIdGenerator,
  }) {
    container = ProviderContainer(
      overrides: [
        usageStatisticsSliceDependenciesProvider.overrideWithValue(
          UsageStatisticsSliceDependencies(
            repository: repository,
            initialState: initialState,
            clock: clock,
            operationIdGenerator: operationIdGenerator,
          ),
        ),
        usageStatisticsSliceEffectRunnerFactoryProvider.overrideWithValue(
          (notifier) => UsageStatisticsSliceRunnerAdapter(
            repository: repository,
            textCatalog: textCatalog,
            notifier: notifier,
          ),
        ),
      ],
    );
    notifier = container.read(usageStatisticsSliceProvider.notifier);
    _usageContainers[notifier] = container;
  }

  late final ProviderContainer container;
  late final UsageStatisticsSliceNotifier notifier;

  void dispose() => container.dispose();
}

/// Agent Usage Panel application notifier 的容器化测试夹具。
final class AgentUsagePanelTestBindings {
  AgentUsagePanelTestBindings({
    required AgentUsagePanelRepository repository,
    AgentUsagePanelSliceState? initialState,
    UsageStatisticsTextCatalog textCatalog =
        const FallbackUsageStatisticsTextCatalog(),
    void Function(String? providerId)? onSelectionChanged,
    OperationIdGenerator? directoryOperationIdGenerator,
    OperationIdGenerator Function(String providerId)?
    providerOperationIdGenerator,
  }) {
    container = ProviderContainer(
      overrides: [
        agentUsagePanelSliceDependenciesProvider.overrideWithValue(
          AgentUsagePanelSliceDependencies(
            repository: repository,
            initialState: initialState,
            directoryOperationIdGenerator: directoryOperationIdGenerator,
            providerOperationIdGenerator: providerOperationIdGenerator,
          ),
        ),
        agentUsagePanelSliceEffectRunnerFactoryProvider.overrideWithValue(
          (notifier) => AgentUsagePanelSliceRunnerAdapter(
            repository: repository,
            textCatalog: textCatalog,
            notifier: notifier,
            persistSelection: onSelectionChanged ?? (_) {},
          ),
        ),
      ],
    );
    notifier = container.read(agentUsagePanelSliceProvider.notifier);
    _panelContainers[notifier] = container;
  }

  late final ProviderContainer container;
  late final AgentUsagePanelSliceNotifier notifier;

  void dispose() => container.dispose();
}

extension UsageStatisticsNotifierTestBinding on UsageStatisticsSliceNotifier {
  ProviderContainer get testContainer =>
      _usageContainers[this] ??
      (throw StateError('Usage Statistics notifier has no test container'));

  void dispose() => testContainer.dispose();
}

extension AgentUsagePanelNotifierTestBinding on AgentUsagePanelSliceNotifier {
  ProviderContainer get testContainer =>
      _panelContainers[this] ??
      (throw StateError('Agent Usage Panel notifier has no test container'));

  void dispose() => testContainer.dispose();
}
