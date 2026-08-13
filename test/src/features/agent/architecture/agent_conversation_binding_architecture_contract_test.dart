import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('conversation binding architecture contracts', () {
    test('registry remains the only runtime factory caller', () {
      final callers = Directory('lib/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where(
            (file) =>
                file.readAsStringSync().contains(
                  'providerFactory.createBundle(',
                ),
          )
          .map((file) => file.path.replaceAll(Platform.pathSeparator, '/'))
          .toList(growable: false);

      expect(callers, <String>[
        'lib/src/features/agent/application/agent_provider_runtime_registry.dart',
      ]);
    });

    test('application lifecycle code has no UI controller dependency', () {
      const roots = <String>[
        'lib/src/features/agent/application',
        'lib/src/features/agent_management/application',
        'lib/src/features/project_threads/application',
      ];

      for (final root in roots) {
        for (final file
            in Directory(root)
                .listSync(recursive: true)
                .whereType<File>()
                .where((file) => file.path.endsWith('.dart'))) {
          expect(
            file.readAsStringSync(),
            isNot(contains('/src/ui/')),
            reason: file.path,
          );
        }
      }
    });

    test('ViewModel cannot own session leases scopes or pins', () {
      final source = File(
        'lib/src/features/agent/presentation/agent_conversation_view_model.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('AgentProviderRuntimeLease')));
      expect(source, isNot(contains('AgentProviderRuntimeScopeKey')));
      expect(source, isNot(contains('AgentProviderRuntimePin')));
      expect(source, isNot(contains('AgentProvider? _provider')));
      expect(source, isNot(contains('_turnPin')));
      expect(source, isNot(contains('pinActiveProvider')));
      expect(source, isNot(contains('_ensureCatalogProvider')));
      expect(source, isNot(contains('_ensureSessionProvider')));
      expect(source, isNot(contains('_ensureProvider')));
      expect(source, isNot(contains("domain/agent_provider.dart")));
      expect(source, isNot(matches(RegExp(r'\bAgentProvider[? ]'))));
    });

    test('legacy controller and multi-thread ViewModel APIs stay deleted', () {
      expect(
        File(
          'lib/src/ui/features/ide/view_models/'
          'active_agent_provider_controller.dart',
        ).existsSync(),
        isFalse,
      );
      final viewModel = File(
        'lib/src/features/agent/presentation/agent_conversation_view_model.dart',
      ).readAsStringSync();
      final workspace = File(
        'lib/src/features/agent/application/'
        'agent_thread_workspace_controller.dart',
      ).readAsStringSync();

      for (final legacy in const <String>[
        'switchThread(',
        'updateWorkspace(',
        'restoredSessionId:',
        'restoredProviderId:',
        'resetConversation:',
      ]) {
        expect(viewModel, isNot(contains(legacy)), reason: legacy);
      }
      expect(workspace, isNot(contains('bindThreadIdentity(')));
    });

    test('runtime scope and neutral ports have no compatibility defaults', () {
      final registry = File(
        'lib/src/features/agent/application/agent_provider_runtime_registry.dart',
      ).readAsStringSync();
      final modelSelection = File(
        'lib/src/features/agent/application/'
        'agent_conversation_model_selection_controller.dart',
      ).readAsStringSync();
      final usage = File(
        'lib/src/features/usage_statistics/data/'
        'global_runtime_agent_usage_quota_source.dart',
      ).readAsStringSync();

      expect(
        File(
          'lib/src/features/usage_statistics/data/'
          'provider_agent_usage_panel_repository.dart',
        ).existsSync(),
        isFalse,
      );

      expect(registry, contains('required AgentProviderRuntimeScopeKey scope'));
      expect(
        registry,
        isNot(contains('scope = AgentProviderRuntimeScopeKey.global')),
      );
      expect(modelSelection, isNot(contains('bindProvider(')));
      for (final legacy in const <String>[
        'providerLeaseLoader',
        'providerLoader',
        'isSharedProvider',
        'AgentProviderInstanceLoader',
      ]) {
        expect(usage, isNot(contains(legacy)), reason: legacy);
      }
    });

    test('Binding and Bundle do not expose the raw provider', () {
      final binding = File(
        'lib/src/features/agent/application/agent_conversation_binding.dart',
      ).readAsStringSync();
      final bundle = File(
        'lib/src/features/agent/domain/agent_provider_bundle.dart',
      ).readAsStringSync();

      expect(binding, isNot(contains('AgentProvider get provider')));
      expect(binding, isNot(contains('lease.provider')));
      expect(bundle, isNot(contains('AgentProvider get provider')));
      expect(bundle, isNot(contains('runtime.provider')));
      expect(
        File(
          'lib/src/features/agent/application/agent_provider_runtime_registry.dart',
        ).readAsStringSync(),
        isNot(contains('AgentProvider get provider')),
      );
    });

    test('permission state belongs to one Binding without registries', () {
      expect(
        File(
          'lib/src/features/agent/application/agent_permission_state_store.dart',
        ).existsSync(),
        isFalse,
      );
      final state = File(
        'lib/src/features/agent/application/agent_conversation_permission_state.dart',
      ).readAsStringSync();
      final controller = File(
        'lib/src/features/agent/application/'
        'agent_conversation_permission_selection_controller.dart',
      ).readAsStringSync();

      for (final source in <String>[state, controller]) {
        expect(source, isNot(contains('AgentPermissionStateStore')));
        expect(source, isNot(contains('_activeByProvider')));
        expect(source, isNot(contains('Map<AgentProviderRuntimeIdentity')));
        expect(source, isNot(contains('Map<String, AgentPermission')));
      }
    });

    test(
      'settings controller owns settings but no runtime lease or permission',
      () {
        final source = File(
          'lib/src/features/agent/application/agent_provider_settings_controller.dart',
        ).readAsStringSync();

        expect(source, isNot(contains('AgentProviderRuntimeLease')));
        expect(source, isNot(contains('AgentProviderRuntimeIdentity')));
        expect(source, isNot(contains('AgentPermissionStateStore')));
        expect(source, isNot(contains('permissionStateStore')));
        expect(source, isNot(contains('_providerLease')));
        expect(source, isNot(contains('activeProviderRuntimeIdentity')));
        expect(source, isNot(contains('Future<AgentProvider> activeProvider')));
      },
    );

    test(
      'Project Threads uses global runtime instead of active provider cache',
      () {
        final source = File(
          'lib/src/features/project_threads/application/project_threads_controller.dart',
        ).readAsStringSync();

        expect(source, contains('AgentProviderGlobalRuntime'));
        expect(source, isNot(contains('AgentProviderRuntimeLease')));
        expect(source, isNot(contains('AgentProviderEventListenerGate')));
        expect(source, isNot(contains('.activeProvider()')));
        expect(source, isNot(contains('.acquireProvider(')));
      },
    );

    test('idle monitor is owned by BindingManager only', () {
      expect(
        File(
          'lib/src/features/agent/application/agent_provider_idle_reaper.dart',
        ).existsSync(),
        isFalse,
      );
      final manager = File(
        'lib/src/features/agent/application/agent_conversation_binding_manager.dart',
      ).readAsStringSync();
      final registry = File(
        'lib/src/features/agent/application/agent_provider_runtime_registry.dart',
      ).readAsStringSync();

      expect(manager, contains('Timer.periodic'));
      expect(manager, contains('Duration(minutes: 10)'));
      expect(registry, isNot(contains('Timer.periodic')));
      expect(registry, isNot(contains('lastActiveAt')));
      expect(registry, isNot(contains('AgentPermissionStateStore')));
      expect(registry, isNot(contains('permissionStateStore')));
    });
  });
}
