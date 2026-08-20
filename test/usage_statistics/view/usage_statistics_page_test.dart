import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';
import 'package:zeta/l10n/l10n.dart';
import 'package:zeta/usage_statistics/usage_statistics.dart';

import '../../helpers/helpers.dart';

class _MockUsageStatisticsBloc
    extends MockBloc<UsageStatisticsEvent, UsageStatisticsState>
    implements UsageStatisticsBloc {}

class _MockAgentUsagePanelCubit extends MockCubit<AgentUsagePanelState>
    implements AgentUsagePanelCubit {}

class _MockUsageStatisticsRepository extends Mock
    implements UsageStatisticsRepository {}

void main() {
  group(UsageStatisticsPage, () {
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
      ).thenAnswer(
        (invocation) async => UsageStatisticsReport(
          query: invocation.positionalArguments.first as UsageStatisticsQuery,
          records: const <UsageRecord>[],
          totals: const UsageTotals(
            calls: 0,
            failures: 0,
            inputTokens: 0,
            cachedInputTokens: 0,
            outputTokens: 0,
            reasoningTokens: 0,
            totalTokens: 0,
          ),
          warnings: const <UsageWarning>[],
          refreshedAt: DateTime.utc(2026, 8, 20),
        ),
      );
    });

    testWidgets('renders $UsageStatisticsView', (tester) async {
      await tester.pumpApp(
        RepositoryProvider<UsageStatisticsRepository>.value(
          value: repository,
          child: const UsageStatisticsPage(),
        ),
      );
      await tester.pump();
      expect(find.byType(UsageStatisticsView), findsOneWidget);
    });
  });

  group(UsageStatisticsView, () {
    late UsageStatisticsBloc bloc;
    late AgentUsagePanelCubit panel;

    setUp(() {
      bloc = _MockUsageStatisticsBloc();
      panel = _MockAgentUsagePanelCubit();
      when(() => bloc.state).thenReturn(
        const UsageStatisticsState(status: UsageStatisticsStatus.ready),
      );
      when(() => panel.state).thenReturn(const AgentUsagePanelState());
    });

    testWidgets('requests a repeat refresh and last-7-days preset', (
      tester,
    ) async {
      await tester.pumpApp(
        MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<UsageStatisticsBloc>.value(value: bloc),
            BlocProvider<AgentUsagePanelCubit>.value(value: panel),
          ],
          child: const UsageStatisticsView(),
        ),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.projectRefreshSessions));
      await tester.tap(find.text(l10n.usageTimeRangeLast7Days));
      await tester.pump();
      verify(
        () => bloc.add(const UsageStatisticsRepeatRefreshRequested()),
      ).called(1);
      verify(
        () => bloc.add(
          const UsageStatisticsPresetChanged(UsageTimePreset.last7Days),
        ),
      ).called(1);
    });

    testWidgets('changes the time preset and rank sort', (tester) async {
      await tester.pumpApp(
        MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<UsageStatisticsBloc>.value(value: bloc),
            BlocProvider<AgentUsagePanelCubit>.value(value: panel),
          ],
          child: const UsageStatisticsView(),
        ),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.usageTimeRangeToday));
      await tester.tap(find.text(l10n.usageRankSortCalls));
      await tester.pump();
      verify(
        () => bloc.add(
          const UsageStatisticsPresetChanged(UsageTimePreset.today),
        ),
      ).called(1);
      verify(
        () => bloc.add(
          const UsageStatisticsRankSortChanged(UsageRankSort.calls),
        ),
      ).called(1);
    });

    testWidgets('renders precomputed chart points', (tester) async {
      when(() => bloc.state).thenReturn(
        const UsageStatisticsState(
          status: UsageStatisticsStatus.ready,
          chartPoints: <UsageChartPoint>[
            UsageChartPoint(x: 0, y: 4),
            UsageChartPoint(x: 1, y: 8),
          ],
        ),
      );
      await tester.pumpApp(
        MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<UsageStatisticsBloc>.value(value: bloc),
            BlocProvider<AgentUsagePanelCubit>.value(value: panel),
          ],
          child: const UsageStatisticsView(),
        ),
      );
      expect(find.byType(UsageStatisticsView), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('renders ranked rows and usage failure copy', (tester) async {
      when(() => bloc.state).thenReturn(
        UsageStatisticsState(
          status: UsageStatisticsStatus.failure,
          rankedRecords: <UsageRecord>[
            UsageRecord(
              threadId: 'thread-1',
              turnId: 'turn-1',
              providerId: 'codex',
              providerName: 'Codex',
              projectPath: '/repo',
              sourceKind: 'session',
              startedAt: DateTime.utc(2026, 8, 19),
              status: UsageTaskStatus.completed,
              tokens: const UsageTokenBreakdown(totalTokens: 1),
            ),
          ],
        ),
      );
      await tester.pumpApp(
        MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<UsageStatisticsBloc>.value(value: bloc),
            BlocProvider<AgentUsagePanelCubit>.value(value: panel),
          ],
          child: const UsageStatisticsView(),
        ),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text('Codex'), findsOneWidget);
      expect(find.text(l10n.usageTokenHistoryUnavailable), findsOneWidget);
    });

    testWidgets('renders quota failure and quota rows', (tester) async {
      when(() => panel.state).thenReturn(
        const AgentUsagePanelState(
          status: AgentUsagePanelStatus.failure,
          tab: AgentUsagePanelTab.quota,
          quotaResults: <UsageQuotaResult>[
            UsageQuotaResult(providerId: 'codex', failed: true),
          ],
        ),
      );
      await tester.pumpApp(
        MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<UsageStatisticsBloc>.value(value: bloc),
            BlocProvider<AgentUsagePanelCubit>.value(value: panel),
          ],
          child: const UsageStatisticsView(),
        ),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.usageQuotaUnreadable), findsWidgets);
    });

    testWidgets('renders quota loading progress', (tester) async {
      when(() => panel.state).thenReturn(
        const AgentUsagePanelState(
          status: AgentUsagePanelStatus.loading,
          tab: AgentUsagePanelTab.quota,
        ),
      );
      await tester.pumpApp(
        MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<UsageStatisticsBloc>.value(value: bloc),
            BlocProvider<AgentUsagePanelCubit>.value(value: panel),
          ],
          child: const UsageStatisticsView(),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders ready quota rows for failed and plan types', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      when(() => panel.state).thenReturn(
        AgentUsagePanelState(
          status: AgentUsagePanelStatus.ready,
          tab: AgentUsagePanelTab.quota,
          quotaResults: <UsageQuotaResult>[
            UsageQuotaResult(
              providerId: 'codex',
              snapshot: AgentUsageQuotaSnapshot(
                providerId: 'codex',
                providerName: 'Codex',
                windows: const <AgentUsageWindow>[],
                planType: 'plus',
              ),
            ),
            const UsageQuotaResult(providerId: 'grok', failed: true),
          ],
        ),
      );
      await tester.pumpApp(
        MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<UsageStatisticsBloc>.value(value: bloc),
            BlocProvider<AgentUsagePanelCubit>.value(value: panel),
          ],
          child: const UsageStatisticsView(),
        ),
      );
      expect(find.text('codex'), findsOneWidget);
      expect(find.text('plus'), findsOneWidget);
      expect(find.text('grok'), findsOneWidget);
      expect(find.text(l10n.usageQuotaUnreadable), findsOneWidget);
    });

    testWidgets('selects the quota panel tab', (tester) async {
      await tester.pumpApp(
        MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<UsageStatisticsBloc>.value(value: bloc),
            BlocProvider<AgentUsagePanelCubit>.value(value: panel),
          ],
          child: const UsageStatisticsView(),
        ),
      );
      await tester.tap(find.byType(Switch));
      await tester.pump();
      verify(
        () => panel.selectTab(AgentUsagePanelTab.quota),
      ).called(1);
    });

    testWidgets('selects the summary panel tab', (tester) async {
      when(() => panel.state).thenReturn(
        const AgentUsagePanelState(tab: AgentUsagePanelTab.quota),
      );
      await tester.pumpApp(
        MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<UsageStatisticsBloc>.value(value: bloc),
            BlocProvider<AgentUsagePanelCubit>.value(value: panel),
          ],
          child: const UsageStatisticsView(),
        ),
      );
      await tester.tap(find.byType(Switch));
      await tester.pump();
      verify(
        () => panel.selectTab(AgentUsagePanelTab.summary),
      ).called(1);
    });
  });
}
