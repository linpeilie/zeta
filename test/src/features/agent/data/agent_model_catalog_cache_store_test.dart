import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_model_catalog_cache_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('FileAgentModelCatalogCacheStore', () {
    late Directory directory;
    late File file;
    late FileAgentModelCatalogCacheStore store;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('zeta_model_catalog_');
      file = File('${directory.path}/agent_models_v1.json');
      store = FileAgentModelCatalogCacheStore(file: file);
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test(
      'round-trips normalized fields without raw provider payload',
      () async {
        await store.save(<AgentModelCatalogSnapshot>[
          AgentModelCatalogSnapshot(
            providerId: 'codex',
            configFingerprint: 'fingerprint',
            includeHidden: false,
            fetchedAt: DateTime.utc(2026, 7, 22, 8),
            source: 'Codex app-server',
            models: const AgentModelList(
              models: <AgentModelInfo>[
                AgentModelInfo(
                  id: 'gpt-test',
                  model: 'gpt-test',
                  displayName: 'GPT Test',
                  description: 'Test model',
                  supportedReasoningEfforts: <AgentModelReasoningEffort>[
                    AgentModelReasoningEffort(
                      effort: 'high',
                      description: 'Deep reasoning',
                    ),
                  ],
                  serviceTiers: <AgentModelServiceTier>[
                    AgentModelServiceTier(id: 'priority', name: 'Fast'),
                  ],
                  contextWindowTokens: 128000,
                  raw: <String, Object?>{'secret': 'do-not-write'},
                ),
              ],
            ),
          ),
        ]);

        final text = await file.readAsString();
        final restored = await store.load();

        expect(text, isNot(contains('do-not-write')));
        expect(restored, hasLength(1));
        final model = restored.single.models.models.single;
        expect(model.id, 'gpt-test');
        expect(model.supportedReasoningEfforts.single.effort, 'high');
        expect(model.serviceTiers.single.id, 'priority');
        expect(model.contextWindowTokens, 128000);
        expect(model.raw, isEmpty);
      },
    );

    test(
      'returns an empty cache for corrupt or incompatible content',
      () async {
        await file.writeAsString('{broken');
        expect(await store.load(), isEmpty);

        await file.writeAsString('{"version":99,"entries":[]}');
        expect(await store.load(), isEmpty);
      },
    );
  });
}
