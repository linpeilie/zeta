import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/data/agent_model_catalog_cache_store.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

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

    test(
      'reads an old v1 static snapshot and overwrites it after refresh',
      () async {
        final oldFetchedAt = DateTime.utc(2026, 8, 12, 6);
        final refreshedAt = oldFetchedAt.add(const Duration(hours: 2));
        final fingerprint = AgentModelCatalogRepository(
          store: MemoryAgentModelCatalogCacheStore(),
        ).configFingerprint(AgentProviderConfig.defaultClaudeCode);
        await file.writeAsString(
          jsonEncode(<String, Object?>{
            'version': 1,
            'unknownRootField': true,
            'entries': <Object?>[
              <String, Object?>{
                'providerId': defaultClaudeCodeProviderId,
                'configFingerprint': fingerprint,
                'includeHidden': false,
                'fetchedAt': oldFetchedAt.toIso8601String(),
                'source': 'Claude Code static fallback',
                'unknownEntryField': 'ignored',
                'models': <Object?>[
                  <String, Object?>{
                    'id': 'legacy-static-sonnet',
                    'model': 'legacy-static-sonnet',
                    'displayName': 'Legacy Static Sonnet',
                    'isDefault': true,
                    'unknownModelField': 'ignored',
                  },
                ],
              },
            ],
          }),
        );
        final repository = AgentModelCatalogRepository(
          store: store,
          clock: () => refreshedAt,
        );
        final cacheHits = <String>[];

        final result = await repository.load(
          config: AgentProviderConfig.defaultClaudeCode,
          source: 'Claude Code CLI initialize',
          forceRefresh: true,
          onCacheHit: (snapshot) {
            cacheHits.add(snapshot.models.models.single.id);
          },
          refreshLoader: () async => const AgentModelList(
            models: <AgentModelInfo>[
              AgentModelInfo(
                id: 'cli-current-sonnet',
                model: 'cli-current-sonnet',
                displayName: 'CLI Current Sonnet',
                isDefault: true,
              ),
            ],
          ),
        );
        final persisted = await file.readAsString();

        expect(cacheHits, <String>['legacy-static-sonnet']);
        expect(result.models.models.single.id, 'cli-current-sonnet');
        expect(persisted, contains('cli-current-sonnet'));
        expect(persisted, isNot(contains('legacy-static-sonnet')));
      },
    );
  });
}
