import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:claude_code_client/claude_code_client.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('claude_usage_');
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test(
    'default reader discovers and projects a current Claude JSONL source',
    () async {
      const projectPath = '/workspace/project';
      const sessionId = 'session-1';
      final projectDirectory = await Directory(
        '${tempDirectory.path}${Platform.pathSeparator}projects'
        '${Platform.pathSeparator}-workspace-project',
      ).create(recursive: true);
      final file = File(
        '${projectDirectory.path}${Platform.pathSeparator}$sessionId.jsonl',
      );
      await file.writeAsString(
        '${jsonEncode(<String, Object?>{
          'type': 'user',
          'sessionId': sessionId,
          'uuid': 'user-1',
          'timestamp': '2026-08-10T05:00:00.000Z',
          'cwd': projectPath,
          'message': <String, Object?>{
            'role': 'user',
            'content': '[PROMPT_REDACTED]',
          },
        })}\n'
        '${jsonEncode(<String, Object?>{
          'type': 'assistant',
          'sessionId': sessionId,
          'uuid': 'assistant-1',
          'timestamp': '2026-08-10T05:00:01.000Z',
          'message': <String, Object?>{
            'role': 'assistant',
            'model': 'claude-test',
            'stop_reason': 'end_turn',
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': '[RESPONSE_REDACTED]'},
            ],
            'usage': <String, Object?>{
              'input_tokens': 3,
              'output_tokens': 2,
              'cache_creation_input_tokens': 5,
              'cache_read_input_tokens': 7,
            },
          },
        })}\n',
      );
      final reader = ClaudeCodeUsageReader(claudeHome: tempDirectory.path);

      final result = await reader.scan(
        startInclusive: DateTime.utc(2026, 8, 10, 5),
        endExclusive: DateTime.utc(2026, 8, 10, 6),
      );

      expect(result.localSourceCount, 1);
      final source = result.sources.single;
      expect(source.sourcePath, file.path);
      expect(source.fingerprint, startsWith('${await file.length()}:'));
      expect(source.threadId, sessionId);
      expect(source.projectPath, projectPath);
      expect(source.modifiedAt, isNotNull);
      final turn = source.turns.single;
      expect(turn.id, isNotEmpty);
      expect(turn.status, isNotEmpty);
      expect(turn.startedAt, DateTime.utc(2026, 8, 10, 5));
      expect(turn.completedAt, DateTime.utc(2026, 8, 10, 5, 0, 1));
      expect(turn.model, 'claude-test');
      expect(turn.inputTokens, 3);
      expect(turn.cachedInputTokens, 12);
      expect(turn.outputTokens, 2);
      expect(turn.tokenUsageIsSessionCumulative, isFalse);
    },
  );

  test(
    'uses half-open time boundaries and distinguishes empty windows',
    () async {
      final files = <File>[
        await File('${tempDirectory.path}${Platform.pathSeparator}one.jsonl')
            .writeAsString('one'),
        await File('${tempDirectory.path}${Platform.pathSeparator}two.jsonl')
            .writeAsString('two'),
      ];
      final start = DateTime.utc(2026, 8, 20);
      final end = start.add(const Duration(hours: 1));
      var loaded = 0;
      final reader = ClaudeCodeUsageReader(
        claudeHome: tempDirectory.path,
        discoverFiles: (_) => Stream<File>.fromIterable(files),
        loadSource: (file) async {
          loaded += 1;
          if (file.path.endsWith('one.jsonl')) {
            return null;
          }
          return ClaudeCodeUsageLoadedSource(
            threadId: 'thread',
            projectPath: '/project',
            turns: <ClaudeCodeUsageTurnResponse>[
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

      expect(loaded, 2);
      expect(result.localSourceCount, 1);
      expect(result.sources.single.turns.map((turn) => turn.id), <String>[
        'start',
      ]);

      final empty = await reader.scan(
        startInclusive: end.add(const Duration(hours: 1)),
        endExclusive: end.add(const Duration(hours: 2)),
      );
      expect(empty.localSourceCount, 1);
      expect(empty.sources, isEmpty);
    },
  );

  test('returns no sources when the Claude projects root is absent', () async {
    final reader = ClaudeCodeUsageReader(claudeHome: tempDirectory.path);

    final result = await reader.scan(
      startInclusive: DateTime.utc(2026),
      endExclusive: DateTime.utc(2027),
    );

    expect(result.localSourceCount, 0);
    expect(result.sources, isEmpty);
  });

  test('cooperatively cancels a 1000-source scan', () async {
    var visited = 0;
    var cancelled = false;
    final reader = ClaudeCodeUsageReader(
      claudeHome: tempDirectory.path,
      discoverFiles: (_) => Stream<File>.fromIterable(<File>[
        for (var index = 0; index < 1000; index += 1)
          File('${tempDirectory.path}${Platform.pathSeparator}$index.jsonl'),
      ]),
      loadSource: (file) async {
        visited += 1;
        if (visited == 5) {
          cancelled = true;
        }
        return ClaudeCodeUsageLoadedSource(
          threadId: '$visited',
          projectPath: '/project',
          turns: <ClaudeCodeUsageTurnResponse>[
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
      throwsA(isA<ClaudeCodeUsageScanCancelledException>()),
    );
    expect(visited, 5);
    expect(
      const ClaudeCodeUsageScanCancelledException().toString(),
      'ClaudeCodeUsageScanCancelledException()',
    );
  });

  test('rejects empty or reversed time windows', () async {
    final reader = ClaudeCodeUsageReader(claudeHome: tempDirectory.path);
    final at = DateTime.utc(2026);

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
  });

  test('turn response exposes only whitelisted usage fields', () {
    final turn = _turn(
      'turn',
      startedAt: DateTime.utc(2026),
      completedAt: DateTime.utc(2026, 1, 1, 0, 1),
    );

    expect(turn.duration, const Duration(seconds: 2));
    expect(turn.timeToFirstToken, const Duration(milliseconds: 100));
    expect(turn.cwd, '/project');
    expect(turn.reasoningTokens, 2);
    expect(turn.totalTokens, 10);
  });
}

ClaudeCodeUsageTurnResponse _turn(
  String id, {
  DateTime? startedAt,
  DateTime? completedAt,
}) {
  return ClaudeCodeUsageTurnResponse(
    id: id,
    status: 'completed',
    startedAt: startedAt,
    completedAt: completedAt,
    duration: const Duration(seconds: 2),
    timeToFirstToken: const Duration(milliseconds: 100),
    cwd: '/project',
    model: 'claude-test',
    inputTokens: 3,
    cachedInputTokens: 1,
    outputTokens: 4,
    reasoningTokens: 2,
    totalTokens: 10,
    tokenUsageIsSessionCumulative: false,
  );
}
