import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/codex/codex_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/codex/codex_usage_log_scanner.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/codex/codex_usage_partition_codec.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

void main() {
  test('maps canonical records and uses config id partition', () async {
    final sessions = _sessions();
    final config = AgentProviderConfig.defaultCodex.copyWith(
      id: 'codex-work',
      displayName: 'Codex Work',
    );
    final refreshedAt = DateTime(2026, 8, 12, 12);
    final scanner = _UsageScanner(sessions);
    final store = MemoryUsageStatisticsPartitionStore();
    final source = CodexTokenUsageSource(
      config: config,
      partitionStore: store,
      scanner: scanner,
      environment: const <String, String>{'CODEX_HOME': '/codex-home'},
      clock: () => refreshedAt,
    );
    final earliest = DateTime(2026, 8, 1);

    final actual = await source.load(AgentUsageQuery(earliest: earliest));

    expect(actual.records, hasLength(2));
    expect(actual.historyPresence, AgentTokenHistoryPresence.present);
    final fork = actual.records.first;
    expect(fork.id, 'codex-work/fork/turn-fork');
    expect(fork.startedAt, DateTime(2026, 8, 9, 9));
    expect(fork.status, UsageTaskStatus.completed);
    expect(fork.tokens.inputTokens, 20);
    expect(fork.tokens.cachedInputTokens, 0);
    expect(fork.tokens.outputTokens, 8);
    expect(fork.tokens.reasoningTokens, 2);
    expect(fork.tokens.totalTokens, 30);
    final parent = actual.records.last;
    expect(parent.id, 'codex-work/parent/turn-parent');
    expect(parent.status, UsageTaskStatus.completed);
    expect(parent.duration, const Duration(minutes: 1));
    expect(parent.model, 'gpt-5');
    expect(parent.tokens.inputTokens, 65);
    expect(parent.tokens.cachedInputTokens, 15);
    expect(parent.tokens.outputTokens, 24);
    expect(parent.tokens.reasoningTokens, 6);
    expect(parent.tokens.totalTokens, 110);
    expect(parent.errorMessage, 'secret failure');
    expect(parent.errorCode, 'provider-secret-code');
    expect(actual.providerId, config.id);
    expect(actual.providerName, config.displayName);
    expect(actual.refreshedAt, refreshedAt);
    expect(actual.warnings, isEmpty);
    expect(scanner.codexHomes, <String>['/codex-home']);
    expect(scanner.cachedSessionCounts, <int>[0]);
    final partition = await store.readPartition(config.id);
    expect(partition?.schemaVersion, CodexUsagePartitionCodec.schemaVersion);
    expect(partition?.payload['sessions'], hasLength(2));
    final encoded = jsonEncode(partition?.toJson());
    expect(encoded, isNot(contains('sourcePath')));
    expect(encoded, isNot(contains('/rollout/')));
    expect(encoded, isNot(contains('secret failure')));
    expect(encoded, isNot(contains('provider-secret-code')));
  });

  test('reuses partition cache and forwards force refresh', () async {
    final config = AgentProviderConfig.defaultCodex;
    final scanner = _UsageScanner(_sessions());
    final source = CodexTokenUsageSource(
      config: config,
      partitionStore: MemoryUsageStatisticsPartitionStore(),
      scanner: scanner,
      environment: const <String, String>{'CODEX_HOME': '/codex-home'},
    );
    final query = AgentUsageQuery(earliest: DateTime(2026, 8, 1));

    await source.load(query);
    await source.load(query);
    await source.load(
      AgentUsageQuery(earliest: query.earliest, forceRefresh: true),
    );

    expect(scanner.cachedSessionCounts, <int>[0, 2, 2]);
    expect(scanner.forceRefreshes, <bool>[false, false, true]);
  });

  test(
    'prefers config CODEX_HOME without exposing environment upstream',
    () async {
      final scanner = _UsageScanner(
        const <String, CodexUsageSessionSnapshot>{},
      );
      final source = CodexTokenUsageSource(
        config: AgentProviderConfig.defaultCodex.copyWith(
          environment: const <String, String>{
            'CODEX_HOME': '/configured/codex',
            'SECRET_VALUE': 'must-not-leak',
          },
        ),
        partitionStore: MemoryUsageStatisticsPartitionStore(),
        scanner: scanner,
        environment: const <String, String>{'CODEX_HOME': '/inherited/codex'},
      );

      final snapshot = await source.load(
        AgentUsageQuery(earliest: DateTime(2026, 8, 1)),
      );

      expect(scanner.codexHomes.single, '/configured/codex');
      expect(
        jsonEncode(<Object?>[snapshot.providerId, snapshot.warnings]),
        isNot(contains('must-not-leak')),
      );
    },
  );

  test(
    'index write failure stays a warning and keeps scanned records',
    () async {
      final source = CodexTokenUsageSource(
        config: AgentProviderConfig.defaultCodex,
        partitionStore: _WriteFailingPartitionStore(),
        scanner: _UsageScanner(_sessions()),
        environment: const <String, String>{'CODEX_HOME': '/codex-home'},
      );

      final snapshot = await source.load(
        AgentUsageQuery(earliest: DateTime(2026, 8, 1)),
      );

      expect(snapshot.records, hasLength(2));
      expect(snapshot.warnings.single.code, 'codex-index-write');
      expect(snapshot.warnings.single.message, isNot(contains('sensitive')));
    },
  );

  test('partition codec skips damaged sessions and ignores other schemas', () {
    const codec = CodexUsagePartitionCodec();
    final valid = _sessions().values.first;
    final partition = UsageStatisticsIndexPartition(
      schemaVersion: 1,
      payload: <String, Object?>{
        'sessions': <Object?>[
          valid.toJson(),
          <String, Object?>{'threadId': 'damaged'},
          'damaged',
        ],
      },
    );

    expect(codec.decode(partition).values.single.threadId, valid.threadId);
    expect(
      codec.decode(
        UsageStatisticsIndexPartition(
          schemaVersion: 2,
          payload: <String, Object?>{
            'sessions': <Object?>[valid.toJson()],
          },
        ),
      ),
      isEmpty,
    );
  });
}

Map<String, CodexUsageSessionSnapshot> _sessions() {
  final parentCreated = DateTime(2026, 8, 8, 9);
  final forkCreated = DateTime(2026, 8, 9, 9);
  final sampleA = CodexUsageSample(
    deduplicationKey: 'sample-a',
    timestamp: parentCreated.add(const Duration(seconds: 1)),
    inputTokens: 50,
    cachedInputTokens: 10,
    outputTokens: 16,
    reasoningTokens: 4,
    totalTokens: 80,
  );
  final sampleB = CodexUsageSample(
    deduplicationKey: 'sample-b',
    timestamp: parentCreated.add(const Duration(seconds: 2)),
    inputTokens: 15,
    cachedInputTokens: 5,
    outputTokens: 8,
    reasoningTokens: 2,
    totalTokens: 30,
  );
  final sampleC = CodexUsageSample(
    deduplicationKey: 'sample-c',
    timestamp: forkCreated.add(const Duration(seconds: 10)),
    inputTokens: 20,
    cachedInputTokens: 0,
    outputTokens: 8,
    reasoningTokens: 2,
    totalTokens: 30,
  );
  return <String, CodexUsageSessionSnapshot>{
    '/rollout/parent.jsonl': CodexUsageSessionSnapshot(
      sourcePath: '/rollout/parent.jsonl',
      fingerprint: '100:1',
      threadId: 'parent',
      projectPath: '/work/zeta',
      sourceKind: 'codex_cli_rs',
      createdAt: parentCreated,
      turns: <CodexUsageTurnSnapshot>[
        CodexUsageTurnSnapshot(
          id: 'turn-parent',
          status: AgentHistoryTurnStatus.completed,
          startedAt: parentCreated,
          completedAt: parentCreated.add(const Duration(minutes: 1)),
          model: 'gpt-5',
          errorMessage: 'secret failure',
          errorCode: 'provider-secret-code',
          samples: <CodexUsageSample>[sampleA, sampleB],
        ),
      ],
    ),
    '/rollout/fork.jsonl': CodexUsageSessionSnapshot(
      sourcePath: '/rollout/fork.jsonl',
      fingerprint: '120:2',
      threadId: 'fork',
      projectPath: '/work/zeta',
      sourceKind: 'codex_cli_rs',
      createdAt: forkCreated,
      turns: <CodexUsageTurnSnapshot>[
        CodexUsageTurnSnapshot(
          id: 'turn-fork',
          status: AgentHistoryTurnStatus.completed,
          startedAt: forkCreated,
          completedAt: forkCreated.add(const Duration(minutes: 1)),
          model: 'gpt-5',
          samples: <CodexUsageSample>[sampleA, sampleC],
        ),
      ],
    ),
  };
}

final class _UsageScanner implements CodexUsageLogScanner {
  _UsageScanner(this.sessions);

  final Map<String, CodexUsageSessionSnapshot> sessions;
  final List<String> codexHomes = <String>[];
  final List<int> cachedSessionCounts = <int>[];
  final List<bool> forceRefreshes = <bool>[];

  @override
  Future<CodexUsageScanResult> scan({
    required String codexHome,
    required Map<String, CodexUsageSessionSnapshot> cachedSessions,
    bool forceRefresh = false,
    UsageStatisticsTextCatalog textCatalog =
        const FallbackUsageStatisticsTextCatalog(),
  }) async {
    codexHomes.add(codexHome);
    cachedSessionCounts.add(cachedSessions.length);
    forceRefreshes.add(forceRefresh);
    return CodexUsageScanResult(sessions: sessions, warnings: const <String>[]);
  }
}

final class _WriteFailingPartitionStore
    implements UsageStatisticsPartitionStore {
  @override
  Future<UsageStatisticsIndexPartition?> readPartition(
    String sourceKey,
  ) async => null;

  @override
  Future<void> writePartition(
    String sourceKey,
    UsageStatisticsIndexPartition partition,
  ) {
    throw StateError('sensitive index failure');
  }
}
