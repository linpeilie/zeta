import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';
import 'package:zeta/usage_statistics/usage_statistics.dart';

class _MockUsageStatisticsRepository extends Mock
    implements UsageStatisticsRepository {}

void main() {
  final startedAt = DateTime.utc(2026, 8, 19, 8);
  final record = UsageRecord(
    threadId: 'thread-1',
    turnId: 'turn-1',
    providerId: 'codex',
    providerName: 'Codex',
    projectPath: '/repo',
    sourceKind: 'session',
    startedAt: startedAt,
    status: UsageTaskStatus.completed,
    tokens: const UsageTokenBreakdown(totalTokens: 12),
    duration: const Duration(seconds: 3),
    model: 'gpt',
  );
  final failed = UsageRecord(
    threadId: 'thread-2',
    turnId: 'turn-2',
    providerId: 'grok',
    providerName: 'Grok',
    projectPath: '/other',
    sourceKind: 'session',
    startedAt: startedAt.add(const Duration(hours: 1)),
    status: UsageTaskStatus.failed,
    tokens: const UsageTokenBreakdown(totalTokens: 4),
    duration: const Duration(seconds: 1),
    model: 'grok-1',
  );

  UsageStatisticsReport reportFor(UsageStatisticsQuery query) {
    return UsageStatisticsReport(
      query: query,
      records: <UsageRecord>[record, failed],
      totals: const UsageTotals(
        calls: 2,
        failures: 1,
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        reasoningTokens: 0,
        totalTokens: 16,
      ),
      warnings: const <UsageWarning>[],
      refreshedAt: DateTime.utc(2026, 8, 20, 12),
    );
  }

  group(UsageStatisticsBloc, () {
    late UsageStatisticsRepository repository;

    setUpAll(() {
      registerFallbackValue(
        UsageStatisticsQuery(
          startInclusive: DateTime.utc(2026, 8),
          endExclusive: DateTime.utc(2026, 8, 21),
        ),
      );
    });

    setUp(() {
      repository = _MockUsageStatisticsRepository();
      when(
        () => repository.report(
          any(),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        final isCancelled =
            invocation.namedArguments[#isCancelled] as bool Function();
        isCancelled();
        final query =
            invocation.positionalArguments.first as UsageStatisticsQuery;
        return reportFor(query);
      });
    });

    UsageStatisticsBloc build() {
      return UsageStatisticsBloc(
        usageStatisticsRepository: repository,
        clock: () => DateTime.utc(2026, 8, 20, 12),
      );
    }

    blocTest<UsageStatisticsBloc, UsageStatisticsState>(
      'loads a report and precomputes chart points',
      build: build,
      act: (bloc) => bloc.add(const UsageStatisticsStarted()),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.status, UsageStatisticsStatus.ready);
        expect(bloc.state.report?.totals.calls, 2);
        expect(bloc.state.chartPoints, isNotEmpty);
        expect(bloc.state.rankedRecords, hasLength(2));
      },
    );

    blocTest<UsageStatisticsBloc, UsageStatisticsState>(
      'recomputes the query when the preset changes',
      build: build,
      act: (bloc) async {
        bloc.add(const UsageStatisticsStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(
          const UsageStatisticsPresetChanged(UsageTimePreset.today),
        );
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.preset, UsageTimePreset.today);
      },
    );

    blocTest<UsageStatisticsBloc, UsageStatisticsState>(
      'filters ranked records by project, provider, and model',
      build: build,
      act: (bloc) async {
        bloc.add(const UsageStatisticsStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const UsageStatisticsProjectChanged('/repo'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const UsageStatisticsProviderChanged('codex'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const UsageStatisticsModelChanged('gpt'));
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(bloc.state.rankedRecords, <UsageRecord>[record]);
      },
    );

    blocTest<UsageStatisticsBloc, UsageStatisticsState>(
      're-ranks without reloading when the sort changes',
      build: build,
      seed: () => UsageStatisticsState(
        status: UsageStatisticsStatus.ready,
        report: reportFor(
          UsageStatisticsQuery(
            startInclusive: DateTime.utc(2026, 8, 14),
            endExclusive: DateTime.utc(2026, 8, 21),
          ),
        ),
        rankedRecords: <UsageRecord>[record, failed],
      ),
      act: (bloc) {
        bloc.add(
          const UsageStatisticsRankSortChanged(UsageRankSort.failures),
        );
      },
      verify: (bloc) {
        expect(bloc.state.rankedRecords.first, failed);
      },
    );

    blocTest<UsageStatisticsBloc, UsageStatisticsState>(
      'covers remaining presets and a forced refresh',
      build: build,
      act: (bloc) async {
        for (final preset in UsageTimePreset.values) {
          bloc.add(UsageStatisticsPresetChanged(preset));
          await Future<void>.delayed(Duration.zero);
        }
        bloc
          ..add(const UsageStatisticsRefreshRequested())
          ..add(const UsageStatisticsRepeatRefreshRequested());
      },
      wait: const Duration(milliseconds: 40),
      verify: (bloc) {
        expect(bloc.state.preset, UsageTimePreset.previousMonth);
        expect(bloc.state.status, UsageStatisticsStatus.ready);
      },
    );

    blocTest<UsageStatisticsBloc, UsageStatisticsState>(
      'keeps the previous report when a scan is cancelled',
      build: () {
        when(
          () => repository.report(
            any(),
            isCancelled: any(named: 'isCancelled'),
          ),
        ).thenThrow(const UsageStatisticsCancelledException());
        return build();
      },
      seed: () => UsageStatisticsState(
        status: UsageStatisticsStatus.ready,
        report: reportFor(
          UsageStatisticsQuery(
            startInclusive: DateTime.utc(2026, 8, 14),
            endExclusive: DateTime.utc(2026, 8, 21),
          ),
        ),
        queryGeneration: 3,
      ),
      act: (bloc) => bloc.add(const UsageStatisticsRefreshRequested()),
      expect: () => <Matcher>[
        isA<UsageStatisticsState>().having(
          (state) => state.status,
          'status',
          UsageStatisticsStatus.loading,
        ),
        isA<UsageStatisticsState>()
            .having((state) => state.cancelled, 'cancelled', isTrue)
            .having((state) => state.report, 'report', isNotNull),
      ],
    );

    blocTest<UsageStatisticsBloc, UsageStatisticsState>(
      'fails when a scan is cancelled before any report exists',
      build: () {
        when(
          () => repository.report(
            any(),
            isCancelled: any(named: 'isCancelled'),
          ),
        ).thenThrow(const UsageStatisticsCancelledException());
        return build();
      },
      act: (bloc) => bloc.add(const UsageStatisticsStarted()),
      expect: () => <Matcher>[
        isA<UsageStatisticsState>().having(
          (state) => state.status,
          'status',
          UsageStatisticsStatus.loading,
        ),
        isA<UsageStatisticsState>().having(
          (state) => state.status,
          'status',
          UsageStatisticsStatus.failure,
        ),
      ],
    );

    blocTest<UsageStatisticsBloc, UsageStatisticsState>(
      'emits failure when the repository throws',
      build: () {
        when(
          () => repository.report(
            any(),
            isCancelled: any(named: 'isCancelled'),
          ),
        ).thenThrow(Exception('io'));
        return build();
      },
      act: (bloc) => bloc.add(const UsageStatisticsStarted()),
      expect: () => <Matcher>[
        isA<UsageStatisticsState>().having(
          (state) => state.status,
          'status',
          UsageStatisticsStatus.loading,
        ),
        isA<UsageStatisticsState>().having(
          (state) => state.status,
          'status',
          UsageStatisticsStatus.failure,
        ),
      ],
    );

    blocTest<UsageStatisticsBloc, UsageStatisticsState>(
      'clears optional filters and re-ranks remaining sorts',
      build: build,
      seed: () => UsageStatisticsState(
        status: UsageStatisticsStatus.ready,
        projectPath: '/repo',
        providerId: 'codex',
        model: 'gpt',
        report: reportFor(
          UsageStatisticsQuery(
            startInclusive: DateTime.utc(2026, 8, 14),
            endExclusive: DateTime.utc(2026, 8, 21),
          ),
        ),
      ),
      act: (bloc) async {
        bloc.add(const UsageStatisticsProjectChanged(null));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const UsageStatisticsProviderChanged(null));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const UsageStatisticsModelChanged(null));
        await Future<void>.delayed(Duration.zero);
        bloc
          ..add(
            const UsageStatisticsRankSortChanged(UsageRankSort.totalTokens),
          )
          ..add(
            const UsageStatisticsRankSortChanged(
              UsageRankSort.averageDuration,
            ),
          )
          ..add(const UsageStatisticsRankSortChanged(UsageRankSort.calls));
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(bloc.state.projectPath, isNull);
        expect(bloc.state.providerId, isNull);
        expect(bloc.state.model, isNull);
        expect(bloc.state.rankSort, UsageRankSort.calls);
      },
    );

    test('copyWith clears optional usage fields', () {
      final report = reportFor(
        UsageStatisticsQuery(
          startInclusive: DateTime.utc(2026, 8, 14),
          endExclusive: DateTime.utc(2026, 8, 21),
        ),
      );
      final state = UsageStatisticsState(
        projectPath: '/repo',
        providerId: 'codex',
        model: 'gpt',
        report: report,
      );
      final cleared = state.copyWith(
        clearProject: true,
        clearProvider: true,
        clearModel: true,
        clearReport: true,
      );
      expect(cleared.projectPath, isNull);
      expect(cleared.providerId, isNull);
      expect(cleared.model, isNull);
      expect(cleared.report, isNull);
    });

    test('event equality uses value props', () {
      expect(const UsageStatisticsStarted().props, isEmpty);
      expect(
        const UsageStatisticsPresetChanged(UsageTimePreset.today).props,
        <Object?>[UsageTimePreset.today],
      );
      expect(
        const UsageStatisticsProjectChanged('/repo').props,
        <Object?>['/repo'],
      );
      expect(
        const UsageStatisticsProviderChanged('codex').props,
        <Object?>['codex'],
      );
      expect(
        const UsageStatisticsModelChanged('gpt').props,
        <Object?>['gpt'],
      );
      expect(
        const UsageStatisticsRankSortChanged(UsageRankSort.calls).props,
        <Object?>[UsageRankSort.calls],
      );
      expect(const UsageStatisticsRefreshRequested().props, isEmpty);
      expect(const UsageStatisticsRepeatRefreshRequested().props, isEmpty);
      expect(
        const UsageChartPoint(x: 1, y: 2).props,
        <Object?>[1.0, 2.0],
      );
    });
  });
}
