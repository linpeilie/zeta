import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

void main() {
  test('AgentUsageQuery uses value equality including forceRefresh', () {
    final earliest = DateTime.utc(2026, 8, 12);

    expect(
      AgentUsageQuery(earliest: earliest),
      AgentUsageQuery(earliest: earliest),
    );
    expect(
      AgentUsageQuery(earliest: earliest),
      isNot(AgentUsageQuery(earliest: earliest, forceRefresh: true)),
    );
  });

  test('capability result distinguishes unsupported and unavailable', () {
    const warning = AgentUsageWarning(
      code: 'history-unavailable',
      message: '历史暂时不可用',
    );

    const unsupported = AgentUsageCapabilityResult<int>.unsupported();
    const unavailable = AgentUsageCapabilityResult<int>.unavailable(warning);
    const available = AgentUsageCapabilityResult<int>.available(42);

    expect(unsupported.status, AgentUsageCapabilityStatus.unsupported);
    expect(unsupported.isSupported, isFalse);
    expect(unavailable.status, AgentUsageCapabilityStatus.unavailable);
    expect(unavailable.isSupported, isTrue);
    expect(unavailable.warning, same(warning));
    expect(available.status, AgentUsageCapabilityStatus.available);
    expect(available.isAvailable, isTrue);
    expect(available.value, 42);
  });

  test('token source snapshot defensively copies its collections', () {
    final records = <AgentUsageRecord>[_record()];
    final warnings = <AgentUsageWarning>[
      const AgentUsageWarning(code: 'partial', message: '部分历史损坏'),
    ];
    final snapshot = AgentTokenUsageSourceSnapshot(
      providerId: 'test',
      providerName: 'Test',
      records: records,
      refreshedAt: DateTime.utc(2026, 8, 12),
      warnings: warnings,
    );

    records.clear();
    warnings.clear();

    expect(snapshot.records, hasLength(1));
    expect(snapshot.warnings, hasLength(1));
    expect(() => snapshot.records.add(_record()), throwsUnsupportedError);
    expect(
      () => snapshot.warnings.add(
        const AgentUsageWarning(code: 'late', message: 'late'),
      ),
      throwsUnsupportedError,
    );
  });

  test(
    'record identity includes Provider to avoid cross-source collisions',
    () {
      final first = _record();
      final second = AgentUsageRecord(
        threadId: first.threadId,
        turnId: first.turnId,
        providerId: 'other',
        providerName: 'Other',
        projectPath: first.projectPath,
        sourceKind: 'other',
        startedAt: first.startedAt,
        status: first.status,
      );

      expect(first.id, 'test/thread-1/turn-1');
      expect(second.id, 'other/thread-1/turn-1');
      expect(first.id, isNot(second.id));
    },
  );
}

AgentUsageRecord _record() => AgentUsageRecord(
  threadId: 'thread-1',
  turnId: 'turn-1',
  providerId: 'test',
  providerName: 'Test',
  projectPath: '/work',
  sourceKind: 'test',
  startedAt: DateTime.utc(2026, 8, 12),
  status: UsageTaskStatus.completed,
);
