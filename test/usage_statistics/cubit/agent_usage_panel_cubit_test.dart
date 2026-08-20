import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';
import 'package:zeta/usage_statistics/usage_statistics.dart';

class _MockUsageStatisticsRepository extends Mock
    implements UsageStatisticsRepository {}

void main() {
  const quota = UsageQuotaResult(providerId: 'codex', failed: true);

  group(AgentUsagePanelCubit, () {
    late UsageStatisticsRepository repository;

    setUp(() {
      repository = _MockUsageStatisticsRepository();
      when(
        () => repository.quotaSnapshots(),
      ).thenAnswer((_) async => const <UsageQuotaResult>[quota]);
    });

    AgentUsagePanelCubit build() {
      return AgentUsagePanelCubit(usageStatisticsRepository: repository);
    }

    blocTest<AgentUsagePanelCubit, AgentUsagePanelState>(
      'loads quota when the quota tab is selected',
      build: build,
      act: (cubit) => cubit.selectTab(AgentUsagePanelTab.quota),
      wait: const Duration(milliseconds: 10),
      verify: (cubit) {
        expect(cubit.state.tab, AgentUsagePanelTab.quota);
        expect(cubit.state.quotaResults, const <UsageQuotaResult>[quota]);
      },
    );

    blocTest<AgentUsagePanelCubit, AgentUsagePanelState>(
      'does not load quota when selecting the summary tab',
      build: build,
      act: (cubit) => cubit.selectTab(AgentUsagePanelTab.summary),
      verify: (cubit) {
        expect(cubit.state.tab, AgentUsagePanelTab.summary);
        verifyNever(() => repository.quotaSnapshots());
      },
    );

    blocTest<AgentUsagePanelCubit, AgentUsagePanelState>(
      'emits failure when quota loading throws',
      build: () {
        when(() => repository.quotaSnapshots()).thenThrow(Exception('io'));
        return build();
      },
      act: (cubit) => cubit.loadQuota(),
      expect: () => <Matcher>[
        isA<AgentUsagePanelState>().having(
          (state) => state.status,
          'status',
          AgentUsagePanelStatus.loading,
        ),
        isA<AgentUsagePanelState>().having(
          (state) => state.status,
          'status',
          AgentUsagePanelStatus.failure,
        ),
      ],
    );

    blocTest<AgentUsagePanelCubit, AgentUsagePanelState>(
      'does not start a second quota load while one is in flight',
      build: () {
        when(() => repository.quotaSnapshots()).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return const <UsageQuotaResult>[quota];
        });
        return build();
      },
      act: (cubit) async {
        final first = cubit.loadQuota();
        await cubit.loadQuota();
        await first;
      },
      verify: (_) {
        verify(() => repository.quotaSnapshots()).called(1);
      },
    );
  });
}
