import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/usage_statistics/application/usage_statistics_report_builder.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

void main() {
  group('UsageDateWindow', () {
    test('resolves current and previous seven-day windows', () {
      final now = DateTime(2026, 7, 10, 12);

      final window = UsageDateWindow.resolve(
        preset: UsageTimeRangePreset.last7Days,
        now: now,
      );

      expect(window.start, DateTime(2026, 7, 4));
      expect(window.endExclusive, now);
      expect(window.previous.endExclusive, window.start);
      expect(window.previous.duration, window.duration);
    });

    test('normalizes a reversed custom date range', () {
      final window = UsageDateWindow.resolve(
        preset: UsageTimeRangePreset.custom,
        now: DateTime(2026, 7, 10),
        customStart: DateTime(2026, 7, 9),
        customEndInclusive: DateTime(2026, 7, 5),
      );

      expect(window.start, DateTime(2026, 7, 5));
      expect(window.endExclusive, DateTime(2026, 7, 10));
    });
  });

  group('buildUsageStatisticsReport', () {
    test('aggregates success, duration, TTFT, tokens and rankings', () {
      final now = DateTime(2026, 7, 10, 12);
      final source = UsageStatisticsSourceSnapshot(
        refreshedAt: now,
        records: <AgentUsageRecord>[
          _record(
            turnId: 'success',
            projectPath: r'C:\work\alpha',
            startedAt: DateTime(2026, 7, 10, 9),
            status: UsageTaskStatus.completed,
            duration: const Duration(minutes: 2),
            ttft: const Duration(seconds: 2),
            inputTokens: 100,
            outputTokens: 40,
            totalTokens: 140,
          ),
          _record(
            turnId: 'failed',
            projectPath: r'C:\work\alpha',
            startedAt: DateTime(2026, 7, 9, 9),
            status: UsageTaskStatus.failed,
            duration: const Duration(minutes: 4),
            errorCategory: UsageErrorCategory.timeout,
            inputTokens: 80,
            outputTokens: 20,
            totalTokens: 100,
          ),
          _record(
            turnId: 'cancelled',
            projectPath: r'C:\work\beta',
            startedAt: DateTime(2026, 7, 8, 9),
            status: UsageTaskStatus.interrupted,
            duration: const Duration(minutes: 3),
            errorCategory: UsageErrorCategory.cancelled,
          ),
          _record(
            turnId: 'running',
            projectPath: r'C:\work\beta',
            startedAt: DateTime(2026, 7, 7, 9),
            status: UsageTaskStatus.running,
          ),
          _record(
            turnId: 'previous',
            projectPath: r'C:\work\alpha',
            startedAt: DateTime(2026, 7, 1, 9),
            status: UsageTaskStatus.completed,
          ),
        ],
      );
      final window = UsageDateWindow.resolve(
        preset: UsageTimeRangePreset.last7Days,
        now: now,
      );

      final report = buildUsageStatisticsReport(
        source: source,
        window: window,
        filter: const UsageStatisticsFilter(),
        trendMetric: UsageTrendMetric.calls,
        rankSort: UsageRankSort.calls,
      );

      expect(report.overview.totalCalls, 4);
      expect(report.overview.failedCalls, 2);
      expect(report.overview.successRate, closeTo(1 / 3, 0.0001));
      expect(report.overview.averageDuration, const Duration(minutes: 3));
      expect(report.overview.averageResponse, const Duration(seconds: 2));
      expect(report.overview.responseSampleCount, 1);
      expect(report.overview.tokens.totalTokens, 240);
      expect(report.agentRanking.single.calls, 4);
      expect(report.projectRanking.map((entry) => entry.projectName), [
        'alpha',
        'beta',
      ]);
      expect(report.modelShares.single.model, 'gpt-5');
      expect(report.errors.first.category, UsageErrorCategory.timeout);
      expect(
        report.trend.fold<double>(0, (sum, point) => sum + (point.value ?? 0)),
        4,
      );
      expect(report.overview.callComparison.previous, 1);
      expect(report.overview.callComparison.changePercent, 300);
    });

    test('applies project and model filters without losing filter options', () {
      final now = DateTime(2026, 7, 10, 12);
      final source = UsageStatisticsSourceSnapshot(
        refreshedAt: now,
        records: <AgentUsageRecord>[
          _record(
            turnId: 'alpha',
            projectPath: '/work/alpha',
            startedAt: DateTime(2026, 7, 10),
            status: UsageTaskStatus.completed,
          ),
          _record(
            turnId: 'beta',
            projectPath: '/work/beta',
            startedAt: DateTime(2026, 7, 9),
            status: UsageTaskStatus.completed,
            model: 'gpt-5-mini',
          ),
        ],
      );

      final report = buildUsageStatisticsReport(
        source: source,
        window: UsageDateWindow.resolve(
          preset: UsageTimeRangePreset.last7Days,
          now: now,
        ),
        filter: const UsageStatisticsFilter(
          projectPath: '/work/beta',
          model: 'gpt-5-mini',
        ),
        trendMetric: UsageTrendMetric.totalTokens,
        rankSort: UsageRankSort.totalTokens,
      );

      expect(report.records.single.turnId, 'beta');
      expect(report.projectOptions, ['/work/alpha', '/work/beta']);
      expect(report.modelOptions, ['gpt-5', 'gpt-5-mini']);
    });
  });
}

AgentUsageRecord _record({
  required String turnId,
  required String projectPath,
  required DateTime startedAt,
  required UsageTaskStatus status,
  Duration? duration,
  Duration? ttft,
  int? inputTokens,
  int? outputTokens,
  int? totalTokens,
  UsageErrorCategory? errorCategory,
  String model = 'gpt-5',
}) {
  return AgentUsageRecord(
    threadId: 'thread-$turnId',
    turnId: turnId,
    providerId: 'codex',
    providerName: 'Codex CLI',
    projectPath: projectPath,
    sourceKind: 'appServer',
    startedAt: startedAt,
    completedAt: status.isTerminal
        ? startedAt.add(duration ?? Duration.zero)
        : null,
    duration: duration,
    timeToFirstToken: ttft,
    model: model,
    status: status,
    tokens: UsageTokenBreakdown(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: totalTokens,
    ),
    errorCategory: errorCategory,
  );
}
