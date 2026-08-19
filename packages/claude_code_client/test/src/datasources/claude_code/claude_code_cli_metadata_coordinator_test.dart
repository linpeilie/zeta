import 'dart:async';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_cli_metadata.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_cli_metadata_coordinator.dart';
import 'package:test/test.dart';

void main() {
  group('ClaudeCodeCliMetadataCoordinator', () {
    test('model and quota callers share one in-flight probe', () async {
      // Arrange
      final gate = Completer<ClaudeCodeCliMetadataSnapshot>();
      var calls = 0;
      final coordinator = ClaudeCodeCliMetadataCoordinator(
        metadataLoader: () {
          calls += 1;
          return gate.future;
        },
      );

      // Act
      final model = coordinator.refreshForModels();
      final quota = coordinator.readForQuota();
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(calls, 1);
      gate.complete(_metadata('shared'));
      final results = await Future.wait(<Future<ClaudeCodeCliMetadataSnapshot>>[
        model,
        quota,
      ]);
      expect(results.first.models.models.single.id, 'shared');
      expect(identical(results.first, results.last), isTrue);
    });

    test('every sequential model refresh starts a new probe', () async {
      var calls = 0;
      final coordinator = ClaudeCodeCliMetadataCoordinator(
        metadataLoader: () async {
          calls += 1;
          return _metadata('model-$calls');
        },
      );

      final first = await coordinator.refreshForModels();
      final quotaReuse = await coordinator.readForQuota();
      final second = await coordinator.refreshForModels();

      expect(first.models.models.single.id, 'model-1');
      expect(identical(quotaReuse, first), isTrue);
      expect(second.models.models.single.id, 'model-2');
      expect(calls, 2);
    });

    test('quota reuses only the configured short success window', () async {
      var now = DateTime.utc(2026, 8, 12, 8);
      var calls = 0;
      final coordinator = ClaudeCodeCliMetadataCoordinator(
        metadataLoader: () async {
          calls += 1;
          return _metadata('quota-$calls');
        },
        clock: () => now,
      );

      final first = await coordinator.readForQuota();
      now = now.add(const Duration(seconds: 59));
      final cached = await coordinator.readForQuota();
      now = now.add(const Duration(seconds: 1));
      final refreshed = await coordinator.readForQuota();

      expect(identical(cached, first), isTrue);
      expect(refreshed.models.models.single.id, 'quota-2');
      expect(calls, 2);
    });

    test('a failed probe is cleared and can be retried', () async {
      var calls = 0;
      final coordinator = ClaudeCodeCliMetadataCoordinator(
        metadataLoader: () async {
          calls += 1;
          if (calls == 1) {
            throw StateError('redacted probe failure');
          }
          return _metadata('recovered');
        },
      );

      await expectLater(coordinator.readForQuota(), throwsA(isA<StateError>()));
      final recovered = await coordinator.readForQuota();

      expect(recovered.models.models.single.id, 'recovered');
      expect(calls, 2);
    });
  });
}

ClaudeCodeCliMetadataSnapshot _metadata(String id) {
  return ClaudeCodeCliMetadataSnapshot(
    models: AgentModelList(
      models: <AgentModelInfo>[
        AgentModelInfo(id: id, model: id, displayName: id, isDefault: true),
      ],
    ),
    subscriptionType: 'Claude Pro',
  );
}
