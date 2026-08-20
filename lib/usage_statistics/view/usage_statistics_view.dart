import 'package:app_ui/app_ui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/l10n/l10n.dart';
import 'package:zeta/usage_statistics/bloc/usage_statistics_bloc.dart';
import 'package:zeta/usage_statistics/bloc/usage_statistics_event.dart';
import 'package:zeta/usage_statistics/bloc/usage_statistics_state.dart';
import 'package:zeta/usage_statistics/cubit/agent_usage_panel_cubit.dart';

class UsageStatisticsView extends StatelessWidget {
  const UsageStatisticsView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        IdePageHeader(
          title: l10n.usagePageTitle,
          actions: <Widget>[
            TextButton(
              onPressed: () {
                context.read<UsageStatisticsBloc>().add(
                  const UsageStatisticsRepeatRefreshRequested(),
                );
              },
              child: Text(l10n.projectRefreshSessions),
            ),
          ],
        ),
        const Expanded(
          child: IdePageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _UsageFilters(),
                _UsageChart(),
                _UsageRank(),
                _UsagePanel(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UsageFilters extends StatelessWidget {
  const _UsageFilters();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<UsageStatisticsBloc>().state;
    return Wrap(
      children: <Widget>[
        TextButton(
          onPressed: () {
            context.read<UsageStatisticsBloc>().add(
              const UsageStatisticsPresetChanged(UsageTimePreset.today),
            );
          },
          child: Text(l10n.usageTimeRangeToday),
        ),
        TextButton(
          onPressed: () {
            context.read<UsageStatisticsBloc>().add(
              const UsageStatisticsPresetChanged(UsageTimePreset.last7Days),
            );
          },
          child: Text(l10n.usageTimeRangeLast7Days),
        ),
        TextButton(
          onPressed: () {
            context.read<UsageStatisticsBloc>().add(
              const UsageStatisticsRankSortChanged(UsageRankSort.calls),
            );
          },
          child: Text(l10n.usageRankSortCalls),
        ),
        if (state.status == UsageStatisticsStatus.failure)
          EmptyState(text: l10n.usageTokenHistoryUnavailable),
      ],
    );
  }
}

class _UsageChart extends StatelessWidget {
  const _UsageChart();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final points = context.select<UsageStatisticsBloc, List<UsageChartPoint>>(
      (bloc) => bloc.state.chartPoints,
    );
    if (points.isEmpty) {
      return const SizedBox.shrink();
    }
    return Semantics(
      label: l10n.usageTrendSemantic(
        l10n.usageTrendMetricTotalTokens,
        '${points.length}',
      ),
      child: SizedBox(
        height: 160,
        child: LineChart(
          LineChartData(
            lineBarsData: <LineChartBarData>[
              LineChartBarData(
                spots: <FlSpot>[
                  for (final point in points) FlSpot(point.x, point.y),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageRank extends StatelessWidget {
  const _UsageRank();

  @override
  Widget build(BuildContext context) {
    final records = context.select<UsageStatisticsBloc, List<UsageRecord>>(
      (bloc) => bloc.state.rankedRecords,
    );
    return Column(
      children: <Widget>[
        for (final record in records)
          IdeListRow(
            title: record.providerName,
            subtitle: record.projectPath,
          ),
      ],
    );
  }
}

class _UsagePanel extends StatelessWidget {
  const _UsagePanel();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<AgentUsagePanelCubit, AgentUsagePanelState>(
      builder: (context, state) {
        return Column(
          children: <Widget>[
            IdeSettingsRow(
              label: l10n.usageDetailTabsSemantic,
              control: Switch(
                value: state.tab == AgentUsagePanelTab.quota,
                onChanged: (value) {
                  context.read<AgentUsagePanelCubit>().selectTab(
                    value
                        ? AgentUsagePanelTab.quota
                        : AgentUsagePanelTab.summary,
                  );
                },
              ),
            ),
            if (state.status == AgentUsagePanelStatus.loading)
              const CircularProgressIndicator()
            else if (state.status == AgentUsagePanelStatus.failure)
              EmptyState(text: l10n.usageQuotaUnreadable)
            else
              for (final quota in state.quotaResults)
                IdeListRow(
                  title: quota.providerId,
                  subtitle: quota.failed
                      ? l10n.usageQuotaUnreadable
                      : quota.snapshot?.planType,
                ),
          ],
        );
      },
    );
  }
}
