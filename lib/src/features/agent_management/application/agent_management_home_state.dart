import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'agent_management_agent_view.dart';
import 'agent_management_detection_state.dart';
import 'agent_management_runtime_facts.dart';
import 'agent_management_slice/agent_management_slice_state.dart';
import 'agent_management_slice/agent_management_slice_notifier.dart';

/// 首页 Provider 的归一化状态。
enum HomeProviderStatus {
  available,
  running,
  disabled,
  needsLogin,
  error,
  detecting,
}

/// 首页消费的 Provider 轻量摘要。
final class HomeProviderSummary {
  const HomeProviderSummary({
    required this.id,
    required this.displayName,
    required this.vendor,
    required this.status,
    this.version,
    this.isStale = false,
    HomeProviderStatus? availabilityStatus,
  }) : availabilityStatus = availabilityStatus ?? status;

  factory HomeProviderSummary.fromAgentView(
    AgentManagementAgentView agent, {
    bool isStale = false,
  }) {
    return HomeProviderSummary(
      id: agent.definition.id,
      isStale: isStale,
      displayName: agent.definition.displayName,
      vendor: agent.definition.vendor,
      version: agent.currentVersion,
      status: _resolveProviderStatus(agent),
      availabilityStatus: _resolveProviderStatus(agent, ignoreRuntime: true),
    );
  }

  final String id;
  final String displayName;
  final String vendor;
  final String? version;
  final bool isStale;
  final HomeProviderStatus status;
  final HomeProviderStatus availabilityStatus;

  /// 检测缓存只提供可用性；实时运行状态始终来自同一管理摘要。
  HomeProviderSummary withRuntime(
    AgentManagementProviderRuntimeSummary? runtime,
  ) {
    if (runtime == null) return this;
    final liveStatus = switch (runtime.state) {
      AgentRuntimeState.running ||
      AgentRuntimeState.starting => HomeProviderStatus.running,
      AgentRuntimeState.error ||
      AgentRuntimeState.unavailable => HomeProviderStatus.error,
      AgentRuntimeState.disabled => HomeProviderStatus.disabled,
      _ =>
        runtime.enabled
            ? (availabilityStatus == HomeProviderStatus.disabled
                  ? HomeProviderStatus.available
                  : availabilityStatus)
            : HomeProviderStatus.disabled,
    };
    return HomeProviderSummary(
      id: id,
      isStale: isStale,
      displayName: displayName,
      vendor: vendor,
      version: version,
      status: liveStatus,
      availabilityStatus: availabilityStatus,
    );
  }
}

HomeProviderStatus _resolveProviderStatus(
  AgentManagementAgentView agent, {
  bool ignoreRuntime = false,
}) {
  final runtimeState = ignoreRuntime
      ? AgentRuntimeState.notRunning
      : agent.runtimeState;
  if (agent.installationState == AgentInstallationState.detecting) {
    return HomeProviderStatus.detecting;
  }
  if (!agent.enabled || runtimeState == AgentRuntimeState.disabled) {
    return HomeProviderStatus.disabled;
  }
  if (agent.accountState == AgentAccountState.loggedOut ||
      agent.accountState == AgentAccountState.expired ||
      agent.accountState == AgentAccountState.unavailable) {
    return HomeProviderStatus.needsLogin;
  }
  if (runtimeState == AgentRuntimeState.error ||
      runtimeState == AgentRuntimeState.unavailable) {
    return HomeProviderStatus.error;
  }
  if (runtimeState == AgentRuntimeState.running ||
      runtimeState == AgentRuntimeState.starting ||
      runtimeState == AgentRuntimeState.stopping) {
    return HomeProviderStatus.running;
  }
  // 「有新版本」不在首页出现：升级是 Agent 管理页的事，首页只回答「现在能不能
  // 用」。可更新的 Provider 依然是可用的，就按可用显示。
  return HomeProviderStatus.available;
}

/// 首页只从管理 owner 的确认证据与实时覆盖计算，不缓存第二份列表。
final class AgentManagementHomeState {
  AgentManagementHomeState({
    required List<HomeProviderSummary> installedProviders,
    required this.isLoading,
    required this.phase,
    required this.hasConfirmedData,
    required this.showingStaleData,
    this.detectionFailure,
  }) : installedProviders = List.unmodifiable(installedProviders);
  final List<HomeProviderSummary> installedProviders;
  final bool isLoading;
  final ManagementDetectionPhase phase;
  final bool hasConfirmedData;
  final bool showingStaleData;
  final AgentManagementFailure? detectionFailure;
}

AgentManagementHomeState selectManagementHome(AgentManagementSliceState state) {
  final detection = state.detection;
  return AgentManagementHomeState(
    installedProviders: [
      for (final agent in AgentManagementSliceSelectors.agents(state))
        if (agent.installed &&
            detection.confirmedByProviderId.containsKey(agent.definition.id))
          HomeProviderSummary.fromAgentView(
            agent,
            isStale:
                detection
                    .confirmedByProviderId[agent.definition.id]!
                    .freshness !=
                DetectionFreshness.confirmedThisRun,
          ).withRuntime(state.runtimeByProviderId[agent.definition.id]),
    ],
    isLoading: detection.isLoading,
    phase: detection.phase,
    hasConfirmedData: detection.confirmedByProviderId.isNotEmpty,
    showingStaleData: detection.confirmedByProviderId.values.any(
      (r) =>
          r.freshness == DetectionFreshness.stale ||
          r.freshness == DetectionFreshness.restoredCache,
    ),
    detectionFailure:
        detection.lastResult?.failure ??
        detection.failuresByProviderId.values.firstOrNull,
  );
}

final agentManagementHomeProvider = Provider<AgentManagementHomeState>(
  (ref) => selectManagementHome(ref.watch(agentManagementSliceProvider)),
);
