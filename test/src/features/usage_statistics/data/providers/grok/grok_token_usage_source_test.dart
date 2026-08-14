import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/grok/grok_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/grok/grok_usage_log_scanner.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/grok/grok_usage_partition_codec.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

void main() {
  test('maps canonical records and uses config id partition', () async {
    final result = _scanResult();
    final config = AgentProviderConfig.defaultGrok.copyWith(
      id: 'grok-work',
      displayName: 'Grok Work',
    );
    final refreshedAt = DateTime.utc(2026, 8, 12, 12);
    final scanner = _GrokUsageScanner(result);
    final store = MemoryUsageStatisticsPartitionStore();
    final source = GrokTokenUsageSource(
      config: config,
      partitionStore: store,
      scanner: scanner,
      environment: const <String, String>{'GROK_HOME': '/grok-home'},
      clock: () => refreshedAt,
    );
    final earliest = DateTime.utc(2026, 8, 12);

    final actual = await source.load(AgentUsageQuery(earliest: earliest));

    expect(actual.records, hasLength(2));
    expect(actual.historyPresence, AgentTokenHistoryPresence.present);
    final failed = actual.records.first;
    expect(failed.id, 'grok-work/thread-beta/turn-beta');
    expect(failed.projectPath, '/work/beta/nested');
    expect(failed.status, UsageTaskStatus.failed);
    expect(failed.tokens.inputTokens, 50);
    expect(failed.tokens.outputTokens, 10);
    expect(failed.tokens.totalTokens, 60);
    expect(failed.errorCategory, UsageErrorCategory.other);
    expect(failed.errorMessage, 'secret failure');
    expect(failed.errorCode, 'provider-secret-code');
    final completed = actual.records.last;
    expect(completed.id, 'grok-work/thread-alpha/turn-today');
    expect(completed.status, UsageTaskStatus.completed);
    expect(completed.duration, const Duration(seconds: 3));
    expect(completed.tokens.inputTokens, 60);
    expect(completed.tokens.cachedInputTokens, 40);
    expect(completed.tokens.outputTokens, 15);
    expect(completed.tokens.reasoningTokens, 5);
    expect(completed.tokens.totalTokens, 120);
    expect(actual.providerId, config.id);
    expect(actual.providerName, config.displayName);
    expect(actual.refreshedAt, refreshedAt);
    expect(actual.warnings.map((warning) => warning.message), <String>[
      'partial history',
    ]);
    expect(scanner.grokHomes, <String>['/grok-home']);
    expect(scanner.cachedSessionCounts, <int>[0]);
    final partition = await store.readPartition(config.id);
    expect(partition?.schemaVersion, GrokUsagePartitionCodec.schemaVersion);
    expect(partition?.payload['sessions'], hasLength(2));
    final encoded = jsonEncode(partition?.toJson());
    expect(encoded, isNot(contains('sourcePath')));
    expect(encoded, isNot(contains('/updates/')));
    expect(encoded, isNot(contains('secret failure')));
    expect(encoded, isNot(contains('provider-secret-code')));
  });

  test('reuses partition cache and forwards force refresh', () async {
    final scanner = _GrokUsageScanner(_scanResult());
    final source = GrokTokenUsageSource(
      config: AgentProviderConfig.defaultGrok,
      partitionStore: MemoryUsageStatisticsPartitionStore(),
      scanner: scanner,
      environment: const <String, String>{'GROK_HOME': '/grok-home'},
    );
    final query = AgentUsageQuery(earliest: DateTime.utc(2026, 8, 1));

    await source.load(query);
    await source.load(query);
    await source.load(
      AgentUsageQuery(earliest: query.earliest, forceRefresh: true),
    );

    expect(scanner.cachedSessionCounts, <int>[0, 2, 2]);
    expect(scanner.forceRefreshes, <bool>[false, false, true]);
  });

  test(
    'prefers config GROK_HOME without exposing environment upstream',
    () async {
      final scanner = _GrokUsageScanner(
        const GrokUsageScanResult(
          sessions: <String, GrokUsageIndexedSession>{},
          warnings: <String>[],
        ),
      );
      final source = GrokTokenUsageSource(
        config: AgentProviderConfig.defaultGrok.copyWith(
          environment: const <String, String>{
            'GROK_HOME': '/configured/grok',
            'SECRET_VALUE': 'must-not-leak',
          },
        ),
        partitionStore: MemoryUsageStatisticsPartitionStore(),
        scanner: scanner,
        environment: const <String, String>{'GROK_HOME': '/inherited/grok'},
      );

      final snapshot = await source.load(
        AgentUsageQuery(earliest: DateTime.utc(2026, 8, 1)),
      );

      expect(scanner.grokHomes.single, '/configured/grok');
      expect(
        jsonEncode(<Object?>[snapshot.providerId, snapshot.warnings]),
        isNot(contains('must-not-leak')),
      );
    },
  );

  test(
    'index write failure stays a warning and keeps scanned records',
    () async {
      final source = GrokTokenUsageSource(
        config: AgentProviderConfig.defaultGrok,
        partitionStore: _WriteFailingPartitionStore(),
        scanner: _GrokUsageScanner(_scanResult(warnings: const <String>[])),
        environment: const <String, String>{'GROK_HOME': '/grok-home'},
      );

      final snapshot = await source.load(
        AgentUsageQuery(earliest: DateTime.utc(2026, 8, 12)),
      );

      expect(snapshot.records, hasLength(2));
      expect(snapshot.warnings.single.code, 'grok-index-write');
      expect(snapshot.warnings.single.message, isNot(contains('sensitive')));
    },
  );

  test('partition codec skips damaged sessions and ignores other schemas', () {
    const codec = GrokUsagePartitionCodec();
    final valid = _scanResult().sessions.values.first;
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

GrokUsageScanResult _scanResult({
  List<String> warnings = const <String>['partial history'],
}) {
  final today = DateTime.utc(2026, 8, 12);
  return GrokUsageScanResult(
    sessions: <String, GrokUsageIndexedSession>{
      '/updates/alpha.jsonl': _session(
        sourcePath: '/updates/alpha.jsonl',
        threadId: 'thread-alpha',
        projectPath: '/work/alpha',
        turns: <GrokUsageIndexedTurn>[
          GrokUsageIndexedTurn(
            id: 'turn-today',
            status: AgentHistoryTurnStatus.completed,
            startedAt: today.add(const Duration(hours: 2)),
            completedAt: today.add(const Duration(hours: 2, seconds: 3)),
            duration: const Duration(seconds: 3),
            inputTokens: 60,
            cachedInputTokens: 40,
            outputTokens: 15,
            reasoningTokens: 5,
            totalTokens: 120,
          ),
          GrokUsageIndexedTurn(
            id: 'turn-old',
            status: AgentHistoryTurnStatus.completed,
            startedAt: today.subtract(const Duration(minutes: 1)),
            totalTokens: 999,
          ),
        ],
      ),
      '/updates/beta.jsonl': _session(
        sourcePath: '/updates/beta.jsonl',
        threadId: 'thread-beta',
        projectPath: '/work/beta',
        turns: <GrokUsageIndexedTurn>[
          GrokUsageIndexedTurn(
            id: 'turn-beta',
            status: AgentHistoryTurnStatus.failed,
            startedAt: today.add(const Duration(hours: 3)),
            cwd: '/work/beta/nested',
            inputTokens: 50,
            outputTokens: 10,
            totalTokens: 60,
            errorCategoryHint: 'other',
            errorMessage: 'secret failure',
            errorCode: 'provider-secret-code',
          ),
        ],
      ),
    },
    warnings: warnings,
  );
}

GrokUsageIndexedSession _session({
  required String sourcePath,
  required String threadId,
  required String projectPath,
  required List<GrokUsageIndexedTurn> turns,
}) {
  return GrokUsageIndexedSession(
    sourcePath: sourcePath,
    fingerprint: '1:1',
    threadId: threadId,
    projectPath: projectPath,
    sourceKind: 'grok_acp',
    modifiedAt: DateTime.utc(2026, 8, 12),
    turns: turns,
  );
}

final class _GrokUsageScanner implements GrokUsageLogScanner {
  _GrokUsageScanner(this.result);

  final GrokUsageScanResult result;
  final List<String> grokHomes = <String>[];
  final List<bool> forceRefreshes = <bool>[];
  final List<int> cachedSessionCounts = <int>[];

  @override
  Future<GrokUsageScanResult> scan({
    required String grokHome,
    required Map<String, GrokUsageIndexedSession> cachedSessions,
    bool forceRefresh = false,
  }) async {
    grokHomes.add(grokHome);
    forceRefreshes.add(forceRefresh);
    cachedSessionCounts.add(cachedSessions.length);
    return result;
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
