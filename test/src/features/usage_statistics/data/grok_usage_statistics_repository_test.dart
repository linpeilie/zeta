import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/data/datasources/local_history/grok_usage_log_scanner.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/usage_statistics/data/grok_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

void main() {
  test('映射今日跨项目 Grok 用量并拆分缓存与推理 Token', () async {
    final today = DateTime.utc(2026, 7, 21);
    final scanner = _GrokUsageScanner(
      GrokUsageScanResult(
        sessions: <GrokUsageSessionSnapshot>[
          _session(
            threadId: 'thread-alpha',
            projectPath: '/work/alpha',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-today',
                status: AgentHistoryTurnStatus.completed,
                startedAt: today.add(const Duration(hours: 2)),
                completedAt: today.add(const Duration(hours: 2, seconds: 3)),
                tokenUsage: const AgentTokenUsage(
                  inputTokens: 100,
                  cachedInputTokens: 40,
                  outputTokens: 20,
                  reasoningOutputTokens: 5,
                  totalTokens: 120,
                ),
                tokenUsageIsSessionCumulative: false,
              ),
              AgentHistoryTurn(
                id: 'turn-old',
                status: AgentHistoryTurnStatus.completed,
                startedAt: today.subtract(const Duration(minutes: 1)),
                tokenUsage: const AgentTokenUsage(totalTokens: 999),
                tokenUsageIsSessionCumulative: false,
              ),
            ],
          ),
          _session(
            threadId: 'thread-beta',
            projectPath: '/work/beta',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-beta',
                status: AgentHistoryTurnStatus.failed,
                startedAt: today.add(const Duration(hours: 3)),
                cwd: '/work/beta/nested',
                tokenUsage: const AgentTokenUsage(
                  inputTokens: 50,
                  outputTokens: 10,
                  totalTokens: 60,
                ),
                tokenUsageIsSessionCumulative: false,
                errorMessage: 'network failed',
              ),
            ],
          ),
        ],
        warnings: const <String>['partial history'],
      ),
    );
    final provider = _GrokProvider(
      AgentProviderConfig.defaultGrok.copyWith(
        environment: const <String, String>{'GROK_HOME': '/configured/grok'},
      ),
    );
    final repository = GrokUsageStatisticsRepository(
      providerLoader: () async => provider,
      scanner: scanner,
      clock: () => today.add(const Duration(hours: 4)),
    );

    final source = await repository.load(earliest: today, forceRefresh: true);

    expect(scanner.grokHomes, <String>['/configured/grok']);
    expect(scanner.forceRefreshes, <bool>[true]);
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
  });
}

GrokUsageSessionSnapshot _session({
  required String threadId,
  required String projectPath,
  required List<AgentHistoryTurn> turns,
}) {
  return GrokUsageSessionSnapshot(
    sourcePath: '/grok/$threadId/updates.jsonl',
    threadId: threadId,
    projectPath: projectPath,
    modifiedAt: DateTime.utc(2026, 7, 21),
    history: AgentThreadHistorySnapshot(threadId: threadId, turns: turns),
  );
}

class _GrokUsageScanner implements GrokUsageLogScanner {
  _GrokUsageScanner(this.result);

  final GrokUsageScanResult result;
  final List<String> grokHomes = <String>[];
  final List<bool> forceRefreshes = <bool>[];

  @override
  Future<GrokUsageScanResult> scan({
    required String grokHome,
    bool forceRefresh = false,
  }) async {
    grokHomes.add(grokHome);
    forceRefreshes.add(forceRefresh);
    return result;
  }
}

class _GrokProvider extends Fake implements AgentProvider {
  _GrokProvider(this.config);

  @override
  final AgentProviderConfig config;
}
