import 'dart:convert';
import 'dart:io';

import 'package:grok_acp_client/grok_acp_client.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('grok_usage_');
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test('default reader discovers and projects Grok turn usage', () async {
    final at = DateTime.utc(2026, 8, 20, 1);
    final file = await _writeGrokSession(
      home: tempDirectory,
      projectKey: Uri.encodeComponent('/encoded/project'),
      threadId: 'thread-1',
      projectPath: '/canonical/project',
      at: at,
    );
    final reader = GrokUsageReader(grokHome: tempDirectory.path);

    final result = await reader.scan(
      startInclusive: at,
      endExclusive: at.add(const Duration(hours: 1)),
    );

    expect(result.localSourceCount, 1);
    expect(result.unreadableSourceCount, 0);
    final source = result.sources.single;
    expect(source.sourcePath, file.path);
    expect(source.fingerprint, startsWith('${await file.length()}:'));
    expect(source.threadId, 'thread-1');
    expect(source.projectPath, '/canonical/project');
    expect(source.modifiedAt, isNotNull);
    final turn = source.turns.single;
    expect(turn.status, isNotEmpty);
    expect(turn.startedAt, at);
    expect(turn.completedAt, at.add(const Duration(milliseconds: 200)));
    expect(turn.inputTokens, 60);
    expect(turn.cachedInputTokens, 40);
    expect(turn.outputTokens, 20);
    expect(turn.reasoningTokens, 5);
    expect(turn.totalTokens, 120);
  });

  test('falls back to encoded project directories and damaged names', () async {
    final at = DateTime.utc(2026, 8, 20, 1);
    await _writeGrokSession(
      home: tempDirectory,
      projectKey: Uri.encodeComponent('/encoded/project'),
      threadId: 'thread-1',
      at: at,
      summaryContents: '{bad',
    );
    await _writeGrokSession(
      home: tempDirectory,
      projectKey: '%',
      threadId: 'thread-2',
      at: at,
    );
    final reader = GrokUsageReader(grokHome: tempDirectory.path);

    final result = await reader.scan(
      startInclusive: at,
      endExclusive: at.add(const Duration(hours: 1)),
    );

    expect(
      result.sources.map((source) => source.projectPath),
      unorderedEquals(<String>['%', '/encoded/project']),
    );
  });

  test('falls back when a project summary cannot be read', () async {
    final at = DateTime.utc(2026, 8, 20, 1);
    await _writeGrokSession(
      home: tempDirectory,
      projectKey: Uri.encodeComponent('/encoded/project'),
      threadId: 'thread-1',
      projectPath: '/canonical/project',
      at: at,
    );
    final reader = GrokUsageReader(
      grokHome: tempDirectory.path,
      readFile: (file) {
        if (file.path.endsWith('summary.json')) {
          throw const FileSystemException('denied');
        }
        return file.readAsString();
      },
    );

    final result = await reader.scan(
      startInclusive: at,
      endExclusive: at.add(const Duration(hours: 1)),
    );

    expect(result.sources.single.projectPath, '/encoded/project');
  });

  test('uses half-open boundaries and sorts discovered sources', () async {
    final files = <File>[
      await File('${tempDirectory.path}${Platform.pathSeparator}z.jsonl')
          .writeAsString('z'),
      await File('${tempDirectory.path}${Platform.pathSeparator}a.jsonl')
          .writeAsString('a'),
      await File('${tempDirectory.path}${Platform.pathSeparator}n.jsonl')
          .writeAsString('n'),
    ];
    final start = DateTime.utc(2026, 8, 20);
    final end = start.add(const Duration(hours: 1));
    final reader = GrokUsageReader(
      grokHome: tempDirectory.path,
      discoverFiles: (_) => Stream<File>.fromIterable(files),
      loadSource: (file) async {
        if (file.path.endsWith('n.jsonl')) {
          return null;
        }
        return GrokUsageLoadedSource(
          threadId: file.path,
          projectPath: '/project',
          turns: <GrokUsageTurnResponse>[
            _turn('start', startedAt: start),
            _turn('end', completedAt: end),
            _turn('unknown'),
          ],
        );
      },
    );

    final result = await reader.scan(
      startInclusive: start,
      endExclusive: end,
    );

    expect(result.localSourceCount, 2);
    expect(result.unreadableSourceCount, 1);
    expect(result.sources.map((source) => source.sourcePath), <String>[
      files[1].path,
      files[0].path,
    ]);
    expect(
      result.sources.expand((source) => source.turns).map((turn) => turn.id),
      <String>['start', 'start'],
    );

    final empty = await reader.scan(
      startInclusive: end.add(const Duration(hours: 1)),
      endExclusive: end.add(const Duration(hours: 2)),
    );
    expect(empty.localSourceCount, 2);
    expect(empty.sources, isEmpty);
  });

  test('counts per-source filesystem and format failures', () async {
    final files = <File>[
      File('${tempDirectory.path}${Platform.pathSeparator}format.jsonl'),
      File('${tempDirectory.path}${Platform.pathSeparator}filesystem.jsonl'),
    ];
    final reader = GrokUsageReader(
      grokHome: tempDirectory.path,
      discoverFiles: (_) => Stream<File>.fromIterable(files),
      loadSource: (file) async {
        if (file.path.contains('format')) {
          throw const FormatException();
        }
        throw const FileSystemException('denied');
      },
    );

    final result = await reader.scan(
      startInclusive: DateTime.utc(2026),
      endExclusive: DateTime.utc(2027),
    );

    expect(result.localSourceCount, 0);
    expect(result.unreadableSourceCount, 2);
    expect(result.sources, isEmpty);
  });

  test('returns empty when sessions root is absent', () async {
    final reader = GrokUsageReader(grokHome: tempDirectory.path);

    final result = await reader.scan(
      startInclusive: DateTime.utc(2026),
      endExclusive: DateTime.utc(2027),
    );

    expect(result.sources, isEmpty);
    expect(result.localSourceCount, 0);
  });

  test('cooperatively cancels a 1000-source scan', () async {
    var visited = 0;
    var cancelled = false;
    final reader = GrokUsageReader(
      grokHome: tempDirectory.path,
      discoverFiles: (_) => Stream<File>.fromIterable(<File>[
        for (var index = 0; index < 1000; index += 1)
          File('${tempDirectory.path}${Platform.pathSeparator}$index.jsonl'),
      ]),
      loadSource: (file) async {
        visited += 1;
        if (visited == 5) {
          cancelled = true;
        }
        return GrokUsageLoadedSource(
          threadId: '$visited',
          projectPath: '/project',
          turns: <GrokUsageTurnResponse>[
            _turn('turn', startedAt: DateTime.utc(2026, 8, 20)),
          ],
        );
      },
    );

    await expectLater(
      reader.scan(
        startInclusive: DateTime.utc(2026),
        endExclusive: DateTime.utc(2027),
        isCancelled: () => cancelled,
      ),
      throwsA(isA<GrokUsageScanCancelledException>()),
    );
    expect(visited, 5);
    expect(
      const GrokUsageScanCancelledException().toString(),
      'GrokUsageScanCancelledException()',
    );
  });

  test('rejects invalid time windows and exposes whitelisted fields', () async {
    final reader = GrokUsageReader(grokHome: tempDirectory.path);
    final at = DateTime.utc(2026);

    await expectLater(
      reader.scan(startInclusive: at, endExclusive: at),
      throwsArgumentError,
    );
    final turn = _turn('turn', startedAt: at, completedAt: at);
    expect(turn.id, 'turn');
    expect(turn.duration, const Duration(seconds: 1));
    expect(turn.timeToFirstToken, const Duration(milliseconds: 20));
    expect(turn.cwd, '/project');
    expect(turn.model, 'grok-model');
  });
}

GrokUsageTurnResponse _turn(
  String id, {
  DateTime? startedAt,
  DateTime? completedAt,
}) {
  return GrokUsageTurnResponse(
    id: id,
    status: 'completed',
    startedAt: startedAt,
    completedAt: completedAt,
    duration: const Duration(seconds: 1),
    timeToFirstToken: const Duration(milliseconds: 20),
    cwd: '/project',
    model: 'grok-model',
    inputTokens: 1,
    cachedInputTokens: 2,
    outputTokens: 3,
    reasoningTokens: 4,
    totalTokens: 10,
  );
}

Future<File> _writeGrokSession({
  required Directory home,
  required String projectKey,
  required String threadId,
  required DateTime at,
  String? projectPath,
  String? summaryContents,
}) async {
  final directory = await Directory(
    '${home.path}${Platform.pathSeparator}sessions'
    '${Platform.pathSeparator}$projectKey'
    '${Platform.pathSeparator}$threadId',
  ).create(recursive: true);
  if (projectPath != null || summaryContents != null) {
    await File(
      '${directory.path}${Platform.pathSeparator}summary.json',
    ).writeAsString(
      summaryContents ??
          jsonEncode(<String, Object?>{
            'info': <String, Object?>{'cwd': projectPath},
          }),
    );
  }
  final timestamp = at.millisecondsSinceEpoch;
  final updates = <Map<String, Object?>>[
    <String, Object?>{
      'timestamp': timestamp ~/ Duration.millisecondsPerSecond,
      'method': 'session/update',
      'params': <String, Object?>{
        'sessionId': threadId,
        'update': <String, Object?>{
          'sessionUpdate': 'user_message_chunk',
          'content': <String, Object?>{'type': 'text', 'text': 'redacted'},
        },
        '_meta': <String, Object?>{
          'eventId': '$threadId-user',
          'agentTimestampMs': timestamp,
        },
      },
    },
    <String, Object?>{
      'timestamp': timestamp ~/ Duration.millisecondsPerSecond,
      'method': '_x.ai/session/update',
      'params': <String, Object?>{
        'sessionId': threadId,
        'update': <String, Object?>{
          'sessionUpdate': 'turn_completed',
          'stop_reason': 'end_turn',
          'usage': <String, Object?>{
            'inputTokens': 100,
            'cachedReadTokens': 40,
            'outputTokens': 20,
            'reasoningTokens': 5,
            'totalTokens': 120,
          },
        },
        '_meta': <String, Object?>{
          'eventId': '$threadId-complete',
          'agentTimestampMs': timestamp + 200,
        },
      },
    },
  ];
  return File(
    '${directory.path}${Platform.pathSeparator}updates.jsonl',
  )..writeAsStringSync(updates.map(jsonEncode).join('\n'));
}
