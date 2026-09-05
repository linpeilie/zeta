import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _sourcePath =
    'lib/src/app/agent_management_slice/workspace_agent_runtime_fact_source.dart';
const _factsPath =
    'lib/src/features/agent_management/application/agent_management_runtime_facts.dart';

List<String> _forbiddenObservationMechanisms(String source) {
  final code = source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
  return [
    for (final token in [
      'selectedAgentController',
      'activeProviderId',
      'activeOperationCount',
      'debugProviderCount',
      'StorageService',
      'Timer(',
      '.acquire(',
      '.release(',
      '.invalidateRuntime(',
    ])
      if (code.contains(token)) token,
  ];
}

void main() {
  test(
    'production fact source exists and observes without selecting or owning runtimes',
    () {
      final source = File(_sourcePath).readAsStringSync();
      expect(source, contains('implements AgentManagementRuntimeFactSource'));
      expect(source, contains('workspace.bindingManager.bindings'));
      expect(source, contains('runtimeObservationListenable'));
      expect(source, contains('subscriptionGeneration'));
      expect(_forbiddenObservationMechanisms(source), isEmpty);
      final facts = File(_factsPath).readAsStringSync();
      expect(facts, contains('class AgentManagementRuntimeFacts'));
      expect(facts, contains('class AgentManagementProviderRuntimeSummary'));
      for (final token in [
        'AgentConversationBinding binding',
        'threadTitle',
        'threadPreview',
        'rawError',
        'toJson(',
        'sessionPath',
        'StorageService',
      ]) {
        expect(facts, isNot(contains(token)), reason: token);
      }
    },
  );

  test(
    'observer guard rejects negative samples, including hidden ownership',
    () {
      for (final sample in [
        'selectedAgentController.status',
        'settings.activeProviderId',
        'binding.runtimeSnapshot.activeOperationCount',
        'registry.debugProviderCount',
        'StorageService()',
        'Timer(Duration.zero, poll)',
        'registry.acquire(config)',
        'lease.release()',
        'binding.invalidateRuntime()',
      ]) {
        expect(
          _forbiddenObservationMechanisms(sample),
          isNotEmpty,
          reason: sample,
        );
      }
    },
  );

  test(
    'old single-provider tuple and UI status bridge are removed from production',
    () {
      final files = [
        'lib/src/ui/features/ide/views/ide_home.dart',
        'lib/src/app/shell/ide_shell_controller.dart',
        'lib/src/app/agent_management_slice/agent_management_slice_runner.dart',
        'lib/src/app/agent_management_slice/agent_management_slice_composition.dart',
      ];
      expect(files, isNotEmpty);
      for (final path in files) {
        final source = File(path).readAsStringSync();
        for (final legacy in [
          'AgentManagementRuntimeSnapshot',
          '_managementRuntimeState',
          '_managementRuntimeSnapshot',
          'subscribeRuntimeChanges',
          'runtimeSnapshotChanged(',
        ]) {
          expect(source, isNot(contains(legacy)), reason: '$path: $legacy');
        }
      }
    },
  );
}
