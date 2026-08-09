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
                file.readAsStringSync().contains('providerFactory.create('),
          )
          .map((file) => file.path)
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
