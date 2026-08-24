import 'package:flutter/foundation.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

import 'package:zeta/src/app/agent_management_slice/agent_management_slice_runner.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_effect.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_store.dart';
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_text_catalog.dart';

/// IdeHome 持有的 Agent management 页面组合。
///
/// 它拥有 store/runner 与两个 ingress 监听；repository、settings store 和 runtime
/// 均由上层拥有，关闭本对象时只摘监听并关闭页面 store。
final class AgentManagementSliceComposition {
  AgentManagementSliceComposition._({
    required this.store,
    required this._providerSettings,
    required this._runtimeListenable,
    required this._runtimeSnapshotProvider,
  }) {
    _unsubscribeProviderSettings = _providerSettings.subscribe(
      _handleProviderSettingsChanged,
    );
    _runtimeListenable.addListener(_handleRuntimeChanged);
  }

  final AgentManagementSliceStore store;
  final AgentProviderSettingsPort _providerSettings;
  final Listenable _runtimeListenable;
  final AgentManagementRuntimeSnapshotProvider _runtimeSnapshotProvider;
  late final void Function() _unsubscribeProviderSettings;
  bool _closed = false;

  factory AgentManagementSliceComposition.create({
    required Map<String, AgentCliManagementRepository> repositories,
    required AgentProviderSettingsPort providerSettings,
    required Listenable runtimeListenable,
    required AgentManagementRuntimeSnapshotProvider runtimeSnapshotProvider,
    required AgentManagementTextCatalog textCatalog,
  }) {
    final orderedIds = <String>[
      for (final definition in AgentDefinition.all)
        if (repositories.containsKey(definition.id)) definition.id,
      for (final id in repositories.keys)
        if (!AgentDefinition.all.any((definition) => definition.id == id)) id,
    ];
    final initialState = AgentManagementSliceState.initial(
      agentsById: <String, ManagedAgent>{
        for (final id in orderedIds)
          id: ManagedAgent.forDefinition(
            definition:
                AgentDefinition.byId(id) ??
                AgentDefinition(
                  id: id,
                  displayName: id,
                  vendor: 'Unknown',
                  commandName: id,
                  protocol: 'unknown',
                  transport: 'unknown',
                  configFormat: 'unknown',
                  defaultConfigRelativePath: '',
                  npmPackage: '',
                ),
            enabled: providerSettings.isProviderEnabled(id),
          ),
      },
      orderedAgentIds: orderedIds,
      capabilitiesByAgentId: <String, AgentCliManagementCapabilities>{
        for (final entry in repositories.entries)
          entry.key: entry.value is AgentCliManagementDescriptor
              ? (entry.value as AgentCliManagementDescriptor)
                    .managementCapabilities
              : AgentCliManagementCapabilities.none,
      },
      providerSettings: providerSettings.settings,
    );
    final deferredRunner = _DeferredAgentManagementRunner();
    final store = AgentManagementSliceStore(
      initialState: initialState,
      effectRunner: deferredRunner,
      configurationNotLoadedMessage: textCatalog.configurationNotLoaded(),
      accountDataEnrichmentEnabledFor: (config) =>
          config.extra[claudeCodeAccountDataEnrichmentKey] != false,
    );
    deferredRunner.delegate = AgentManagementSliceRunnerAdapter(
      repositories: repositories,
      providerSettings: providerSettings,
      store: store,
      textCatalog: textCatalog,
      runtimeSnapshotProvider: runtimeSnapshotProvider,
    );
    return AgentManagementSliceComposition._(
      store: store,
      providerSettings: providerSettings,
      runtimeListenable: runtimeListenable,
      runtimeSnapshotProvider: runtimeSnapshotProvider,
    );
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _unsubscribeProviderSettings();
    _runtimeListenable.removeListener(_handleRuntimeChanged);
    store.close();
  }

  void _handleProviderSettingsChanged() {
    if (!_closed) {
      store.providerSettingsChanged(_providerSettings.settings);
    }
  }

  void _handleRuntimeChanged() {
    if (_closed) {
      return;
    }
    final snapshot = _runtimeSnapshotProvider();
    store.runtimeSnapshotChanged(snapshot.activeAgentId, snapshot.runtimeState);
  }
}

final class _DeferredAgentManagementRunner
    implements AgentManagementSliceEffectRunner {
  AgentManagementSliceEffectRunner? delegate;

  @override
  void run(AgentManagementSliceEffect effect) => delegate?.run(effect);

  @override
  String? validateConfiguration(String agentId, String content) =>
      delegate?.validateConfiguration(agentId, content);
}
