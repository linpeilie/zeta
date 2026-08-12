import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_session_history_reader.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/claude_code/claude_code_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/claude_code/claude_code_usage_partition_codec.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

void main() {
  group('ClaudeCodeTokenUsageSource', () {
    late Directory tempRoot;
    late MemoryUsageStatisticsPartitionStore store;
    late _CountingHistoryReader reader;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('zeta-claude-usage-');
      store = MemoryUsageStatisticsPartitionStore();
      reader = _CountingHistoryReader(claudeHome: tempRoot.path);
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test(
      'projects completed failed interrupted turns and absolute cache usage',
      () async {
        const privatePrompt = 'private prompt must not escape';
        const privateResponse = 'private response must not escape';
        const privateError = 'private provider failure must not escape';
        final today = DateTime.utc(2026, 8, 12);
        await _writeHistory(
          root: tempRoot,
          projectPath: '/workspace/completed',
          fileName: 'completed.jsonl',
          sessionId: 'completed-session',
          userId: 'completed-user',
          startedAt: today.add(const Duration(hours: 1)),
          subtype: 'success',
          durationMs: 900,
          usage: const <String, Object?>{
            'input_tokens': 3,
            'output_tokens': 2,
            'cache_creation_input_tokens': 5,
            'cache_read_input_tokens': 7,
          },
          prompt: privatePrompt,
          response: privateResponse,
          malformedLine: true,
        );
        await _writeHistory(
          root: tempRoot,
          projectPath: '/workspace/interrupted',
          fileName: 'interrupted.jsonl',
          sessionId: 'interrupted-session',
          userId: 'interrupted-user',
          startedAt: today.add(const Duration(hours: 2)),
          subtype: 'error_max_turns',
          durationMs: 1200,
          usage: const <String, Object?>{
            'input_tokens': 11,
            'output_tokens': 4,
            'cache_read_input_tokens': 13,
          },
          prompt: privatePrompt,
          response: privateResponse,
        );
        await _writeHistory(
          root: tempRoot,
          projectPath: '/workspace/failed',
          fileName: 'failed.jsonl',
          sessionId: 'failed-session',
          userId: 'failed-user',
          startedAt: today.add(const Duration(hours: 3)),
          subtype: 'error_during_execution',
          durationMs: 400,
          usage: const <String, Object?>{'input_tokens': 6, 'output_tokens': 1},
          prompt: privatePrompt,
          response: privateError,
        );
        await _writeHistory(
          root: tempRoot,
          projectPath: '/workspace/old',
          fileName: 'old.jsonl',
          sessionId: 'old-session',
          userId: 'old-user',
          startedAt: today.subtract(const Duration(days: 1)),
          subtype: 'success',
          durationMs: 100,
          usage: const <String, Object?>{'input_tokens': 999},
          prompt: privatePrompt,
          response: privateResponse,
        );
        final refreshedAt = today.add(const Duration(hours: 12));
        final config = AgentProviderConfig.defaultClaudeCode.copyWith(
          id: 'claude-work',
          displayName: 'Claude Work',
          environment: const <String, String>{
            'SECRET_VALUE': 'credential-value-must-not-escape',
          },
        );
        final source = ClaudeCodeTokenUsageSource(
          config: config,
          partitionStore: store,
          historyReader: reader,
          environment: const <String, String>{},
          clock: () => refreshedAt,
        );

        final snapshot = await source.load(AgentUsageQuery(earliest: today));

        expect(snapshot.records, hasLength(3));
        expect(snapshot.providerId, 'claude-work');
        expect(snapshot.providerName, 'Claude Work');
        expect(snapshot.refreshedAt, refreshedAt);
        final byThread = <String, AgentUsageRecord>{
          for (final record in snapshot.records) record.threadId: record,
        };
        final completed = byThread['completed-session']!;
        expect(completed.status, UsageTaskStatus.completed);
        expect(completed.tokens.inputTokens, 3);
        expect(completed.tokens.outputTokens, 2);
        expect(completed.tokens.cachedInputTokens, 12);
        expect(completed.tokens.totalTokens, 5);
        expect(completed.duration, const Duration(milliseconds: 900));
        expect(completed.sourceKind, 'claude_code_stream_json');
        expect(
          completed.id,
          startsWith('claude-work/completed-session/cc-history-turn:'),
        );
        expect(
          byThread['interrupted-session']?.status,
          UsageTaskStatus.interrupted,
        );
        expect(
          byThread['interrupted-session']?.errorCategory,
          UsageErrorCategory.cancelled,
        );
        expect(byThread['failed-session']?.status, UsageTaskStatus.failed);
        expect(
          byThread['failed-session']?.errorCategory,
          UsageErrorCategory.other,
        );
        expect(
          snapshot.warnings.map((warning) => warning.message),
          contains('1 行 Claude Code 历史损坏，已跳过并继续统计。'),
        );

        final partition = await store.readPartition(config.id);
        expect(
          partition?.schemaVersion,
          ClaudeCodeUsagePartitionCodec.schemaVersion,
        );
        final persisted = jsonEncode(partition?.toJson());
        final safeSnapshot = jsonEncode(
          snapshot.records.map((record) => record.toJson()).toList(),
        );
        for (final secret in <String>[
          privatePrompt,
          privateResponse,
          privateError,
          'credential-value-must-not-escape',
          tempRoot.path,
          'sourcePath',
          'sessionPath',
          'rawPayload',
        ]) {
          expect(persisted, isNot(contains(secret)));
          expect(safeSnapshot, isNot(contains(secret)));
        }
      },
    );

    test(
      'deduplicates canonical identity and keeps the fuller record',
      () async {
        final startedAt = DateTime.utc(2026, 8, 12, 4);
        for (final fixture in <({String name, Map<String, Object?> usage})>[
          (
            name: 'a-partial.jsonl',
            usage: const <String, Object?>{'input_tokens': 2},
          ),
          (
            name: 'b-complete.jsonl',
            usage: const <String, Object?>{
              'input_tokens': 2,
              'output_tokens': 3,
              'cache_creation_input_tokens': 5,
              'cache_read_input_tokens': 7,
            },
          ),
        ]) {
          await _writeHistory(
            root: tempRoot,
            projectPath: '/workspace/duplicate',
            fileName: fixture.name,
            sessionId: 'duplicate-session',
            userId: 'same-source-user',
            startedAt: startedAt,
            subtype: 'success',
            durationMs: 500,
            usage: fixture.usage,
            prompt: '[PROMPT_REDACTED]',
            response: '[RESPONSE_REDACTED]',
          );
        }
        final source = ClaudeCodeTokenUsageSource(
          config: AgentProviderConfig.defaultClaudeCode,
          partitionStore: store,
          historyReader: reader,
        );

        final snapshot = await source.load(
          AgentUsageQuery(earliest: DateTime.utc(2026, 8, 12)),
        );

        expect(snapshot.records, hasLength(1));
        expect(snapshot.records.single.tokens.cachedInputTokens, 12);
        expect(snapshot.records.single.tokens.outputTokens, 3);
        expect(snapshot.records.single.tokens.totalTokens, 5);
      },
    );

    test(
      'reuses its partition index and force refresh reparses files',
      () async {
        await _writeHistory(
          root: tempRoot,
          projectPath: '/workspace/cache',
          fileName: 'cached.jsonl',
          sessionId: 'cached-session',
          userId: 'cached-user',
          startedAt: DateTime.utc(2026, 8, 12, 5),
          subtype: 'success',
          durationMs: 300,
          usage: const <String, Object?>{'input_tokens': 8, 'output_tokens': 2},
          prompt: '[PROMPT_REDACTED]',
          response: '[RESPONSE_REDACTED]',
        );
        final source = ClaudeCodeTokenUsageSource(
          config: AgentProviderConfig.defaultClaudeCode,
          partitionStore: store,
          historyReader: reader,
        );
        final query = AgentUsageQuery(earliest: DateTime.utc(2026, 8, 12));

        final first = await source.load(query);
        final parsedAfterFirst = reader.readCount;
        final second = await source.load(query);
        final parsedAfterSecond = reader.readCount;
        final refreshed = await source.load(
          AgentUsageQuery(earliest: query.earliest, forceRefresh: true),
        );

        expect(parsedAfterFirst, 1);
        expect(parsedAfterSecond, parsedAfterFirst);
        expect(reader.readCount, parsedAfterFirst + 1);
        expect(_usageSignature(second), _usageSignature(first));
        expect(_usageSignature(refreshed), _usageSignature(first));
      },
    );

    test(
      'usage projection stays positionally equal to history snapshot',
      () async {
        final historyFile = await _writeHistory(
          root: tempRoot,
          projectPath: '/workspace/parity',
          fileName: 'parity.jsonl',
          sessionId: 'parity-session',
          userId: 'parity-user',
          startedAt: DateTime.utc(2026, 8, 12, 6),
          subtype: 'success',
          durationMs: 700,
          usage: const <String, Object?>{
            'input_tokens': 42,
            'output_tokens': 17,
            'cache_creation_input_tokens': 1200,
            'cache_read_input_tokens': 3400,
          },
          prompt: '[PROMPT_REDACTED]',
          response: '[RESPONSE_REDACTED]',
        );
        final history = await reader.readLocalHistoryFile(
          file: historyFile,
          providerId: defaultClaudeCodeProviderId,
        );
        final source = ClaudeCodeTokenUsageSource(
          config: AgentProviderConfig.defaultClaudeCode,
          partitionStore: store,
          historyReader: reader,
        );

        final usage = await source.load(
          AgentUsageQuery(earliest: DateTime.utc(2026, 8, 12)),
        );

        final historyTurns = history!.history.snapshot.turns;
        expect(usage.records, hasLength(historyTurns.length));
        for (var index = 0; index < historyTurns.length; index += 1) {
          final expected = historyTurns[index];
          final actual = usage.records[index];
          expect(actual.turnId, expected.id);
          expect(actual.tokens.inputTokens, expected.tokenUsage?.inputTokens);
          expect(
            actual.tokens.cachedInputTokens,
            expected.tokenUsage?.cachedInputTokens,
          );
          expect(actual.tokens.outputTokens, expected.tokenUsage?.outputTokens);
          expect(actual.tokens.totalTokens, expected.tokenUsage?.totalTokens);
          expect(expected.tokenUsageIsSessionCumulative, isFalse);
        }
      },
    );

    test('partition codec skips damaged sessions and unknown schemas', () {
      const codec = ClaudeCodeUsagePartitionCodec();
      final session = ClaudeCodeUsageIndexedSession(
        sourcePath: '/private/session.jsonl',
        sourceId: 'safe-source-id',
        fingerprint: '10:20',
        threadId: 'thread-id',
        projectPath: '/workspace/project',
        sourceKind: 'claude_code_stream_json',
        modifiedAt: DateTime.utc(2026, 8, 12),
        turns: const <ClaudeCodeUsageIndexedTurn>[
          ClaudeCodeUsageIndexedTurn(
            id: 'turn-id',
            status: AgentHistoryTurnStatus.failed,
            inputTokens: 4,
            cachedInputTokens: 6,
            outputTokens: 2,
            totalTokens: 6,
            errorCategoryHint: 'other',
            errorMessage: 'private raw error',
            errorCode: 'private provider code',
          ),
        ],
      );
      final partition = codec.encode(<ClaudeCodeUsageIndexedSession>[session]);

      expect(codec.decode(partition).values.single.threadId, 'thread-id');
      expect(
        codec
            .decode(
              UsageStatisticsIndexPartition(
                schemaVersion: 1,
                payload: <String, Object?>{
                  'sessions': <Object?>[
                    session.toJson(),
                    <String, Object?>{'threadId': 'damaged'},
                    'damaged',
                  ],
                },
              ),
            )
            .values
            .single
            .threadId,
        'thread-id',
      );
      expect(
        codec.decode(
          UsageStatisticsIndexPartition(
            schemaVersion: 2,
            payload: <String, Object?>{
              'sessions': <Object?>[session.toJson()],
            },
          ),
        ),
        isEmpty,
      );
      final encoded = jsonEncode(partition.toJson());
      expect(encoded, isNot(contains('/private/session.jsonl')));
      expect(encoded, isNot(contains('private raw error')));
      expect(encoded, isNot(contains('private provider code')));
    });
  });
}

Future<File> _writeHistory({
  required Directory root,
  required String projectPath,
  required String fileName,
  required String sessionId,
  required String userId,
  required DateTime startedAt,
  required String subtype,
  required int durationMs,
  required Map<String, Object?> usage,
  required String prompt,
  required String response,
  bool malformedLine = false,
}) async {
  final directory = Directory(
    '${root.path}${Platform.pathSeparator}projects'
    '${Platform.pathSeparator}'
    '${ClaudeCodeSessionHistoryReader.encodeProjectPath(projectPath)}',
  );
  await directory.create(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  final completedAt = startedAt.add(Duration(milliseconds: durationMs));
  final frames = <Map<String, Object?>>[
    <String, Object?>{
      'type': 'user',
      'sessionId': sessionId,
      'uuid': userId,
      'timestamp': startedAt.toIso8601String(),
      'cwd': projectPath,
      'message': <String, Object?>{'role': 'user', 'content': prompt},
    },
    <String, Object?>{
      'type': 'assistant',
      'sessionId': sessionId,
      'uuid': '$userId-assistant',
      'timestamp': startedAt
          .add(const Duration(milliseconds: 100))
          .toIso8601String(),
      'message': <String, Object?>{
        'id': '$userId-message',
        'role': 'assistant',
        'model': 'claude-test-model',
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': response},
        ],
      },
    },
    <String, Object?>{
      'type': 'result',
      'subtype': subtype,
      'sessionId': sessionId,
      'uuid': '$userId-result',
      'timestamp': completedAt.toIso8601String(),
      'duration_ms': durationMs,
      'result': response,
      'usage': usage,
    },
  ];
  final lines = <String>[
    jsonEncode(frames[0]),
    if (malformedLine) '{malformed-json}',
    ...frames.skip(1).map(jsonEncode),
  ];
  await file.writeAsString('${lines.join('\n')}\n');
  return file;
}

List<String> _usageSignature(AgentTokenUsageSourceSnapshot snapshot) {
  return snapshot.records
      .map(
        (record) => <Object?>[
          record.id,
          record.status.name,
          record.tokens.inputTokens,
          record.tokens.cachedInputTokens,
          record.tokens.outputTokens,
          record.tokens.totalTokens,
        ].join('|'),
      )
      .toList(growable: false);
}

final class _CountingHistoryReader extends ClaudeCodeSessionHistoryReader {
  _CountingHistoryReader({required super.claudeHome});

  int readCount = 0;

  @override
  Future<ClaudeCodeLocalHistoryReadResult?> readLocalHistoryFile({
    required File file,
    required String providerId,
    Map<String, String>? environment,
    AgentRuntimeScope runtimeScope = const AgentRuntimeScope(
      runtimeId: 'claude-code-local-history',
      connectionEpoch: 1,
    ),
  }) {
    readCount += 1;
    return super.readLocalHistoryFile(
      file: file,
      providerId: providerId,
      environment: environment,
      runtimeScope: runtimeScope,
    );
  }
}
