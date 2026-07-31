import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/usage_statistics/data/composite_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';

void main() {
  test(
    'merges records from all sources and keeps provider identities',
    () async {
      final repository = CompositeUsageStatisticsRepository(
        sources: <UsageStatisticsRepository>[
          _FakeUsageSource(
            records: <AgentUsageRecord>[
              _record(
                providerId: 'codex',
                providerName: 'Codex',
                turnId: 'c1',
                startedAt: DateTime(2026, 7, 10, 10),
              ),
            ],
          ),
          _FakeUsageSource(
            records: <AgentUsageRecord>[
              _record(
                providerId: 'grok',
                providerName: 'Grok',
                turnId: 'g1',
                startedAt: DateTime(2026, 7, 10, 11),
              ),
            ],
          ),
        ],
        clock: () => DateTime(2026, 7, 10, 12),
      );

      final snapshot = await repository.load(earliest: DateTime(2026, 7, 1));

      expect(snapshot.records, hasLength(2));
      expect(
        snapshot.records.map((record) => record.providerId).toSet(),
        <String>{'codex', 'grok'},
      );
      // 按开始时间倒序。
      expect(snapshot.records.first.turnId, 'g1');
      expect(snapshot.records.last.turnId, 'c1');
    },
  );

  test('isolates a failing source without dropping other providers', () async {
    final repository = CompositeUsageStatisticsRepository(
      sources: <UsageStatisticsRepository>[
        _FakeUsageSource(
          records: <AgentUsageRecord>[
            _record(
              providerId: 'codex',
              providerName: 'Codex',
              turnId: 'c1',
              startedAt: DateTime(2026, 7, 10, 10),
            ),
          ],
        ),
        _FailingUsageSource(),
      ],
      clock: () => DateTime(2026, 7, 10, 12),
    );

    final snapshot = await repository.load(earliest: DateTime(2026, 7, 1));

    expect(snapshot.records, hasLength(1));
    expect(snapshot.records.single.providerId, 'codex');
    expect(snapshot.warnings, isNotEmpty);
  });
}

class _FakeUsageSource implements UsageStatisticsRepository {
  _FakeUsageSource({required this.records});

  final List<AgentUsageRecord> records;

  @override
  Future<UsageStatisticsSourceSnapshot> load({
    required DateTime earliest,
    bool forceRefresh = false,
  }) async {
    return UsageStatisticsSourceSnapshot(
      records: records,
      refreshedAt: DateTime(2026, 7, 10, 12),
    );
  }
}

class _FailingUsageSource implements UsageStatisticsRepository {
  @override
  Future<UsageStatisticsSourceSnapshot> load({
    required DateTime earliest,
    bool forceRefresh = false,
  }) async {
    throw StateError('boom');
  }
}

AgentUsageRecord _record({
  required String providerId,
  required String providerName,
  required String turnId,
  required DateTime startedAt,
}) {
  return AgentUsageRecord(
    threadId: 'thread-$turnId',
    turnId: turnId,
    providerId: providerId,
    providerName: providerName,
    projectPath: '/work',
    sourceKind: 'test',
    startedAt: startedAt,
    status: UsageTaskStatus.completed,
  );
}
