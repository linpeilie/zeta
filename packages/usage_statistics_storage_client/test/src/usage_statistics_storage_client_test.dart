import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:usage_statistics_storage_client/usage_statistics_storage_client.dart';

void main() {
  group('UsageIndexCodec', () {
    const codec = UsageIndexCodec();

    test('round-trips isolated current-schema partitions', () {
      final document = UsageIndexDocument(
        partitions: <String, UsageIndexPartition>{
          'codex:primary': UsageIndexPartition(
            schemaVersion: 2,
            payload: <String, Object?>{
              'values': <Object?>[
                1,
                true,
                null,
                <String, Object?>{'nested': 'value'},
              ],
            },
          ),
          'grok:secondary': UsageIndexPartition(
            schemaVersion: 1,
            payload: const <String, Object?>{},
          ),
        },
      );

      final encoded = codec.encode(document);
      final decoded = codec.decode(jsonDecode(jsonEncode(encoded)));

      expect(encoded['version'], usageIndexSchemaVersion);
      expect(decoded.partitions.keys, <String>[
        'codex:primary',
        'grok:secondary',
      ]);
      expect(decoded.partitions['codex:primary']?.schemaVersion, 2);
      expect(
        decoded.partitions['codex:primary']?.payload['values'],
        <Object?>[
          1,
          true,
          null,
          <String, Object?>{'nested': 'value'},
        ],
      );
    });

    test('rejects invalid roots, versions, and provider fields', () {
      final cases = <MapEntry<Object?, UsageIndexDecodeFailureCode>>[
        const MapEntry<Object?, UsageIndexDecodeFailureCode>(
          <Object?>[],
          UsageIndexDecodeFailureCode.invalidRoot,
        ),
        const MapEntry<Object?, UsageIndexDecodeFailureCode>(
          <String, Object?>{'version': 3},
          UsageIndexDecodeFailureCode.unsupportedVersion,
        ),
        const MapEntry<Object?, UsageIndexDecodeFailureCode>(
          <String, Object?>{'version': 4, 'providers': <Object?>[]},
          UsageIndexDecodeFailureCode.invalidField,
        ),
        const MapEntry<Object?, UsageIndexDecodeFailureCode>(
          <String, Object?>{
            'version': 4,
            'providers': <String, Object?>{'': <String, Object?>{}},
          },
          UsageIndexDecodeFailureCode.invalidField,
        ),
        const MapEntry<Object?, UsageIndexDecodeFailureCode>(
          <String, Object?>{
            'version': 4,
            'providers': <String, Object?>{' codex': <String, Object?>{}},
          },
          UsageIndexDecodeFailureCode.invalidField,
        ),
        const MapEntry<Object?, UsageIndexDecodeFailureCode>(
          <String, Object?>{
            'version': 4,
            'providers': <String, Object?>{'codex': 'bad'},
          },
          UsageIndexDecodeFailureCode.invalidField,
        ),
        const MapEntry<Object?, UsageIndexDecodeFailureCode>(
          <String, Object?>{
            'version': 4,
            'providers': <String, Object?>{
              'codex': <String, Object?>{
                'schemaVersion': 0,
                'payload': <String, Object?>{},
              },
            },
          },
          UsageIndexDecodeFailureCode.invalidField,
        ),
        MapEntry<Object?, UsageIndexDecodeFailureCode>(
          <String, Object?>{
            'version': 4,
            'providers': <String, Object?>{
              'codex': <String, Object?>{
                'schemaVersion': 1,
                'payload': <String, Object?>{'bad': DateTime(2026)},
              },
            },
          },
          UsageIndexDecodeFailureCode.invalidField,
        ),
      ];

      for (final item in cases) {
        expect(
          () => codec.decode(item.key),
          throwsA(
            isA<UsageIndexDecodeException>().having(
              (error) => error.code,
              'code',
              item.value,
            ),
          ),
        );
      }
    });
  });

  group('UsageIndexPartition', () {
    test('defensively freezes the root partition map', () {
      final partitions = <String, UsageIndexPartition>{
        'codex': _partition('codex'),
      };
      final document = UsageIndexDocument(partitions: partitions);

      partitions.clear();

      expect(document.partitions, contains('codex'));
      expect(
        () => document.partitions['grok'] = _partition('grok'),
        throwsUnsupportedError,
      );
      for (final key in <String>['', ' codex']) {
        expect(
          () => UsageIndexDocument(
            partitions: <String, UsageIndexPartition>{key: _partition('bad')},
          ),
          throwsArgumentError,
        );
      }
    });

    test('deep-freezes JSON-safe maps and dynamic maps', () {
      final dynamicMap = <Object?, Object?>{
        'key': <Object?>[
          1,
          <String, Object?>{'nested': true},
        ],
      };
      final partition = UsageIndexPartition(
        schemaVersion: 1,
        payload: <String, Object?>{'dynamic': dynamicMap},
      );

      dynamicMap['key'] = false;

      expect(
        partition.payload['dynamic'],
        <String, Object?>{
          'key': <Object?>[
            1,
            <String, Object?>{'nested': true},
          ],
        },
      );
      expect(
        () => partition.payload['new'] = true,
        throwsUnsupportedError,
      );
    });

    test('rejects invalid schemas, values, and dynamic keys', () {
      expect(
        () => UsageIndexPartition(
          schemaVersion: 0,
          payload: const <String, Object?>{},
        ),
        throwsArgumentError,
      );
      expect(
        () => UsageIndexPartition(
          schemaVersion: 1,
          payload: <String, Object?>{'value': DateTime(2026)},
        ),
        throwsArgumentError,
      );
      expect(
        () => UsageIndexPartition(
          schemaVersion: 1,
          payload: <String, Object?>{
            'value': <Object?, Object?>{1: 'bad'},
          },
        ),
        throwsArgumentError,
      );
    });
  });

  group('UsagePartitionStore', () {
    test(
      'returns misses for missing and blank clean-install documents',
      () async {
        final storage = _MemoryStorage();
        final store = UsagePartitionStore(storage: storage);

        expect(await store.readPartition('codex'), isNull);
        storage.value = '  ';
        expect(await store.readPartition('codex'), isNull);
        expect(storage.writes, isEmpty);
        await store.close();
      },
    );

    test(
      'serializes parallel writes without dropping provider partitions',
      () async {
        final storage = _MemoryStorage();
        final store = UsagePartitionStore(storage: storage);

        await Future.wait(<Future<void>>[
          store.writePartition('codex', _partition('codex')),
          store.writePartition('claude', _partition('claude')),
          store.writePartition('grok', _partition('grok')),
        ]);

        expect((await store.readPartition('codex'))?.payload['value'], 'codex');
        expect(
          (await store.readPartition('claude'))?.payload['value'],
          'claude',
        );
        expect((await store.readPartition('grok'))?.payload['value'], 'grok');
        expect(storage.maxConcurrentWrites, 1);
        await store.close();
      },
    );

    test(
      'clears malformed, unsupported, and semantically corrupt indexes',
      () async {
        const invalidPartition =
            '{"version":4,"providers":'
            '{"codex":{"schemaVersion":0,"payload":{}}}}';
        for (final source in <String>[
          '{not-json',
          '{"version":3,"providers":{}}',
          invalidPartition,
        ]) {
          final storage = _MemoryStorage()..value = source;
          final store = UsagePartitionStore(storage: storage);

          expect(await store.readPartition('codex'), isNull);
          expect(
            jsonDecode(storage.value!),
            <String, Object?>{'version': 4, 'providers': <String, Object?>{}},
          );
          await store.close();
        }
      },
    );

    test('delete and clear only mutate rebuildable derived data', () async {
      final storage = _MemoryStorage();
      final store = UsagePartitionStore(storage: storage);
      await store.writePartition('codex', _partition('codex'));
      await store.writePartition('grok', _partition('grok'));

      await store.deletePartition('missing');
      await store.deletePartition('codex');
      expect(await store.readPartition('codex'), isNull);
      expect(await store.readPartition('grok'), isNotNull);

      await store.clear();
      expect(await store.readPartition('grok'), isNull);
      await store.close();
    });

    test('validates source keys', () async {
      final store = UsagePartitionStore(storage: _MemoryStorage());

      for (final key in <String>['', ' codex', 'codex ']) {
        expect(() => store.readPartition(key), throwsArgumentError);
        expect(
          () => store.writePartition(key, _partition('value')),
          throwsArgumentError,
        );
        expect(() => store.deletePartition(key), throwsArgumentError);
      }
      await store.close();
    });

    test(
      'a failed write does not poison later serialized operations',
      () async {
        final storage = _MemoryStorage(failWriteCount: 1);
        final store = UsagePartitionStore(storage: storage);

        await expectLater(
          store.writePartition('codex', _partition('first')),
          throwsA(isA<StateError>()),
        );
        await store.writePartition('codex', _partition('second'));

        expect(
          (await store.readPartition('codex'))?.payload['value'],
          'second',
        );
        await store.close();
      },
    );

    test(
      'close waits for queued writes and rejects future operations',
      () async {
        final gate = Completer<void>();
        final storage = _MemoryStorage(writeGate: gate.future);
        final store = UsagePartitionStore(storage: storage);
        final write = store.writePartition('codex', _partition('value'));
        final close = store.close();
        await Future<void>.delayed(Duration.zero);
        expect(storage.isClosed, isFalse);

        gate.complete();
        await write;
        await close;
        expect(storage.isClosed, isTrue);
        await store.close();
        expect(
          () => store.readPartition('codex'),
          throwsA(isA<UsageStorageClosedException>()),
        );
        expect(
          const UsageStorageClosedException().toString(),
          'UsageStorageClosedException()',
        );
      },
    );

    test(
      'propagates storage read, corruption-clear, and close failures',
      () async {
        final readFailure = StateError('read');
        final readStore = UsagePartitionStore(
          storage: _MemoryStorage(readFailure: readFailure),
        );
        await expectLater(
          readStore.readPartition('codex'),
          throwsA(same(readFailure)),
        );

        final clearFailure = StateError('clear');
        final corruptStorage = _MemoryStorage(writeFailure: clearFailure)
          ..value = '{bad';
        final corruptStore = UsagePartitionStore(storage: corruptStorage);
        await expectLater(
          corruptStore.readPartition('codex'),
          throwsA(same(clearFailure)),
        );

        final closeFailure = StateError('close');
        final closeStore = UsagePartitionStore(
          storage: _MemoryStorage(closeFailure: closeFailure),
        );
        await expectLater(closeStore.close(), throwsA(same(closeFailure)));
      },
    );
  });

  group('UsageScanCache', () {
    test(
      'hits matching fingerprints and misses stale or forced reads',
      () async {
        final store = UsagePartitionStore(storage: _MemoryStorage());
        final cache = UsageScanCache(store: store, sourceKey: 'codex');
        final sourceId = _sourceId('source');
        final entry = UsageScanCacheEntry(
          sourceId: sourceId,
          fingerprint: '10:20',
          payload: const <String, Object?>{'tokens': 42},
        );
        await cache.write(entry);

        expect(
          (await cache.read(sourceId: sourceId, fingerprint: '10:20'))?.payload,
          <String, Object?>{'tokens': 42},
        );
        expect(
          await cache.read(sourceId: sourceId, fingerprint: '10:21'),
          isNull,
        );
        expect(
          await cache.read(
            sourceId: sourceId,
            fingerprint: '10:20',
            forceRefresh: true,
          ),
          isNull,
        );
        await store.close();
      },
    );

    test('serializes large concurrent inserts without loss', () async {
      final store = UsagePartitionStore(storage: _MemoryStorage());
      final cache = UsageScanCache(store: store, sourceKey: 'claude');

      await Future.wait(<Future<void>>[
        for (var index = 0; index < 1000; index += 1)
          cache.write(
            UsageScanCacheEntry(
              sourceId: _sourceId('source-$index'),
              fingerprint: '$index:$index',
              payload: <String, Object?>{'index': index},
            ),
          ),
      ]);

      final partition = await store.readPartition('claude');
      expect(
        partition?.payload['entries'],
        isA<Map<String, Object?>>().having(
          (entries) => entries.length,
          'length',
          1000,
        ),
      );
      await store.close();
    });

    test('invalidates entries, complete partitions, and unknown ids', () async {
      final store = UsagePartitionStore(storage: _MemoryStorage());
      final cache = UsageScanCache(store: store, sourceKey: 'grok');
      await cache.write(_cacheEntry('one'));
      await cache.write(_cacheEntry('two'));

      await cache.invalidate(_sourceId('missing'));
      await cache.invalidate(_sourceId('one'));
      expect(
        await cache.read(
          sourceId: _sourceId('one'),
          fingerprint: _fingerprint('one'),
        ),
        isNull,
      );
      expect(
        await cache.read(
          sourceId: _sourceId('two'),
          fingerprint: _fingerprint('two'),
        ),
        isNotNull,
      );

      await cache.clear();
      expect(await store.readPartition('grok'), isNull);
      await store.close();
    });

    test('clears damaged cache payloads and unknown cache schemas', () async {
      final store = UsagePartitionStore(storage: _MemoryStorage());
      final cache = UsageScanCache(store: store, sourceKey: 'codex');
      final cases = <UsageIndexPartition>[
        UsageIndexPartition(
          schemaVersion: 2,
          payload: const <String, Object?>{},
        ),
        UsageIndexPartition(
          schemaVersion: 1,
          payload: const <String, Object?>{'entries': 'bad'},
        ),
        UsageIndexPartition(
          schemaVersion: 1,
          payload: const <String, Object?>{
            'entries': <String, Object?>{'': <String, Object?>{}},
          },
        ),
        UsageIndexPartition(
          schemaVersion: 1,
          payload: <String, Object?>{
            'entries': <String, Object?>{
              _sourceId('source'): <String, Object?>{
                'fingerprint': '',
                'payload': const <String, Object?>{},
              },
            },
          },
        ),
      ];

      for (final partition in cases) {
        await store.writePartition('codex', partition);
        expect(
          await cache.read(sourceId: _sourceId('source'), fingerprint: '1:1'),
          isNull,
        );
      }
      await store.close();
    });

    test('validates entries and helper hashes remain path-free', () {
      expect(
        () => UsageScanCacheEntry(
          sourceId: '',
          fingerprint: '1:1',
          payload: const <String, Object?>{},
        ),
        throwsArgumentError,
      );
      expect(
        () => UsageScanCacheEntry(
          sourceId: '/private/path',
          fingerprint: '1:1',
          payload: const <String, Object?>{},
        ),
        throwsArgumentError,
      );
      expect(
        () => UsageScanCacheEntry(
          sourceId: _sourceId('source'),
          fingerprint: 'raw-value',
          payload: const <String, Object?>{},
        ),
        throwsArgumentError,
      );
      expect(
        () => UsageScanCache(
          store: UsagePartitionStore(storage: _MemoryStorage()),
          sourceKey: ' codex',
        ),
        throwsArgumentError,
      );
      expect(
        () => UsageScanCache(
          store: UsagePartitionStore(storage: _MemoryStorage()),
          sourceKey: 'codex',
          schemaVersion: 0,
        ),
        throwsArgumentError,
      );
      expect(() => usageSourceId(''), throwsArgumentError);
      expect(
        () => usageFileFingerprint(size: -1, modifiedMicroseconds: 0),
        throwsArgumentError,
      );
      expect(usageSourceId('/private/path'), hasLength(16));
      expect(usageSourceId('/private/path'), usageSourceId('/private/path'));
      expect(usageSourceId('/private/path'), isNot(contains('/private/path')));
      expect(
        usageFileFingerprint(size: 12, modifiedMicroseconds: 34),
        '12:34',
      );
    });

    test('a failed cache write does not poison its operation queue', () async {
      final storage = _MemoryStorage(failWriteCount: 1);
      final store = UsagePartitionStore(storage: storage);
      final cache = UsageScanCache(store: store, sourceKey: 'codex');

      await expectLater(
        cache.write(_cacheEntry('first')),
        throwsA(isA<StateError>()),
      );
      await cache.write(_cacheEntry('second'));

      expect(
        await cache.read(
          sourceId: _sourceId('second'),
          fingerprint: _fingerprint('second'),
        ),
        isNotNull,
      );
      await store.close();
    });
  });

  test('atomic usage storage persists and closes a real file', () async {
    final directory = await Directory.systemTemp.createTemp('usage_index_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}index.json');
    final storage = AtomicUsageDocumentStorage.fromFile(file);

    expect(await storage.read(), isNull);
    await storage.write('value');
    expect(await storage.read(), 'value');
    await storage.close();
    expect(storage.storage.isClosed, isTrue);
  });

  test('decode failures expose content-free FormatException metadata', () {
    const failure = UsageIndexDecodeException(
      code: UsageIndexDecodeFailureCode.invalidField,
      field: 'providers',
    );

    expect(failure.message, 'Usage index could not be decoded');
    expect(failure.offset, isNull);
    expect(failure.source, isNull);
    expect(failure.field, 'providers');
    expect(failure.toString(), isNot(contains('providers')));
  });
}

UsageIndexPartition _partition(String value) {
  return UsageIndexPartition(
    schemaVersion: 1,
    payload: <String, Object?>{'value': value},
  );
}

UsageScanCacheEntry _cacheEntry(String id) {
  return UsageScanCacheEntry(
    sourceId: _sourceId(id),
    fingerprint: _fingerprint(id),
    payload: <String, Object?>{'id': id},
  );
}

String _sourceId(String value) => usageSourceId(value);

String _fingerprint(String value) {
  return usageFileFingerprint(
    size: value.length,
    modifiedMicroseconds: value.codeUnits.fold<int>(
      0,
      (sum, unit) => sum + unit,
    ),
  );
}

final class _MemoryStorage implements UsageDocumentStorage {
  _MemoryStorage({
    this.writeGate,
    this.readFailure,
    this.writeFailure,
    this.closeFailure,
    this.failWriteCount = 0,
  });

  String? value;
  final Future<void>? writeGate;
  final Object? readFailure;
  final Object? writeFailure;
  final Object? closeFailure;
  int failWriteCount;
  final List<String> writes = <String>[];
  int activeWrites = 0;
  int maxConcurrentWrites = 0;
  bool isClosed = false;

  @override
  Future<String?> read() async {
    if (readFailure case final failure?) {
      _throwFailure(failure);
    }
    return value;
  }

  @override
  Future<void> write(String contents) async {
    activeWrites += 1;
    if (activeWrites > maxConcurrentWrites) {
      maxConcurrentWrites = activeWrites;
    }
    try {
      await writeGate;
      if (failWriteCount > 0) {
        failWriteCount -= 1;
        throw StateError('planned write failure');
      }
      if (writeFailure case final failure?) {
        _throwFailure(failure);
      }
      writes.add(contents);
      value = contents;
    } finally {
      activeWrites -= 1;
    }
  }

  @override
  Future<void> close() async {
    isClosed = true;
    if (closeFailure case final failure?) {
      _throwFailure(failure);
    }
  }
}

Never _throwFailure(Object failure) {
  if (failure is Exception) {
    throw failure;
  }
  if (failure is Error) {
    throw failure;
  }
  throw StateError('Invalid test failure');
}
