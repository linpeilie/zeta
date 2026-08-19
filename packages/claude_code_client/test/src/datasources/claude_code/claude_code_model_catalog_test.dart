import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_cli_metadata.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_model_catalog.dart';
import 'package:test/test.dart';

void main() {
  group('ClaudeCodeModelCatalog', () {
    test(
      'uses CLI metadata and caches the current instance snapshot',
      () async {
        var metadataCalls = 0;
        final catalog = ClaudeCodeModelCatalog(
          metadataLoader: () async {
            metadataCalls += 1;
            return _metadata('cli-sonnet');
          },
        );

        final first = await catalog.listModels();
        final cached = await catalog.listModels();

        expect(first.models.single.id, 'cli-sonnet');
        expect(cached, same(first));
        expect(metadataCalls, 1);
      },
    );

    test('refresh bypasses the current instance snapshot', () async {
      var metadataCalls = 0;
      final catalog = ClaudeCodeModelCatalog(
        metadataLoader: () async {
          metadataCalls += 1;
          return _metadata('cli-model-$metadataCalls');
        },
      );
      await catalog.listModels();

      final refreshed = await catalog.refreshModels();

      expect(refreshed.models.single.id, 'cli-model-2');
      expect(metadataCalls, 2);
    });

    test(
      'CLI failure throws a sanitized refresh failure and retries',
      () async {
        var metadataCalls = 0;
        final catalog = ClaudeCodeModelCatalog(
          metadataLoader: () async {
            metadataCalls += 1;
            if (metadataCalls == 1) {
              throw StateError('sensitive loader details');
            }
            return _metadata('recovered');
          },
        );

        await expectLater(
          catalog.listModels(),
          throwsA(
            isA<StateError>()
                .having(
                  (error) => error.message,
                  'message',
                  'Claude Code CLI model metadata is unavailable',
                )
                .having(
                  (error) => error.toString(),
                  'sanitized',
                  isNot(contains('sensitive loader details')),
                ),
          ),
        );
        final recovered = await catalog.listModels();

        expect(recovered.models.single.id, 'recovered');
        expect(metadataCalls, 2);
      },
    );

    test('empty CLI metadata fails instead of inventing a catalog', () async {
      final catalog = ClaudeCodeModelCatalog(
        metadataLoader: () async => ClaudeCodeCliMetadataSnapshot.empty,
      );

      await expectLater(
        catalog.refreshModels(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Claude Code CLI returned no available models',
          ),
        ),
      );
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
