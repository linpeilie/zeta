import 'package:zeta/src/features/agent_management/application/agent_management_agent_view.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_detection_port.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_management_details_catalog.dart';
import 'agent_management_details_catalog.dart';
import 'agent_management_detection_projection.dart';
import 'agent_management_repository_config.dart';
import 'contributed_agent_management_detection_adapter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_model_catalog_port_adapter.dart';
import 'package:zeta/src/app/plugins/agent_contribution_providers.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/app/localization/zeta_text_catalog_providers.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_store.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_runtime_facts.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_dependencies.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart';
import 'agent_management_slice_runner.dart';

/// Frozen app-session repository inputs. Tests override this same app seam.
final class AgentManagementCompositionInputs {
  AgentManagementCompositionInputs({
    required Map<String, AgentCliManagementRepository> repositories,
    required Map<String, AgentDefinition> definitions,
    required this.providerSettings,
    required this.textCatalog,
  }) : repositories = Map.unmodifiable(repositories),
       definitions = Map.unmodifiable(definitions);
  final Map<String, AgentCliManagementRepository> repositories;
  final Map<String, AgentDefinition> definitions;
  final AgentProviderSettingsPort providerSettings;
  final AgentManagementTextCatalog textCatalog;
}

final agentManagementCompositionInputsProvider =
    Provider<AgentManagementCompositionInputs>((ref) {
      final contributions = ref.read(agentManagementContributionsProvider);
      final modelCatalogRepository = ref.read(
        agentModelCatalogRepositoryProvider,
      );
      final runtimeRegistry = ref.read(agentProviderRuntimeRegistryProvider);
      final providerSettings = ref.read(
        agentProviderSettingsSliceProvider.notifier,
      );
      final textCatalog = ref.read(agentManagementTextCatalogProvider);
      final byId = <String, AgentManagementContribution>{};
      for (final contribution in contributions) {
        if (contribution.providerId != contribution.definition.id ||
            byId.containsKey(contribution.providerId)) {
          throw StateError('Duplicate or mismatched Agent management identity');
        }
        byId[contribution.providerId] = contribution;
      }
      if (byId.isEmpty) {
        throw StateError('No plugin contributed agent management repositories');
      }
      final services = AgentManagementHostServices(
        textCatalog: textCatalog,
        runtimeRegistry: runtimeRegistry,
        modelCatalog: AgentManagementModelCatalogPortAdapter(
          modelCatalogRepository,
        ),
      );
      final repositories = <String, AgentCliManagementRepository>{
        for (final c in byId.values) c.providerId: c.createRepository(services),
      };
      for (final entry in repositories.entries) {
        if (entry.key != entry.value.agentId) {
          throw StateError('Agent management repository identity mismatch');
        }
      }

      return AgentManagementCompositionInputs(
        repositories: repositories,
        definitions: {for (final c in byId.values) c.providerId: c.definition},
        providerSettings: providerSettings,
        textCatalog: textCatalog,
      );
    });

List<Override> agentManagementSliceOverrides() => [
  agentManagementDetailsCatalogProvider.overrideWith(
    (ref) => ref.read(appAgentManagementDetailsCatalogProvider),
  ),
  agentManagementDefaultDetectionPortProvider.overrideWith((ref) {
    final inputs = ref.read(agentManagementCompositionInputsProvider);
    return ContributedAgentManagementDetectionAdapter(
      repositories: inputs.repositories,
      definitions: inputs.definitions,
      settings: inputs.providerSettings,
      details: ref.read(appAgentManagementDetailsCatalogProvider),
      textCatalog: inputs.textCatalog,
      configFor: AgentManagementRepositoryConfig(inputs.definitions).configFor,
    );
  }),
  agentManagementSliceDependenciesProvider.overrideWith((ref) {
    final inputs = ref.read(agentManagementCompositionInputsProvider);
    final orderedIds = <String>[
      for (final definition in inputs.definitions.values)
        if (inputs.repositories.containsKey(definition.id)) definition.id,
      for (final id in inputs.repositories.keys)
        if (!inputs.definitions.values.any((definition) => definition.id == id))
          id,
    ];
    final initialState = AgentManagementSliceState.initial(
      definitionsByProviderId: <String, AgentManagementDisplayDefinition>{
        for (final id in orderedIds)
          id: managementDisplayDefinition(
            inputs.definitions[id] ??
                (throw StateError('Missing management display definition')),
          ),
      },
      orderedAgentIds: orderedIds,
      capabilitiesByAgentId: <String, AgentCliManagementCapabilities>{
        for (final entry in inputs.repositories.entries)
          entry.key: entry.value is AgentCliManagementDescriptor
              ? (entry.value as AgentCliManagementDescriptor)
                    .managementCapabilities
              : AgentCliManagementCapabilities.none,
      },
      providerSettings: inputs.providerSettings.settings,
    );

    return AgentManagementSliceDependencies(
      initialState: initialState,
      configurationNotLoadedMessage: inputs.textCatalog
          .configurationNotLoaded(),
      accountDataEnrichmentEnabledFor: (config) {
        final key = initialState
            .capabilitiesByAgentId[config.id]
            ?.accountDataEnrichmentExtraKey;
        return key != null && config.extra[key] != false;
      },
    );
  }),
  agentManagementRunnerFactoryProvider.overrideWith((ref) {
    final inputs = ref.read(agentManagementCompositionInputsProvider);
    final detectionPort = ref.read(agentManagementDetectionPortProvider);
    final details = ref.read(appAgentManagementDetailsCatalogProvider);
    return (sink) => AgentManagementSliceRunnerAdapter(
      detectionPort: detectionPort,
      detailsCatalog: details,
      repositories: inputs.repositories,
      definitions: inputs.definitions,
      providerSettings: inputs.providerSettings,
      textCatalog: inputs.textCatalog,
      sink: sink,
    );
  }),
];

/// Owns only an external-source subscription, never management state or commands.
/// Start after the provider has built, so synchronous ingress is outside build.
final class AgentManagementInputSubscription {
  AgentManagementInputSubscription(this._subscribeAndPublish);
  final void Function() Function() _subscribeAndPublish;
  void Function()? _unsubscribe;
  bool _closed = false;
  int _borrowers = 0;
  void start() {
    if (_closed) throw StateError('Management input subscription is closed');
    _unsubscribe ??= _subscribeAndPublish();
  }

  void Function() borrow() {
    start();
    _borrowers += 1;
    var released = false;
    return () {
      if (released || _closed) return;
      released = true;
      _borrowers -= 1;
      if (_borrowers == 0) _disconnect();
    };
  }

  void _disconnect() {
    _unsubscribe?.call();
    _unsubscribe = null;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _disconnect();
  }
}

final agentManagementSettingsIngressProvider =
    Provider<AgentManagementInputSubscription>((ref) {
      final sink = ref.read(agentManagementSliceProvider.notifier);
      final settings = ref
          .read(agentManagementCompositionInputsProvider)
          .providerSettings;
      final ingress = AgentManagementInputSubscription(() {
        final unsubscribe = settings.subscribe(
          () => sink.providerSettingsChanged(settings.settings),
        );
        try {
          sink.providerSettingsChanged(settings.settings);
        } catch (_) {
          unsubscribe();
          rethrow;
        }
        return unsubscribe;
      });
      ref.onDispose(ingress.close);
      return ingress;
    });

/// The legacy Shell still owns the fact source until WP-3C moves its construction.
/// This provider borrows that source; closing it only removes its subscription.
final agentManagementRuntimeIngressProvider = Provider.autoDispose
    .family<AgentManagementInputSubscription, AgentManagementRuntimeFactSource>(
      (ref, source) {
        final sink = ref.read(agentManagementSliceProvider.notifier);
        final ingress = AgentManagementInputSubscription(() {
          final unsubscribe = source.subscribe(sink.runtimeFactsReplaced);
          try {
            sink.runtimeFactsReplaced(source.current);
          } catch (_) {
            unsubscribe();
            rethrow;
          }
          return unsubscribe;
        });
        ref.onDispose(ingress.close);
        return ingress;
      },
    );
