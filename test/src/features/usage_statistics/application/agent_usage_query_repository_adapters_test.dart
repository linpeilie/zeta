import 'package:flutter_test/flutter_test.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_query_service.dart';
import 'package:zeta/src/features/usage_statistics/application/query_agent_usage_panel_repository.dart';
import 'package:zeta/src/features/usage_statistics/application/query_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_quota_source.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

void main() {
  final now = DateTime(2026, 8, 12, 12);
  final config = AgentProviderConfig.defaultCodex.copyWith(
    id: 'codex-work',
    displayName: 'Codex Work',
  );
  final quota = AgentUsageQuotaSnapshot(
    providerId: config.id,
    providerName: config.displayName,
    windows: const <AgentUsageWindow>[],
  );
  final earlierRecord = _record(
    config,
    turnId: 'earlier',
    startedAt: DateTime(2026, 8, 12, 9),
    tokens: const UsageTokenBreakdown(
      inputTokens: 10,
      cachedInputTokens: 2,
      outputTokens: 3,
      reasoningTokens: 4,
      totalTokens: 19,
    ),
  );
  final laterRecord = _record(
    config,
    turnId: 'later',
    startedAt: DateTime(2026, 8, 12, 13),
    tokens: const UsageTokenBreakdown(inputTokens: 7, outputTokens: 5),
  );
  final sourceSnapshot = AgentTokenUsageSourceSnapshot(
    providerId: config.id,
    providerName: config.displayName,
    historyPresence: AgentTokenHistoryPresence.present,
    records: <AgentUsageRecord>[earlierRecord, laterRecord],
    refreshedAt: DateTime(2026, 8, 12, 11, 59),
    warnings: const <AgentUsageWarning>[
      AgentUsageWarning(code: 'fixture-warning', message: '部分记录已跳过'),
    ],
  );

  test(
    'same query snapshot projects to directory and one panel result',
    () async {
      final service = _service(
        config: config,
        quota: quota,
        sourceSnapshot: sourceSnapshot,
        clock: now,
      );
      final repository = QueryAgentUsagePanelRepository(
        service,
        clock: () => now,
      );

      final directory = await repository.discoverProviders();
      final result = await repository.loadProvider(
        config.id,
        forceRefresh: true,
      );

      expect(directory.single.providerId, config.id);
      expect(directory.single.providerName, config.displayName);
      final entry = result!.entry;
      expect(entry.providerId, config.id);
      expect(entry.providerName, config.displayName);
      expect(entry.quota, same(quota));
      expect(entry.message, isNull);
      expect(entry.todayTokens?.inputTokens, 10);
      expect(entry.todayTokens?.cachedInputTokens, 2);
      expect(entry.todayTokens?.outputTokens, 3);
      expect(entry.todayTokens?.reasoningTokens, 4);
      expect(entry.todayTokens?.totalTokens, 19);
      expect(result.refreshedAt, now);
    },
  );

  test(
    'same query snapshot projects to the current statistics snapshot',
    () async {
      final service = _service(
        config: config,
        quota: quota,
        sourceSnapshot: sourceSnapshot,
        clock: now,
      );
      final repository = QueryUsageStatisticsRepository(
        service,
        clock: () => now,
      );

      final snapshot = await repository.load(
        earliest: DateTime(2026, 8, 1),
        forceRefresh: true,
      );

      expect(snapshot.records, <AgentUsageRecord>[laterRecord, earlierRecord]);
      expect(snapshot.quota, same(quota));
      expect(snapshot.warnings, <String>['部分记录已跳过']);
      expect(snapshot.refreshedAt, sourceSnapshot.refreshedAt);
    },
  );

  test('capability states keep unsupported and unavailable distinct', () async {
    final unsupported = _service(
      config: config,
      quota: null,
      sourceSnapshot: null,
      clock: now,
    );
    final unsupportedResult = await QueryAgentUsagePanelRepository(
      unsupported,
      clock: () => now,
    ).loadProvider(config.id);
    final unsupportedEntry = unsupportedResult!.entry;
    expect(unsupportedEntry.todayTokens, isNull);
    expect(unsupportedEntry.message, isNull);

    final unavailable = AgentUsageQueryService(
      () async => <AgentProviderConfig>[config],
      _FakeQuotaSource(
        const AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>.unsupported(),
      ),
      _FakeTokenRegistry(_ThrowingTokenSource(config.id)),
      clock: () => now,
    );
    final unavailableResult = await QueryAgentUsagePanelRepository(
      unavailable,
      clock: () => now,
    ).loadProvider(config.id);
    final unavailableEntry = unavailableResult!.entry;
    expect(unavailableEntry.todayTokens, isNull);
    expect(unavailableEntry.message, '今日 Token 暂时无法读取');
  });

  test(
    'panel distinguishes missing history from an empty time window',
    () async {
      AgentTokenUsageSourceSnapshot snapshot(
        AgentTokenHistoryPresence presence,
      ) => AgentTokenUsageSourceSnapshot(
        providerId: config.id,
        providerName: config.displayName,
        historyPresence: presence,
        records: const <AgentUsageRecord>[],
        refreshedAt: now,
      );

      final absentResult = await QueryAgentUsagePanelRepository(
        _service(
          config: config,
          quota: null,
          sourceSnapshot: snapshot(AgentTokenHistoryPresence.absent),
          clock: now,
        ),
        clock: () => now,
      ).loadProvider(config.id);
      final presentResult = await QueryAgentUsagePanelRepository(
        _service(
          config: config,
          quota: null,
          sourceSnapshot: snapshot(AgentTokenHistoryPresence.present),
          clock: now,
        ),
        clock: () => now,
      ).loadProvider(config.id);

      expect(absentResult!.entry.todayTokens, isNull);
      expect(absentResult.entry.message, '暂无 Token 历史');
      expect(presentResult!.entry.todayTokens?.totalTokens, 0);
      expect(presentResult.entry.message, isNull);
    },
  );
}

AgentUsageQueryService _service({
  required AgentProviderConfig config,
  required AgentUsageQuotaSnapshot? quota,
  required AgentTokenUsageSourceSnapshot? sourceSnapshot,
  required DateTime clock,
}) {
  return AgentUsageQueryService(
    () async => <AgentProviderConfig>[config],
    _FakeQuotaSource(
      quota == null
          ? const AgentUsageCapabilityResult<
              AgentUsageQuotaSnapshot
            >.unsupported()
          : AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>.available(
              quota,
            ),
    ),
    _FakeTokenRegistry(
      sourceSnapshot == null
          ? null
          : _FakeTokenSource(config.id, sourceSnapshot),
    ),
    clock: () => clock,
  );
}

AgentUsageRecord _record(
  AgentProviderConfig config, {
  required String turnId,
  required DateTime startedAt,
  required UsageTokenBreakdown tokens,
}) {
  return AgentUsageRecord(
    threadId: 'thread',
    turnId: turnId,
    providerId: config.id,
    providerName: config.displayName,
    projectPath: '/work',
    sourceKind: 'fixture',
    startedAt: startedAt,
    status: UsageTaskStatus.completed,
    tokens: tokens,
  );
}

final class _FakeQuotaSource implements AgentUsageQuotaSource {
  const _FakeQuotaSource(this.result);

  final AgentUsageCapabilityResult<AgentUsageQuotaSnapshot> result;

  @override
  Future<AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>> loadQuota(
    AgentProviderConfig config,
  ) async => result;
}

final class _FakeTokenRegistry implements AgentTokenUsageSourceRegistry {
  const _FakeTokenRegistry(this.source);

  final AgentTokenUsageSource? source;

  @override
  AgentTokenUsageSource? createFor(AgentProviderConfig config) => source;
}

final class _FakeTokenSource implements AgentTokenUsageSource {
  const _FakeTokenSource(this.providerId, this.snapshot);

  @override
  final String providerId;

  final AgentTokenUsageSourceSnapshot snapshot;

  @override
  Future<AgentTokenUsageSourceSnapshot> load(AgentUsageQuery query) async =>
      snapshot;
}

final class _ThrowingTokenSource implements AgentTokenUsageSource {
  const _ThrowingTokenSource(this.providerId);

  @override
  final String providerId;

  @override
  Future<AgentTokenUsageSourceSnapshot> load(AgentUsageQuery query) {
    throw StateError('sensitive fixture failure');
  }
}
