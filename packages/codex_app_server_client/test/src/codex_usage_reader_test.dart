// Async filesystem calls keep these integration-style vendor reader tests
// deterministic across platforms.
// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codex_app_server_client/codex_app_server_client.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('codex_usage_');
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test(
    'discovers rollouts and projects exact half-open usage samples',
    () async {
      final start = DateTime.utc(2026, 8, 20, 1);
      final end = start.add(const Duration(hours: 1));
      final ignored = File(
        '${tempDirectory.path}${Platform.pathSeparator}sessions'
        '${Platform.pathSeparator}ignored.jsonl',
      );
      await ignored.parent.create(recursive: true);
      await ignored.writeAsString('{}');
      final file = await _writeRollout(tempDirectory, <Object?>[
        _meta(at: start),
        _event('task_started', at: start),
        <String, Object?>{
          'timestamp': start.toIso8601String(),
          'type': 'turn_context',
          'payload': <String, Object?>{
            'turn_id': 'turn-1',
            'cwd': '/turn/project',
            'model': 'gpt-5.6',
          },
        },
        _token(
          at: start,
          total: _usage(120, 40, 30, 5, 150),
          last: _usage(120, 40, 30, 5, 150),
        ),
        _token(
          at: start.add(const Duration(seconds: 1)),
          total: _usage(120, 40, 30, 5, 150),
          last: _usage(1, 0, 1, 0, 2),
        ),
        _token(
          at: end,
          total: _usage(150, 50, 40, 8, 190),
          last: _usage(30, 10, 10, 3, 40),
        ),
        _event('task_complete', at: end),
      ]);
      final reader = CodexUsageReader(codexHome: tempDirectory.path);

      final result = await reader.scan(
        startInclusive: start,
        endExclusive: end,
      );

      expect(result.localSourceCount, 1);
      expect(result.unreadableSourceCount, 0);
      expect(result.discoveryFailureCount, 0);
      final source = result.sources.single;
      expect(source.sourcePath, file.path);
      expect(source.fingerprint, startsWith('${await file.length()}:'));
      expect(source.threadId, 'thread-1');
      expect(source.projectPath, '/workspace/project');
      expect(source.sourceKind, 'codex_cli_rs');
      expect(source.createdAt, start);
      expect(source.modifiedAt, isNotNull);
      final turn = source.turns.single;
      expect(turn.id, 'turn-1');
      expect(turn.status, 'completed');
      expect(turn.cwd, '/turn/project');
      expect(turn.model, 'gpt-5.6');
      expect(turn.samples, hasLength(1));
      expect(turn.samples.single.inputTokens, 80);
      expect(turn.samples.single.cachedInputTokens, 40);
      expect(turn.samples.single.outputTokens, 25);
      expect(turn.samples.single.reasoningTokens, 5);
      expect(turn.samples.single.totalTokens, 150);
      expect(
        turn.samples.single.deduplicationKey,
        startsWith('codex:thread-1:'),
      );
    },
  );

  test('uses deltas, skips fork replay, and clamps counter resets', () async {
    final at = DateTime.utc(2026, 8, 20, 1);
    await _writeRollout(tempDirectory, <Object?>[
      _meta(at: at, forkedFromId: 'parent-1'),
      _event('task_started', at: at.add(const Duration(seconds: 1))),
      _token(
        at: at.add(const Duration(seconds: 2)),
        total: _usage(40, 10, 8, 2, 50),
        last: _usage(40, 10, 8, 2, 50),
      ),
      _token(
        at: at.add(const Duration(seconds: 6)),
        total: _usage(70, 15, 15, 5, 90),
        last: _usage(30, 5, 7, 3, 40),
      ),
      _token(
        at: at.add(const Duration(seconds: 7)),
        total: _usage(100, 20, 25, 8, 130),
      ),
      _token(
        at: at.add(const Duration(milliseconds: 7500)),
        total: _usage(110, 22, 30, 9, 145),
        last: <String, Object?>{
          'input_tokens': 10,
          'cached_input_tokens': 2,
          'output_tokens': 5,
          'reasoning_output_tokens': 1,
        },
      ),
      _token(
        at: at.add(const Duration(seconds: 8)),
        total: _usage(1, 0, 0, 0, 1),
      ),
    ]);

    final result =
        await CodexUsageReader(
          codexHome: tempDirectory.path,
        ).scan(
          startInclusive: at,
          endExclusive: at.add(const Duration(minutes: 1)),
        );
    final samples = result.sources.single.turns.single.samples;

    expect(samples, hasLength(3));
    expect(samples.first.deduplicationKey, startsWith('codex:parent-1:'));
    expect(samples.first.inputTokens, 25);
    expect(samples.first.outputTokens, 4);
    expect(samples.first.reasoningTokens, 3);
    expect(samples[1].inputTokens, 25);
    expect(samples[1].cachedInputTokens, 5);
    expect(samples[1].outputTokens, 7);
    expect(samples[1].reasoningTokens, 3);
    expect(samples[1].totalTokens, 40);
    expect(samples.last.totalTokens, 15);
  });

  test(
    'handles legacy turn ids, lifecycle records, and safe fallbacks',
    () async {
      final at = DateTime.utc(2026, 8, 20, 1);
      final file = await _writeRollout(
        tempDirectory,
        <Object?>[
          <String, Object?>{
            'type': 'session_meta',
            'payload': <String, Object?>{
              'timestamp': at.millisecondsSinceEpoch ~/ 1000,
            },
          },
          '{malformed',
          42,
          <String, Object?>{'type': 'unknown', 'payload': <String, Object?>{}},
          <String, Object?>{
            'timestamp': at.add(const Duration(seconds: 1)).toIso8601String(),
            'type': 'response_item',
            'payload': <String, Object?>{'type': 'message', 'role': 'user'},
          },
          <String, Object?>{
            'timestamp': at.add(const Duration(seconds: 2)).toIso8601String(),
            'type': 'turn_context',
            'payload': <String, Object?>{
              'internal_chat_message_metadata_passthrough': <String, Object?>{
                'turn_id': 'legacy-turn',
              },
              'cwd': '/legacy',
              'model': 'gpt-legacy',
            },
          },
          _token(
            at: null,
            total: <String, Object?>{
              'input_tokens': '5',
              'cached_input_tokens': 1.0,
              'output_tokens': 3,
              'reasoning_output_tokens': 1,
              'total_tokens': '8',
            },
            turnId: null,
            recordTurnId: 'legacy-turn',
          ),
          <String, Object?>{
            'timestamp': at
                .add(const Duration(milliseconds: 2500))
                .toIso8601String(),
            'type': 'response_item',
            'payload': <String, Object?>{'type': 'message', 'role': 'user'},
          },
          _event(
            'turn_aborted',
            at: at.add(const Duration(seconds: 3)),
            turnId: 'legacy-turn',
          ),
          <String, Object?>{
            'timestamp': at.add(const Duration(seconds: 4)).toIso8601String(),
            'type': 'response_item',
            'payload': <String, Object?>{'type': 'message', 'role': 'user'},
          },
          _token(
            at: at.add(const Duration(seconds: 5)),
            total: _usage(10, 2, 4, 1, 13),
            last: _usage(5, 1, 2, 0, 7),
          ),
          _event(
            'error',
            at: at.add(const Duration(seconds: 6)),
            turnId: 'ignored-error-turn',
          ),
          <String, Object?>{
            'timestamp': at.add(const Duration(seconds: 7)).toIso8601String(),
            'type': 'other',
            'payload': <String, Object?>{'value': true},
          },
        ],
        name: 'rollout-fallback.jsonl',
      );

      final result =
          await CodexUsageReader(
            codexHome: tempDirectory.path,
          ).scan(
            startInclusive: at,
            endExclusive: at.add(const Duration(minutes: 1)),
          );

      final source = result.sources.single;
      expect(source.threadId, 'rollout-fallback');
      expect(source.projectPath, 'unknown');
      expect(source.sourceKind, 'codex');
      expect(source.turns.expand((turn) => turn.samples), hasLength(2));
      expect(source.turns.first.status, 'interrupted');
      expect(source.turns.first.cwd, '/legacy');
      expect(source.turns.first.model, 'gpt-legacy');
      expect(source.turns.first.samples.single.timestamp, at);
      expect(source.turns.first.samples.single.inputTokens, 4);
      expect(source.sourcePath, file.path);
    },
  );

  test('counts invalid, unreadable, and format-failing sources', () async {
    final files = <File>[];
    for (final entry in <MapEntry<String, Object?>>[
      const MapEntry<String, Object?>('malformed', '{broken'),
      const MapEntry<String, Object?>('not-meta', <String, Object?>{
        'type': 'event_msg',
      }),
      const MapEntry<String, Object?>('no-time', <String, Object?>{
        'type': 'session_meta',
        'payload': <String, Object?>{'session_id': 'missing-time'},
      }),
    ]) {
      files.add(
        await _writeRollout(
          tempDirectory,
          <Object?>[entry.value],
          name: 'rollout-${entry.key}.jsonl',
        ),
      );
    }
    files
      ..add(File('${tempDirectory.path}${Platform.pathSeparator}io.jsonl'))
      ..add(
        File('${tempDirectory.path}${Platform.pathSeparator}format.jsonl'),
      );
    final reader = CodexUsageReader(
      codexHome: tempDirectory.path,
      discoverFiles: (_) => Stream<File>.fromIterable(files),
      readLines: (file) {
        if (file.path.endsWith('io.jsonl')) {
          throw const FileSystemException('denied');
        }
        if (file.path.endsWith('format.jsonl')) {
          throw const FormatException();
        }
        return file
            .openRead()
            .transform(utf8.decoder)
            .transform(
              const LineSplitter(),
            );
      },
    );

    final result = await reader.scan(
      startInclusive: DateTime.utc(2026),
      endExclusive: DateTime.utc(2027),
    );

    expect(result.sources, isEmpty);
    expect(result.localSourceCount, 0);
    expect(result.unreadableSourceCount, 5);
  });

  test(
    'sorts seams, distinguishes empty windows, and freezes responses',
    () async {
      final at = DateTime.utc(2026, 8, 20, 1);
      final files = <File>[
        await File('${tempDirectory.path}${Platform.pathSeparator}z.jsonl')
            .writeAsString('z'),
        await File('${tempDirectory.path}${Platform.pathSeparator}a.jsonl')
            .writeAsString('a'),
        await File('${tempDirectory.path}${Platform.pathSeparator}null.jsonl')
            .writeAsString('null'),
        await File('${tempDirectory.path}${Platform.pathSeparator}stat.jsonl')
            .writeAsString('stat'),
      ];
      final samples = <CodexUsageSampleResponse>[_sample(at)];
      final turns = <CodexUsageTurnResponse>[
        CodexUsageTurnResponse(
          id: 'turn',
          status: 'completed',
          startedAt: at,
          completedAt: at,
          cwd: '/project',
          model: 'gpt-test',
          samples: samples,
        ),
      ];
      final loaded = CodexUsageLoadedSource(
        threadId: 'thread',
        projectPath: '/project',
        sourceKind: 'test',
        createdAt: at,
        turns: turns,
      );
      final reader = CodexUsageReader(
        codexHome: tempDirectory.path,
        discoverFiles: (_) => Stream<File>.fromIterable(files),
        loadSource: (file, {isCancelled}) async {
          if (file.path.endsWith('null.jsonl')) {
            return null;
          }
          return loaded;
        },
        statFile: (file) {
          if (file.path.endsWith('stat.jsonl')) {
            throw const FileSystemException('denied');
          }
          return file.stat();
        },
      );

      final result = await reader.scan(
        startInclusive: at,
        endExclusive: at.add(const Duration(seconds: 1)),
      );
      samples.clear();
      turns.clear();

      expect(result.localSourceCount, 3);
      expect(result.unreadableSourceCount, 2);
      expect(result.sources.map((source) => source.sourcePath), <String>[
        files[1].path,
        files[0].path,
      ]);
      expect(result.sources.first.turns.single.samples, hasLength(1));
      expect(result.sources.clear, throwsUnsupportedError);
      expect(
        () => result.sources.first.turns.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => result.sources.first.turns.single.samples.clear(),
        throwsUnsupportedError,
      );

      final empty = await reader.scan(
        startInclusive: at.add(const Duration(days: 1)),
        endExclusive: at.add(const Duration(days: 2)),
      );
      expect(empty.localSourceCount, 3);
      expect(empty.sources, isEmpty);
    },
  );

  test('reports discovery failure after retaining discovered files', () async {
    final at = DateTime.utc(2026, 8, 20, 1);
    final file = await File(
      '${tempDirectory.path}${Platform.pathSeparator}one.jsonl',
    ).writeAsString('one');
    final reader = CodexUsageReader(
      codexHome: tempDirectory.path,
      discoverFiles: (_) async* {
        yield file;
        throw const FileSystemException('traversal failed');
      },
      loadSource: (file, {isCancelled}) async => _loaded(at),
    );

    final result = await reader.scan(
      startInclusive: at,
      endExclusive: at.add(const Duration(seconds: 1)),
    );

    expect(result.discoveryFailureCount, 1);
    expect(result.sources, hasLength(1));
  });

  test('cooperatively cancels discovery, loading, lines, and stat', () async {
    final at = DateTime.utc(2026, 8, 20, 1);
    final file = await File(
      '${tempDirectory.path}${Platform.pathSeparator}one.jsonl',
    ).writeAsString('one');

    await expectLater(
      CodexUsageReader(
        codexHome: tempDirectory.path,
        discoverFiles: (_) => Stream<File>.value(file),
      ).scan(
        startInclusive: at,
        endExclusive: at.add(const Duration(seconds: 1)),
        isCancelled: () => true,
      ),
      throwsA(isA<CodexUsageScanCancelledException>()),
    );

    var cancelled = false;
    await expectLater(
      CodexUsageReader(
        codexHome: tempDirectory.path,
        discoverFiles: (_) => Stream<File>.value(file),
        loadSource: (file, {isCancelled}) async {
          cancelled = true;
          return _loaded(at);
        },
      ).scan(
        startInclusive: at,
        endExclusive: at.add(const Duration(seconds: 1)),
        isCancelled: () => cancelled,
      ),
      throwsA(isA<CodexUsageScanCancelledException>()),
    );

    var checks = 0;
    await expectLater(
      CodexUsageReader(
        codexHome: tempDirectory.path,
        discoverFiles: (_) => Stream<File>.value(file),
        readLines: (_) => Stream<String>.fromIterable(<String>[
          jsonEncode(_meta(at: at)),
          for (var index = 0; index < 1000; index += 1) '{}',
        ]),
      ).scan(
        startInclusive: at,
        endExclusive: at.add(const Duration(seconds: 1)),
        isCancelled: () => ++checks >= 8,
      ),
      throwsA(isA<CodexUsageScanCancelledException>()),
    );

    cancelled = false;
    await expectLater(
      CodexUsageReader(
        codexHome: tempDirectory.path,
        discoverFiles: (_) => Stream<File>.value(file),
        loadSource: (file, {isCancelled}) async => _loaded(at),
        statFile: (file) async {
          final stat = await file.stat();
          cancelled = true;
          return stat;
        },
      ).scan(
        startInclusive: at,
        endExclusive: at.add(const Duration(seconds: 1)),
        isCancelled: () => cancelled,
      ),
      throwsA(isA<CodexUsageScanCancelledException>()),
    );
    expect(
      const CodexUsageScanCancelledException().toString(),
      'CodexUsageScanCancelledException()',
    );
  });

  test('rejects invalid ranges and returns empty for a missing root', () async {
    final at = DateTime.utc(2026);
    final reader = CodexUsageReader(codexHome: tempDirectory.path);

    await expectLater(
      reader.scan(startInclusive: at, endExclusive: at),
      throwsArgumentError,
    );
    await expectLater(
      reader.scan(
        startInclusive: at,
        endExclusive: at.subtract(const Duration(seconds: 1)),
      ),
      throwsArgumentError,
    );
    final result = await reader.scan(
      startInclusive: at,
      endExclusive: at.add(const Duration(days: 1)),
    );
    expect(result.sources, isEmpty);
    expect(result.localSourceCount, 0);
  });
}

Future<File> _writeRollout(
  Directory home,
  List<Object?> records, {
  String name = 'rollout-test.jsonl',
}) async {
  final directory = await Directory(
    '${home.path}${Platform.pathSeparator}sessions'
    '${Platform.pathSeparator}2026${Platform.pathSeparator}08'
    '${Platform.pathSeparator}20',
  ).create(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsString(
    '${records.map(
      (record) => record is String ? record : jsonEncode(record),
    ).join('\n')}\n',
  );
  return file;
}

Map<String, Object?> _meta({
  required DateTime at,
  String? forkedFromId,
}) {
  return <String, Object?>{
    'timestamp': at.toIso8601String(),
    'type': 'session_meta',
    'payload': <String, Object?>{
      'session_id': 'thread-1',
      'forked_from_id': forkedFromId,
      'cwd': '/workspace/project',
      'originator': 'codex_cli_rs',
      'model': 'gpt-5',
    },
  };
}

Map<String, Object?> _event(
  String type, {
  required DateTime at,
  String turnId = 'turn-1',
}) {
  return <String, Object?>{
    'timestamp': at.toIso8601String(),
    'type': 'event_msg',
    'payload': <String, Object?>{'type': type, 'turn_id': turnId},
  };
}

Map<String, Object?> _token({
  required DateTime? at,
  required Map<String, Object?> total,
  Map<String, Object?>? last,
  String? turnId = 'turn-1',
  String? recordTurnId,
}) {
  return <String, Object?>{
    if (at != null) 'timestamp': at.toIso8601String(),
    'type': 'event_msg',
    if (recordTurnId != null)
      'internal_chat_message_metadata_passthrough': <String, Object?>{
        'turn_id': recordTurnId,
      },
    'payload': <String, Object?>{
      'type': 'token_count',
      'turn_id': ?turnId,
      'info': <String, Object?>{
        'total_token_usage': total,
        'last_token_usage': ?last,
      },
    },
  };
}

Map<String, Object?> _usage(
  int input,
  int cached,
  int output,
  int reasoning,
  int total,
) {
  return <String, Object?>{
    'input_tokens': input,
    'cached_input_tokens': cached,
    'output_tokens': output,
    'reasoning_output_tokens': reasoning,
    'total_tokens': total,
  };
}

CodexUsageSampleResponse _sample(DateTime at) {
  return CodexUsageSampleResponse(
    deduplicationKey: 'codex:test:1',
    timestamp: at,
    inputTokens: 1,
    cachedInputTokens: 2,
    outputTokens: 3,
    reasoningTokens: 4,
    totalTokens: 10,
  );
}

CodexUsageLoadedSource _loaded(DateTime at) {
  return CodexUsageLoadedSource(
    threadId: 'thread',
    projectPath: '/project',
    sourceKind: 'test',
    createdAt: at,
    turns: <CodexUsageTurnResponse>[
      CodexUsageTurnResponse(
        id: 'turn',
        status: 'completed',
        samples: <CodexUsageSampleResponse>[_sample(at)],
      ),
    ],
  );
}
