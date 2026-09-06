import 'package:zeta/src/app/composition/agent_session_resource_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/app/localization/zeta_text_catalog_providers.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_store.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_dependencies.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_notifier.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_state.dart';
import 'project_threads_slice_runner.dart';

/// Immutable input seam; replacing resources requires a new app container.
final class ProjectThreadsCompositionInputs {
  ProjectThreadsCompositionInputs({
    required this.providerSettings,
    required this.globalRuntime,
    required this.bindingManager,
    required this.textCatalog,
    ProjectThreadsSliceDependencies? dependencies,
  }) : dependencies =
           dependencies ??
           ProjectThreadsSliceDependencies(
             initialState: ProjectThreadsSliceState(),
           );

  final AgentProviderSettingsPort providerSettings;
  final AgentProviderGlobalRuntime globalRuntime;
  final AgentConversationBindingManager bindingManager;
  final AgentUiTextCatalog textCatalog;
  final ProjectThreadsSliceDependencies dependencies;
}

final projectThreadsCompositionInputsProvider =
    Provider<ProjectThreadsCompositionInputs>(
      (ref) => ProjectThreadsCompositionInputs(
        providerSettings: ref.read(agentProviderSettingsSliceProvider.notifier),
        globalRuntime: ref.read(agentProviderGlobalRuntimeProvider),
        bindingManager: ref.read(agentConversationBindingManagerProvider),
        textCatalog: ref.read(agentUiTextCatalogProvider),
      ),
      name: 'projectThreadsCompositionInputs',
    );

/// Subscription resource only: Shell receives changes without a copied state.
final projectThreadsChangesProvider =
    Provider<void Function() Function(void Function())>(
      (ref) => (listener) {
        final subscription = ref.listen(
          projectThreadsSliceProvider,
          (_, _) => listener(),
        );
        return subscription.close;
      },
      name: 'projectThreadsChanges',
    );

List<Override> projectThreadsSliceOverrides() => [
  projectThreadsSliceDependenciesProvider.overrideWith(
    (ref) => ref.read(projectThreadsCompositionInputsProvider).dependencies,
  ),
  projectThreadsRunnerFactoryProvider.overrideWith((ref) {
    final inputs = ref.read(projectThreadsCompositionInputsProvider);
    return (owner) => ProjectThreadsSliceRunner(
      providerController: inputs.providerSettings,
      globalRuntime: inputs.globalRuntime,
      bindingManager: inputs.bindingManager,
      textCatalog: inputs.textCatalog,
      stateOwner: owner,
    );
  }),
];
