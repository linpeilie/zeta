import 'dart:convert';
import 'dart:io';

import 'package:agent_config_client/agent_config_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  const codec = AgentModelCatalogCacheCodec();
  final snapshot = AgentModelCatalogSnapshot(
    providerId: 'codex',
    configFingerprint: 'sha256-safe-fingerprint',
    includeHidden: true,
    models: AgentModelList(
      models: <AgentModelInfo>[
        AgentModelInfo(
          id: 'gpt-5',
          model: 'gpt-5-2026',
          displayName: 'GPT-5',
          description: 'Current model',
          hidden: true,
          supportedReasoningEfforts: const <AgentModelReasoningEffort>[
            AgentModelReasoningEffort(
              effort: 'high',
              description: 'Deep reasoning',
            ),
          ],
          defaultReasoningEffort: 'high',
          serviceTiers: const <AgentModelServiceTier>[
            AgentModelServiceTier(
              id: 'priority',
              name: 'Fast',
              description: 'Priority processing',
              unavailableReason: 'quota',
            ),
          ],
          defaultServiceTier: 'priority',
          isDefault: true,
          enabled: false,
          unavailableReason: 'maintenance',
          contextWindowTokens: 200000,
        ),
      ],
      nextCursor: 'next-page',
    ),
    fetchedAt: DateTime.utc(2026, 8, 19, 12),
    source: 'provider',
  );

  group('AgentModelCatalogCacheCodec', () {
    test('round trips all current fields', () {
      final decoded = codec
          .decode(
            codec.encode(<AgentModelCatalogSnapshot>[snapshot]),
          )
          .single;
      expect(decoded.providerId, snapshot.providerId);
      expect(decoded.configFingerprint, snapshot.configFingerprint);
      expect(decoded.includeHidden, isTrue);
      expect(decoded.fetchedAt, snapshot.fetchedAt);
      expect(decoded.source, snapshot.source);
      expect(decoded.models.nextCursor, 'next-page');
      final model = decoded.models.models.single;
      expect(model.id, 'gpt-5');
      expect(model.model, 'gpt-5-2026');
      expect(model.displayName, 'GPT-5');
      expect(model.description, 'Current model');
      expect(model.hidden, isTrue);
      expect(model.supportedReasoningEfforts.single.effort, 'high');
      expect(
        model.supportedReasoningEfforts.single.description,
        'Deep reasoning',
      );
      expect(model.defaultReasoningEffort, 'high');
      expect(model.serviceTiers.single.id, 'priority');
      expect(model.serviceTiers.single.enabled, isTrue);
      expect(model.serviceTiers.single.unavailableReason, 'quota');
      expect(model.defaultServiceTier, 'priority');
      expect(model.isDefault, isTrue);
      expect(model.enabled, isFalse);
      expect(model.unavailableReason, 'maintenance');
      expect(model.contextWindowTokens, 200000);
    });

    test('round trips empty catalogs and nullable model fields', () {
      final minimal = AgentModelCatalogSnapshot(
        providerId: 'minimal',
        configFingerprint: 'fingerprint',
        includeHidden: false,
        models: AgentModelList(
          models: <AgentModelInfo>[
            AgentModelInfo(
              id: 'm',
              model: 'm',
              displayName: 'M',
            ),
          ],
        ),
        fetchedAt: DateTime.utc(2026),
        source: 'cache',
      );
      final decoded = codec.decode(
        codec.encode(<AgentModelCatalogSnapshot>[minimal]),
      );
      expect(decoded.single.models.models.single.contextWindowTokens, isNull);
      expect(
        codec.decode(codec.encode(const <AgentModelCatalogSnapshot>[])),
        isEmpty,
      );
    });

    test('rejects invalid root, version, entries, and duplicate identity', () {
      expect(
        () => codec.decode('x'),
        _failure(AgentConfigDecodeReason.invalidJson),
      );
      expect(
        () => codec.decode('[]'),
        _failure(AgentConfigDecodeReason.invalidShape),
      );
      expect(
        () => codec.decode(
          jsonEncode(<String, Object?>{'version': 2, 'entries': <Object?>[]}),
        ),
        _failure(AgentConfigDecodeReason.unsupportedVersion),
      );
      expect(
        () => codec.decode(
          jsonEncode(<String, Object?>{'version': 1, 'entries': true}),
        ),
        _failure(AgentConfigDecodeReason.invalidShape),
      );
      final entry =
          (jsonDecode(codec.encode(<AgentModelCatalogSnapshot>[snapshot]))
                  as Map<String, Object?>)['entries']!
              as List<Object?>;
      expect(
        () => codec.decode(
          jsonEncode(<String, Object?>{
            'version': 1,
            'entries': <Object?>[entry.single, entry.single],
          }),
        ),
        _failure(AgentConfigDecodeReason.duplicateIdentifier),
      );
    });

    test('rejects malformed snapshot and model fields without truncation', () {
      final root = jsonDecode(
        codec.encode(<AgentModelCatalogSnapshot>[snapshot]),
      ) as Map<String, Object?>;
      final entry = Map<String, Object?>.from(
        (root['entries']! as List<Object?>).single! as Map<String, Object?>,
      );
      final models = Map<String, Object?>.from(
        entry['models']! as Map<String, Object?>,
      );
      final model = Map<String, Object?>.from(
        (models['items']! as List<Object?>).single! as Map<String, Object?>,
      );
      final effort = Map<String, Object?>.from(
        (model['supportedReasoningEfforts']! as List<Object?>).single!
            as Map<String, Object?>,
      );
      final tier = Map<String, Object?>.from(
        (model['serviceTiers']! as List<Object?>).single!
            as Map<String, Object?>,
      );

      final corruptions = <Map<String, Object?>>[
        <String, Object?>{...entry, 'providerId': ''},
        <String, Object?>{...entry, 'includeHidden': 'yes'},
        <String, Object?>{...entry, 'fetchedAt': 'bad'},
        <String, Object?>{...entry, 'models': <Object?>[]},
        <String, Object?>{
          ...entry,
          'models': <String, Object?>{...models, 'items': true},
        },
        <String, Object?>{
          ...entry,
          'models': <String, Object?>{...models, 'nextCursor': 7},
        },
        _entryWithModel(entry, models, <String, Object?>{...model, 'id': ''}),
        _entryWithModel(entry, models, <String, Object?>{
          ...model,
          'hidden': 'yes',
        }),
        _entryWithModel(
          entry,
          models,
          <String, Object?>{...model, 'contextWindowTokens': 0},
        ),
        _entryWithModel(
          entry,
          models,
          <String, Object?>{...model, 'supportedReasoningEfforts': true},
        ),
        _entryWithModel(
          entry,
          models,
          <String, Object?>{
            ...model,
            'supportedReasoningEfforts': <Object?>[
              <String, Object?>{...effort, 'effort': ''},
            ],
          },
        ),
        _entryWithModel(
          entry,
          models,
          <String, Object?>{...model, 'serviceTiers': true},
        ),
        _entryWithModel(
          entry,
          models,
          <String, Object?>{
            ...model,
            'serviceTiers': <Object?>[
              <String, Object?>{...tier, 'enabled': 1},
            ],
          },
        ),
      ];
      for (final corruption in corruptions) {
        expect(
          () => codec.decode(
            jsonEncode(<String, Object?>{
              'version': 1,
              'entries': <Object?>[corruption],
            }),
          ),
          throwsA(isA<AgentConfigDecodeException>()),
        );
      }
    });
  });

  group('FileAgentModelCatalogCacheStore', () {
    late Directory directory;
    late File file;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('zeta_models_');
      file = File('${directory.path}${Platform.pathSeparator}models.json');
    });

    tearDown(() => directory.delete(recursive: true));

    test('returns empty when missing and overwrites complete cache', () async {
      final store = FileAgentModelCatalogCacheStore(file: file);
      expect(await store.load(), isEmpty);
      await store.save(<AgentModelCatalogSnapshot>[snapshot]);
      expect((await store.load()).single.providerId, 'codex');
      await store.save(const <AgentModelCatalogSnapshot>[]);
      expect(await store.load(), isEmpty);
      expect(file.parent.listSync().whereType<File>(), hasLength(1));
    });

    test('propagates typed decode failure for existing corruption', () async {
      await file.create(recursive: true);
      await file.writeAsString('');
      await expectLater(
        FileAgentModelCatalogCacheStore(file: file).load(),
        _failure(AgentConfigDecodeReason.invalidJson),
      );
    });
  });
}

Map<String, Object?> _entryWithModel(
  Map<String, Object?> entry,
  Map<String, Object?> models,
  Map<String, Object?> model,
) {
  return <String, Object?>{
    ...entry,
    'models': <String, Object?>{
      ...models,
      'items': <Object?>[model],
    },
  };
}

Matcher _failure(AgentConfigDecodeReason reason) {
  return throwsA(
    isA<AgentConfigDecodeException>().having(
      (error) => error.reason,
      'reason',
      reason,
    ),
  );
}
