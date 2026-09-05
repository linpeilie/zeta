import 'package:zeta/src/features/agent_management/application/agent_management_runtime_facts.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_slice_runner.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_effect.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_store.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// IdeHome 持有的 Agent management 页面组合。
///
/// 它拥有 store/runner 与两个 ingress 监听；repository、settings store 和 runtime
/// 均由上层拥有，关闭本对象时只摘监听并关闭页面 store。
final class AgentManagementSliceComposition {
  AgentManagementSliceComposition._({
    required this.store,
    required this._providerSettings,
    required AgentManagementRuntimeFactSource runtimeFactSource,
  }) {
    final unsubscribeSettings = _providerSettings.subscribe(
      _handleProviderSettingsChanged,
    );
    void Function()? unsubscribeRuntime;
    try {
      unsubscribeRuntime = runtimeFactSource.subscribe(
        store.runtimeFactsReplaced,
      );
      store.runtimeFactsReplaced(runtimeFactSource.current);
    } catch (_) {
      unsubscribeRuntime?.call();
      unsubscribeSettings();
      store.close();
      rethrow;
    }
    _unsubscribeProviderSettings = unsubscribeSettings;
    _unsubscribeRuntime = unsubscribeRuntime;
  }

  final AgentManagementSliceStore store;
  final AgentProviderSettingsPort _providerSettings;

  late final void Function() _unsubscribeRuntime;
  late final void Function() _unsubscribeProviderSettings;
  bool _closed = false;

  factory AgentManagementSliceComposition.create({
    required Map<String, AgentCliManagementRepository> repositories,
    required Map<String, AgentDefinition> definitions,
    required AgentProviderSettingsPort providerSettings,
    required AgentManagementRuntimeFactSource runtimeFactSource,
    required AgentManagementTextCatalog textCatalog,
  }) {
    final orderedIds = <String>[
      for (final definition in definitions.values)
        if (repositories.containsKey(definition.id)) definition.id,
      for (final id in repositories.keys)
        if (!definitions.values.any((definition) => definition.id == id)) id,
    ];
    final initialState = AgentManagementSliceState.initial(
      agentsById: <String, ManagedAgent>{
        for (final id in orderedIds)
          id: ManagedAgent.forDefinition(
            definition:
                definitions[id] ??
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
      initialState: initialState.copyWith(
        runtimeFacts: runtimeFactSource.current,
      ),
      effectRunner: deferredRunner,
      configurationNotLoadedMessage: textCatalog.configurationNotLoaded(),
      accountDataEnrichmentEnabledFor: (config) {
        final key = initialState
            .capabilitiesByAgentId[config.id]
            ?.accountDataEnrichmentExtraKey;
        return key != null && config.extra[key] != false;
      },
    );
    deferredRunner.delegate = AgentManagementSliceRunnerAdapter(
      repositories: repositories,
      definitions: definitions,
      providerSettings: providerSettings,
      store: store,
      textCatalog: textCatalog,
    );
    return AgentManagementSliceComposition._(
      store: store,
      providerSettings: providerSettings,
      runtimeFactSource: runtimeFactSource,
    );
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _unsubscribeProviderSettings();
    _unsubscribeRuntime();
    store.close();
  }

  void _handleProviderSettingsChanged() {
    if (!_closed) {
      store.providerSettingsChanged(_providerSettings.settings);
    }
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
