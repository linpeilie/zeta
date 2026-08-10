import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/data/datasources/local_history/grok_usage_log_scanner.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/usage_statistics/data/grok_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_index_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

void main() {
  test('映射今日跨项目 Grok 用量并拆分缓存与推理 Token', () async {
    final today = DateTime.utc(2026, 7, 21);
    final scanner = _GrokUsageScanner(
      GrokUsageScanResult(
        sessions: <String, GrokUsageIndexedSession>{
          '/grok/thread-alpha/updates.jsonl': _session(
            sourcePath: '/grok/thread-alpha/updates.jsonl',
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
          '/grok/thread-beta/updates.jsonl': _session(
            sourcePath: '/grok/thread-beta/updates.jsonl',
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
                errorMessage: 'network failed',
              ),
            ],
          ),
        },
        warnings: const <String>['partial history'],
      ),
    );
    final provider = _GrokProvider(
      AgentProviderConfig.defaultGrok.copyWith(
        environment: const <String, String>{'GROK_HOME': '/configured/grok'},
      ),
    );
    final store = MemoryUsageStatisticsIndexStore();
    final repository = GrokUsageStatisticsRepository(
      indexStore: store,
      providerLoader: () async => provider,
      scanner: scanner,
      clock: () => today.add(const Duration(hours: 4)),
    );

    final source = await repository.load(earliest: today, forceRefresh: true);

    expect(scanner.grokHomes, <String>['/configured/grok']);
    expect(scanner.forceRefreshes, <bool>[true]);
    expect(scanner.cachedSessionCounts, <int>[0]);
    expect(source.warnings, <String>['partial history']);
    expect(source.records, hasLength(2));
    final alpha = source.records.singleWhere(
      (record) => record.turnId == 'turn-today',
    );
    expect(alpha.projectPath, '/work/alpha');
    expect(alpha.tokens.inputTokens, 60);
    expect(alpha.tokens.cachedInputTokens, 40);
    expect(alpha.tokens.outputTokens, 15);
    expect(alpha.tokens.reasoningTokens, 5);
    expect(alpha.tokens.totalTokens, 120);
    expect(alpha.duration, const Duration(seconds: 3));

    final beta = source.records.singleWhere(
      (record) => record.turnId == 'turn-beta',
    );
    expect(beta.projectPath, '/work/beta/nested');
    expect(beta.status, UsageTaskStatus.failed);
    expect(beta.errorCategory, UsageErrorCategory.other);
    expect(store.snapshot.grokSessions, hasLength(2));

    await repository.load(earliest: today);
    expect(scanner.cachedSessionCounts, <int>[0, 2]);
  });
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
    modifiedAt: DateTime.utc(2026, 7, 21),
    turns: turns,
  );
}

class _GrokUsageScanner implements GrokUsageLogScanner {
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

class _GrokProvider extends Fake implements AgentProvider {
  _GrokProvider(this.config);

  @override
  final AgentProviderConfig config;
}
