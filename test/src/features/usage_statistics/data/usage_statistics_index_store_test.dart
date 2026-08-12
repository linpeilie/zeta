import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'zeta-usage-statistics-index-',
    );
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  group('FileUsageStatisticsPartitionStore', () {
    test(
      'writes and reloads v4 partitions while preserving unknown sources',
      () async {
        final file = _indexFile(tempDirectory);
        await file.parent.create(recursive: true);
        await file.writeAsString(
          jsonEncode(<String, Object?>{
            'version': 4,
            'providers': <String, Object?>{
              'future-agent': <String, Object?>{
                'schemaVersion': 7,
                'payload': <String, Object?>{
                  'records': <Object?>[
                    <String, Object?>{'opaque': true},
                  ],
                },
              },
            },
            'unknownRootField': true,
          }),
        );
        final store = FileUsageStatisticsPartitionStore(file: file);
        final codex = UsageStatisticsIndexPartition(
          schemaVersion: 1,
          payload: <String, Object?>{
            'sessions': <Object?>[_safeSession('codex-source')],
          },
        );

        await store.writePartition('codex-work', codex);

        final reloaded = await FileUsageStatisticsPartitionStore(
          file: file,
        ).readPartition('codex-work');
        final unknown = await FileUsageStatisticsPartitionStore(
          file: file,
        ).readPartition('future-agent');
        final encoded = jsonDecode(await file.readAsString()) as Map;
        expect(encoded['version'], usageStatisticsPartitionIndexVersion);
        expect(reloaded?.payload, codex.payload);
        expect(unknown?.schemaVersion, 7);
        expect(unknown?.payload['records'], hasLength(1));
        expect(
          (encoded['providers'] as Map).keys,
          containsAll(<String>['codex-work', 'future-agent']),
        );
      },
    );

    test(
      'migrates and sanitizes the real v2 top-level sessions shape',
      () async {
        const sourcePath = '/private/codex/rollout-secret.jsonl';
        const rawError = 'raw error containing prompt text';
        final file = _indexFile(tempDirectory);
        await file.parent.create(recursive: true);
        await file.writeAsString(
          jsonEncode(<String, Object?>{
            'version': 2,
            'sessions': <Object?>[
              <String, Object?>{
                ..._safeSession(null),
                'sourceId': null,
                'sourcePath': sourcePath,
                'turns': <Object?>[
                  <String, Object?>{
                    'id': 'turn-1',
                    'status': 'failed',
                    'errorMessage': rawError,
                    'errorCode': 'provider-private-code',
                    'samples': <Object?>[],
                  },
                ],
              },
            ],
          }),
        );
        final store = FileUsageStatisticsPartitionStore(file: file);

        final migrated = await store.readPartition('codex');
        await store.writePartition('codex', migrated!);

        final encoded = await file.readAsString();
        expect(jsonDecode(encoded), isA<Map>());
        expect(encoded, contains('sourceId'));
        expect(encoded, isNot(contains('sourcePath')));
        expect(encoded, isNot(contains(sourcePath)));
        expect(encoded, isNot(contains('errorMessage')));
        expect(encoded, isNot(contains(rawError)));
        expect(encoded, isNot(contains('provider-private-code')));
        expect(
          (jsonDecode(encoded) as Map)['version'],
          usageStatisticsPartitionIndexVersion,
        );
      },
    );

    test(
      'migrates the real v3 provider shape and preserves every partition',
      () async {
        final file = _indexFile(tempDirectory);
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(_legacyV3()));
        final store = FileUsageStatisticsPartitionStore(file: file);

        final codex = await store.readPartition('codex');
        final grok = await store.readPartition('grok');
        await store.writePartition('codex', codex!);

        final encoded = jsonDecode(await file.readAsString()) as Map;
        final providers = encoded['providers'] as Map;
        expect(codex.payload['sessions'], hasLength(1));
        expect(grok?.payload['sessions'], hasLength(1));
        expect(encoded['version'], usageStatisticsPartitionIndexVersion);
        expect(
          providers.keys,
          containsAll(<String>['codex', 'grok', 'future-agent']),
        );
      },
    );

    test(
      'damaged JSON and damaged partitions degrade without blocking valid data',
      () async {
        final file = _indexFile(tempDirectory);
        await file.parent.create(recursive: true);
        await file.writeAsString('{damaged');
        final store = FileUsageStatisticsPartitionStore(file: file);
        expect(await store.readPartition('codex'), isNull);

        await file.writeAsString(
          jsonEncode(<String, Object?>{
            'version': 4,
            'providers': <String, Object?>{
              'valid': <String, Object?>{
                'schemaVersion': 1,
                'payload': <String, Object?>{'sessions': <Object?>[]},
                'unknownField': 'ignored',
              },
              'missing-payload': <String, Object?>{'schemaVersion': 1},
              'bad-schema': <String, Object?>{
                'schemaVersion': 0,
                'payload': <String, Object?>{},
              },
            },
          }),
        );

        expect((await store.readPartition('valid'))?.payload, <String, Object?>{
          'sessions': <Object?>[],
        });
        expect(await store.readPartition('missing-payload'), isNull);
        expect(await store.readPartition('bad-schema'), isNull);
      },
    );

    test('invalid UTF-8 degrades to an empty index', () async {
      final file = _indexFile(tempDirectory);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[0xff]);

      expect(
        await FileUsageStatisticsPartitionStore(
          file: file,
        ).readPartition('codex'),
        isNull,
      );
    });

    test('repeating a legacy migration is idempotent', () async {
      final file = _indexFile(tempDirectory);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_legacyV3()));
      final store = FileUsageStatisticsPartitionStore(file: file);
      final partition = await store.readPartition('codex');

      await store.writePartition('codex', partition!);
      final first = jsonDecode(await file.readAsString());
      await store.writePartition('codex', partition);
      final second = jsonDecode(await file.readAsString());

      expect(second, first);
    });

    test('parallel partition writes do not drop either source', () async {
      final store = FileUsageStatisticsPartitionStore(
        file: _indexFile(tempDirectory),
      );

      await Future.wait(<Future<void>>[
        store.writePartition(
          'first',
          UsageStatisticsIndexPartition(
            schemaVersion: 1,
            payload: <String, Object?>{'value': 1},
          ),
        ),
        store.writePartition(
          'second',
          UsageStatisticsIndexPartition(
            schemaVersion: 2,
            payload: <String, Object?>{'value': 2},
          ),
        ),
      ]);

      expect((await store.readPartition('first'))?.payload['value'], 1);
      expect((await store.readPartition('second'))?.payload['value'], 2);
    });

    test('propagates write failures', () async {
      final blockingParent = File.fromUri(
        tempDirectory.uri.resolve('not-a-directory'),
      );
      await blockingParent.writeAsString('blocked');
      final store = FileUsageStatisticsPartitionStore(
        file: File.fromUri(
          tempDirectory.uri.resolve(
            'not-a-directory/usage_statistics_index.json',
          ),
        ),
      );

      await expectLater(
        store.writePartition(
          'codex',
          UsageStatisticsIndexPartition(
            schemaVersion: 1,
            payload: <String, Object?>{'sessions': <Object?>[]},
          ),
        ),
        throwsA(isA<IOException>()),
      );
    });
  });

  test('rejects non-JSON-safe payload values instead of stringifying them', () {
    expect(
      () => UsageStatisticsIndexPartition(
        schemaVersion: 1,
        payload: <String, Object?>{'raw': DateTime(2026)},
      ),
      throwsArgumentError,
    );
  });

  test('normalizes damaged input to an empty v4 root', () {
    expect(normalizeUsageStatisticsPartitionIndex(null), <String, Object?>{
      'version': usageStatisticsPartitionIndexVersion,
      'providers': <String, Object?>{},
    });
  });
}

File _indexFile(Directory directory) =>
    File.fromUri(directory.uri.resolve('state/usage_statistics_index.json'));

Map<String, Object?> _legacyV3() => <String, Object?>{
  'version': 3,
  'providers': <String, Object?>{
    'codex': <String, Object?>{
      'sessions': <Object?>[_safeSession('codex-source')],
    },
    'grok': <String, Object?>{
      'sessions': <Object?>[
        <String, Object?>{
          ..._safeSession('grok-source'),
          'modifiedAt': DateTime.utc(2026, 8, 12).millisecondsSinceEpoch,
        },
      ],
    },
    'future-agent': <String, Object?>{
      'sessions': <Object?>[_safeSession('future-source')],
      'unknown': true,
    },
  },
};

Map<String, Object?> _safeSession(String? sourceId) => <String, Object?>{
  'sourceId': ?sourceId,
  'fingerprint': '10:20',
  'threadId': 'thread-1',
  'projectPath': '/workspace/zeta',
  'sourceKind': 'fixture',
  'createdAt': DateTime.utc(2026, 8, 12).millisecondsSinceEpoch,
  'turns': <Object?>[],
};
