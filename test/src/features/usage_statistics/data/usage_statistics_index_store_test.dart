import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/storage/file_storage_service.dart';
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
        final store = FileUsageStatisticsPartitionStore(
          storage: FileStorageService(file),
        );
        final codex = UsageStatisticsIndexPartition(
          schemaVersion: 1,
          payload: <String, Object?>{
            'sessions': <Object?>[
              <String, Object?>{'sourceId': 'codex-source'},
            ],
          },
        );

        await store.writePartition('codex-work', codex);

        final reloaded = await FileUsageStatisticsPartitionStore(
          storage: FileStorageService(file),
        ).readPartition('codex-work');
        final unknown = await FileUsageStatisticsPartitionStore(
          storage: FileStorageService(file),
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
      'damaged JSON and damaged partitions degrade without blocking valid data',
      () async {
        final file = _indexFile(tempDirectory);
        await file.parent.create(recursive: true);
        await file.writeAsString('{damaged');
        final store = FileUsageStatisticsPartitionStore(
          storage: FileStorageService(file),
        );
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
          storage: FileStorageService(file),
        ).readPartition('codex'),
        isNull,
      );
    });

    test('unsupported root versions degrade to an empty index', () async {
      final file = _indexFile(tempDirectory);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'version': usageStatisticsPartitionIndexVersion - 1,
          'providers': <String, Object?>{
            'codex': <String, Object?>{
              'schemaVersion': 1,
              'payload': <String, Object?>{},
            },
          },
        }),
      );

      expect(
        await FileUsageStatisticsPartitionStore(
          storage: FileStorageService(file),
        ).readPartition('codex'),
        isNull,
      );
    });

    test('parallel partition writes do not drop either source', () async {
      final store = FileUsageStatisticsPartitionStore(
        storage: FileStorageService(_indexFile(tempDirectory)),
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
        storage: FileStorageService(
          File.fromUri(
            tempDirectory.uri.resolve(
              'not-a-directory/usage_statistics_index.json',
            ),
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
}

File _indexFile(Directory directory) =>
    File.fromUri(directory.uri.resolve('state/usage_statistics_index.json'));
