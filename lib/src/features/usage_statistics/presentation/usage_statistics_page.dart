import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_controller.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_report_builder.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_formatters.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_status_card.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

/// 本地 Agent CLI 使用统计页面。
class UsageStatisticsPage extends StatefulWidget {
  const UsageStatisticsPage({
    required this.controller,
    required this.onBackPressed,
    required this.onOpenAgentManagement,
    super.key,
  });

  final UsageStatisticsController controller;
  final VoidCallback onBackPressed;
  final VoidCallback onOpenAgentManagement;

  @override
  State<UsageStatisticsPage> createState() => _UsageStatisticsPageState();
}

class _UsageStatisticsPageState extends State<UsageStatisticsPage> {
  static const double _twoColumnBreakpoint = 980;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      key: const ValueKey('usage-statistics-page'),
      showBorder: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PageHeader(onBackPressed: widget.onBackPressed),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) => _buildBody(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final controller = widget.controller;
    final report = controller.report;
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= _twoColumnBreakpoint;
        return ListView(
          key: const ValueKey('usage-statistics-scroll-view'),
          padding: IdeSpacing.all16,
          children: [
            _UsageFilters(controller: controller, report: report),
            const SizedBox(height: IdeSpacing.space12),
            if (controller.loading) ...[
              const sf.Progress(progress: null),
              const SizedBox(height: IdeSpacing.space12),
            ],
            if (controller.errorMessage case final error?)
              IdeStatusCard(
                tone: IdeStatusCardTone.error,
                title: '统计加载失败',
                body: Text(error),
                footer: Align(
                  alignment: Alignment.centerLeft,
                  child: sf.OutlineButton(
                    onPressed: controller.refresh,
                    size: sf.ButtonSize.small,
                    child: const Text('重新加载'),
                  ),
                ),
              ),
            for (final warning in controller.warnings)
              IdeStatusCard(
                tone: IdeStatusCardTone.warning,
                title: '部分数据不可用',
                body: Text(warning),
              ),
            if (report == null && controller.loading)
              const _LoadingState()
            else if (report == null)
              const SizedBox.shrink()
            else ...[
              _OverviewGrid(overview: report.overview),
              const SizedBox(height: IdeSpacing.space12),
              _TrendSection(controller: controller, report: report),
              const SizedBox(height: IdeSpacing.space12),
              if (report.records.isEmpty)
                _EmptyUsageState(
                  onOpenAgentManagement: widget.onOpenAgentManagement,
                )
              else ...[
                _ResponsivePair(
                  twoColumns: twoColumns,
                  left: _AgentRankingSection(
                    controller: controller,
                    entries: report.agentRanking,
                  ),
                  right: _ProjectRankingSection(
                    entries: report.projectRanking,
                    onProjectSelected: controller.selectProject,
                  ),
                ),
                const SizedBox(height: IdeSpacing.space12),
                _ResponsivePair(
                  twoColumns: twoColumns,
                  left: _TokenAnalysisSection(report: report),
                  right: _QuotaSection(quota: controller.source?.quota),
                ),
                const SizedBox(height: IdeSpacing.space12),
                _RecentTasksSection(
                  records: report.records,
                  onTaskPressed: (record) => _openTaskDrawer(context, record),
                ),
                const SizedBox(height: IdeSpacing.space12),
                _ErrorAnalysisSection(
                  errors: report.errors,
                  records: report.records,
                  onCategoryPressed: (category) {
                    _openErrorDrawer(context, category, report.records);
                  },
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  void _openTaskDrawer(BuildContext context, AgentUsageRecord record) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    sf.openDrawer(
      context: context,
      expands: narrow,
      position: narrow ? sf.OverlayPosition.bottom : sf.OverlayPosition.end,
      builder: (drawerContext) => _TaskDetailDrawer(record: record),
    );
  }

  void _openErrorDrawer(
    BuildContext context,
    UsageErrorCategory category,
    List<AgentUsageRecord> records,
  ) {
    final matching = records
        .where(
          (record) =>
              record.status.isFailure &&
              (record.errorCategory ?? UsageErrorCategory.other) == category,
        )
        .toList();
    final narrow = MediaQuery.sizeOf(context).width < 700;
    sf.openDrawer(
      context: context,
      expands: narrow,
      position: narrow ? sf.OverlayPosition.bottom : sf.OverlayPosition.end,
      builder: (drawerContext) => _ErrorListDrawer(
        category: category,
        records: matching,
        onTaskPressed: (record) {
          sf.closeOverlay(drawerContext);
          _openTaskDrawer(context, record);
        },
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.onBackPressed});

  final VoidCallback onBackPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Container(
      padding: IdeSpacing.all12,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          sf.IconButton.ghost(
            key: const ValueKey('usage-statistics-back-button'),
            onPressed: onBackPressed,
            size: sf.ButtonSize.small,
            density: sf.ButtonDensity.iconDense,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
          ),
          const SizedBox(width: IdeSpacing.space8),
          Icon(Icons.query_stats_rounded, size: 20, color: colors.accent),
          const SizedBox(width: IdeSpacing.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('使用统计', style: textStyles.displaySmall),
                Text(
                  '分析本地 Codex 的调用、性能、Token、项目与套餐额度',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageFilters extends StatelessWidget {
  const _UsageFilters({required this.controller, required this.report});

  static const String _all = '__all__';

  final UsageStatisticsController controller;
  final UsageStatisticsReport? report;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final report = this.report;
    final projects = report?.projectOptions ?? const <String>[];
    final agents = report?.agentOptions ?? const <String>[];
    final models = report?.modelOptions ?? const <String>[];
    return PanelCard(
      child: Padding(
        padding: IdeSpacing.cardPadding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final fieldWidth = compact ? constraints.maxWidth : 190.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: IdeSpacing.space8,
                  runSpacing: IdeSpacing.space8,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    _LabeledFilter(
                      label: '时间范围',
                      width: fieldWidth,
                      child: _select<UsageTimeRangePreset>(
                        key: const ValueKey('usage-time-range-filter'),
                        width: fieldWidth,
                        value: controller.timePreset,
                        options: [
                          for (final preset in UsageTimeRangePreset.values)
                            _SelectOption(preset, preset.label),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            unawaited(controller.selectTimePreset(value));
                          }
                        },
                      ),
                    ),
                    _LabeledFilter(
                      label: '项目',
                      width: fieldWidth,
                      child: _select<String>(
                        key: const ValueKey('usage-project-filter'),
                        width: fieldWidth,
                        value: controller.projectPath ?? _all,
                        options: <_SelectOption<String>>[
                          const _SelectOption(_all, '全部项目'),
                          for (final project in projects)
                            _SelectOption(project, usageProjectName(project)),
                        ],
                        onChanged: (value) => controller.selectProject(
                          value == null || value == _all ? null : value,
                        ),
                      ),
                    ),
                    _LabeledFilter(
                      label: 'Agent',
                      width: fieldWidth,
                      child: _select<String>(
                        key: const ValueKey('usage-agent-filter'),
                        width: fieldWidth,
                        value: controller.providerId ?? _all,
                        options: <_SelectOption<String>>[
                          const _SelectOption(_all, '全部 Agent'),
                          for (final agent in agents)
                            _SelectOption(agent, _providerName(report, agent)),
                        ],
                        onChanged: (value) => controller.selectProvider(
                          value == null || value == _all ? null : value,
                        ),
                      ),
                    ),
                    _LabeledFilter(
                      label: '模型',
                      width: fieldWidth,
                      child: _select<String>(
                        key: const ValueKey('usage-model-filter'),
                        width: fieldWidth,
                        value: controller.model ?? _all,
                        options: <_SelectOption<String>>[
                          const _SelectOption(_all, '全部模型'),
                          for (final model in models)
                            _SelectOption(model, model),
                        ],
                        onChanged: (value) => controller.selectModel(
                          value == null || value == _all ? null : value,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: compact ? constraints.maxWidth : null,
                      child: Row(
                        mainAxisSize: compact
                            ? MainAxisSize.max
                            : MainAxisSize.min,
                        children: [
                          if (compact) const Spacer(),
                          Text(
                            '最后更新：${formatUsageClock(controller.lastUpdated)}',
                            style: textStyles.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: IdeSpacing.space8),
                          sf.OutlineButton(
                            key: const ValueKey('usage-refresh-button'),
                            onPressed: controller.loading
                                ? null
                                : controller.refresh,
                            size: sf.ButtonSize.small,
                            leading: const Icon(
                              Icons.refresh_rounded,
                              size: 15,
                            ),
                            child: const Text('刷新'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (controller.timePreset == UsageTimeRangePreset.custom) ...[
                  const SizedBox(height: IdeSpacing.space8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: compact ? constraints.maxWidth : 320,
                      child: sf.DateRangePicker(
                        key: const ValueKey('usage-custom-date-range'),
                        value: sf.DateTimeRange(
                          controller.customStart ??
                              DateTime.now().subtract(const Duration(days: 6)),
                          controller.customEndInclusive ?? DateTime.now(),
                        ),
                        mode: compact
                            ? sf.PromptMode.dialog
                            : sf.PromptMode.popover,
                        dialogTitle: const Text('选择统计日期'),
                        onChanged: (range) {
                          if (range != null) {
                            unawaited(
                              controller.selectCustomRange(
                                range.start,
                                range.end,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  static Widget _select<T>({
    required Key key,
    required double width,
    required T value,
    required List<_SelectOption<T>> options,
    required ValueChanged<T?> onChanged,
  }) {
    return sf.Select<T>(
      key: key,
      value: value,
      constraints: BoxConstraints.tightFor(width: width),
      popupConstraints: BoxConstraints(maxHeight: 320, minWidth: width),
      itemBuilder: (context, selected) {
        final option = options.firstWhere(
          (candidate) => candidate.value == selected,
          orElse: () => options.first,
        );
        return Text(option.label, maxLines: 1, overflow: TextOverflow.ellipsis);
      },
      onChanged: onChanged.call,
      popup: sf.SelectPopup.noVirtualization(
        items: sf.SelectItemList(
          children: [
            for (final option in options)
              sf.SelectItemButton(
                value: option.value,
                child: Text(option.label),
              ),
          ],
        ),
      ).call,
    );
  }

  static String _providerName(UsageStatisticsReport? report, String id) {
    if (report != null) {
      for (final record in report.records) {
        if (record.providerId == id) {
          return record.providerName;
        }
      }
    }
    return id;
  }
}

class _SelectOption<T> {
  const _SelectOption(this.value, this.label);

  final T value;
  final String label;
}

class _LabeledFilter extends StatelessWidget {
  const _LabeledFilter({
    required this.label,
    required this.width,
    required this.child,
  });

  final String label;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: textStyles.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: IdeSpacing.space4),
          child,
        ],
      ),
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.overview});

  final UsageOverview overview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 5
            : constraints.maxWidth >= 720
            ? 3
            : constraints.maxWidth >= 420
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - (IdeSpacing.space8 * (columns - 1))) /
            columns;
        final comparison = overview.callComparison;
        final comparisonText = comparison.changePercent == null
            ? comparison.current > 0
                  ? '上一周期无调用'
                  : '与上一周期持平'
            : '${comparison.changePercent! >= 0 ? '↑' : '↓'} '
                  '${comparison.changePercent!.abs().toStringAsFixed(1)}% · 相比上一周期';
        return Wrap(
          spacing: IdeSpacing.space8,
          runSpacing: IdeSpacing.space8,
          children: [
            _MetricCard(
              width: width,
              label: '调用次数',
              value: formatUsageCount(overview.totalCalls),
              detail: comparisonText,
              icon: Icons.bolt_rounded,
            ),
            _MetricCard(
              width: width,
              label: '成功率',
              value: formatUsagePercent(overview.successRate),
              detail: '失败：${overview.failedCalls} 次',
              icon: Icons.check_circle_outline_rounded,
            ),
            _MetricCard(
              width: width,
              label: '平均响应时间',
              value: formatUsageDuration(overview.averageResponse),
              detail: overview.responseSampleCount == 0
                  ? '暂无可靠 TTFT 样本'
                  : '有效样本：${overview.responseSampleCount}',
              icon: Icons.speed_rounded,
            ),
            _MetricCard(
              width: width,
              label: '平均任务耗时',
              value: formatUsageDuration(overview.averageDuration),
              detail: '按 Codex turn 统计',
              icon: Icons.timer_outlined,
            ),
            _MetricCard(
              width: width,
              label: 'Token 使用量',
              value: overview.tokens.hasData
                  ? formatUsageCount(overview.tokens.effectiveTotal ?? 0)
                  : '不支持',
              detail: overview.tokens.hasData
                  ? '输入 ${formatUsageCount(overview.tokens.inputTokens ?? 0)} · '
                        '输出 ${formatUsageCount(overview.tokens.outputTokens ?? 0)} · '
                        '推理 ${formatUsageCount(overview.tokens.reasoningTokens ?? 0)}'
                  : '当前 Agent 不支持 Token 统计',
              icon: Icons.data_usage_rounded,
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
  });

  final double width;
  final String label;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return SizedBox(
      width: width,
      child: PanelCard(
        color: colors.surfaceElevated,
        child: Padding(
          padding: IdeSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: colors.accent),
                  const SizedBox(width: IdeSpacing.space6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyles.bodySmall.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: IdeSpacing.space8),
              Text(value, style: textStyles.displayLarge),
              const SizedBox(height: IdeSpacing.space4),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textStyles.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendSection extends StatelessWidget {
  const _TrendSection({required this.controller, required this.report});

  final UsageStatisticsController controller;
  final UsageStatisticsReport report;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '使用趋势',
      subtitle: '粒度根据时间范围自动调整',
      trailing: IdeTabs<UsageTrendMetric>(
        value: controller.trendMetric,
        semanticLabel: '趋势指标',
        items: [
          for (final metric in UsageTrendMetric.values)
            IdeTabItem<UsageTrendMetric>(
              key: ValueKey<String>('usage-trend-${metric.name}'),
              value: metric,
              label: metric.label,
            ),
        ],
        onChanged: controller.selectTrendMetric,
      ),
      child: _UsageLineChart(
        key: ValueKey<String>(
          'usage-main-chart-${controller.trendMetric.name}',
        ),
        points: report.trend,
        metric: controller.trendMetric,
      ),
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({
    required this.twoColumns,
    required this.left,
    required this.right,
  });

  final bool twoColumns;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (!twoColumns) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          left,
          const SizedBox(height: IdeSpacing.space12),
          right,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: IdeSpacing.space12),
        Expanded(child: right),
      ],
    );
  }
}

class _AgentRankingSection extends StatelessWidget {
  const _AgentRankingSection({required this.controller, required this.entries});

  final UsageStatisticsController controller;
  final List<UsageAgentRankEntry> entries;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Agent 使用排行',
      subtitle: '按当前筛选范围汇总',
      trailing: _UsageFilters._select<UsageRankSort>(
        key: const ValueKey('usage-agent-rank-sort'),
        width: 140,
        value: controller.rankSort,
        options: [
          for (final sort in UsageRankSort.values)
            _SelectOption(sort, sort.label),
        ],
        onChanged: (value) {
          if (value != null) {
            controller.selectRankSort(value);
          }
        },
      ),
      child: _UsageTable(
        minWidth: 620,
        headers: const ['Agent', '调用次数', '成功率', 'Token', '失败', '平均耗时'],
        flexes: const [3, 2, 2, 2, 2, 2],
        rows: [
          for (final entry in entries)
            [
              entry.providerName,
              formatUsageCount(entry.calls),
              formatUsagePercent(entry.successRate),
              entry.totalTokens == null
                  ? '不支持'
                  : formatUsageCount(entry.totalTokens!),
              entry.failures.toString(),
              formatUsageDuration(entry.averageDuration, compact: true),
            ],
        ],
      ),
    );
  }
}

class _ProjectRankingSection extends StatelessWidget {
  const _ProjectRankingSection({
    required this.entries,
    required this.onProjectSelected,
  });

  final List<UsageProjectRankEntry> entries;
  final ValueChanged<String?> onProjectSelected;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '项目使用排行',
      subtitle: '点击项目可直接应用筛选',
      child: _UsageTable(
        minWidth: 620,
        headers: const ['项目', '调用次数', 'Token', '平均耗时', '最近使用'],
        flexes: const [3, 2, 2, 2, 2],
        rows: [
          for (final entry in entries)
            [
              entry.projectName,
              formatUsageCount(entry.calls),
              entry.totalTokens == null
                  ? '不支持'
                  : formatUsageCount(entry.totalTokens!),
              formatUsageDuration(entry.averageDuration, compact: true),
              formatUsageRelativeTime(entry.lastUsedAt, DateTime.now()),
            ],
        ],
        rowKeys: [for (final entry in entries) entry.projectPath],
        onRowPressed: (index) => onProjectSelected(entries[index].projectPath),
      ),
    );
  }
}

class _TokenAnalysisSection extends StatelessWidget {
  const _TokenAnalysisSection({required this.report});

  final UsageStatisticsReport report;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final tokens = report.overview.tokens;
    return _SectionCard(
      title: 'Token 分析',
      subtitle: '输入、输出与模型消耗比例',
      child: tokens.hasData
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: IdeSpacing.space12,
                  runSpacing: IdeSpacing.space6,
                  children: [
                    _InlineMetric(
                      label: '总量',
                      value: formatUsageCount(tokens.effectiveTotal ?? 0),
                    ),
                    _InlineMetric(
                      label: '输入',
                      value: formatUsageCount(tokens.inputTokens ?? 0),
                    ),
                    _InlineMetric(
                      label: '缓存输入',
                      value: formatUsageCount(tokens.cachedInputTokens ?? 0),
                    ),
                    _InlineMetric(
                      label: '输出',
                      value: formatUsageCount(tokens.outputTokens ?? 0),
                    ),
                    _InlineMetric(
                      label: '推理',
                      value: formatUsageCount(tokens.reasoningTokens ?? 0),
                    ),
                  ],
                ),
                const SizedBox(height: IdeSpacing.space12),
                for (final share in report.modelShares) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          share.model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyles.bodySmall,
                        ),
                      ),
                      Text(
                        '${(share.ratio * 100).toStringAsFixed(1)}% · '
                        '${formatUsageCount(share.totalTokens)}',
                        style: textStyles.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: IdeSpacing.space4),
                  sf.Progress(progress: share.ratio),
                  const SizedBox(height: IdeSpacing.space8),
                ],
                const SizedBox(height: IdeSpacing.space4),
                _UsageLineChart(
                  key: const ValueKey('usage-token-trend-chart'),
                  points: report.tokenTrend,
                  metric: UsageTrendMetric.totalTokens,
                  height: 150,
                ),
              ],
            )
          : Text(
              '当前 Agent 不支持 Token 统计',
              style: textStyles.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
    );
  }
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Text.rich(
      TextSpan(
        text: '$label ',
        style: textStyles.caption.copyWith(color: colors.textSecondary),
        children: [
          TextSpan(
            text: value,
            style: textStyles.bodySmall.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _QuotaSection extends StatelessWidget {
  const _QuotaSection({required this.quota});

  final AgentUsageQuotaSnapshot? quota;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final quota = this.quota;
    return _SectionCard(
      title: '订阅套餐',
      subtitle: 'Codex 返回的实际限额窗口',
      child: quota == null
          ? Text(
              '当前账号未提供套餐信息',
              style: textStyles.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatUsagePlanType(quota.planType),
                        style: textStyles.titleLarge,
                      ),
                    ),
                    if (quota.credits?.unlimited == true)
                      const IdeTab(
                        label: '无限额度',
                        selected: true,
                        trailingIcon: null,
                      ),
                  ],
                ),
                if (quota.limitName case final name?) ...[
                  const SizedBox(height: IdeSpacing.space4),
                  Text(
                    name,
                    style: textStyles.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: IdeSpacing.space12),
                for (final window in quota.windows) ...[
                  _QuotaWindow(window: window),
                  const SizedBox(height: IdeSpacing.space10),
                ],
                if (quota.credits case final credits?)
                  Text(
                    credits.unlimited
                        ? '余额：无限'
                        : credits.balance == null
                        ? '余额状态：${credits.hasCredits ? '可用' : '已用尽'}'
                        : '余额：${credits.balance}',
                    style: textStyles.bodySmall.copyWith(
                      color: credits.hasCredits || credits.unlimited
                          ? colors.success
                          : colors.warning,
                    ),
                  ),
                if (quota.reachedReason != null) ...[
                  const SizedBox(height: IdeSpacing.space8),
                  Text(
                    '额度状态：${quota.reachedReason}',
                    style: textStyles.caption.copyWith(color: colors.warning),
                  ),
                ],
              ],
            ),
    );
  }
}

class _QuotaWindow extends StatelessWidget {
  const _QuotaWindow({required this.window});

  final AgentUsageWindow window;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final remaining = math.max(0, 100 - window.usedPercent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(window.label, style: textStyles.bodySmall)),
            Text(
              '已用 ${window.usedPercent}% · 剩余 $remaining%',
              style: textStyles.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: IdeSpacing.space4),
        sf.Progress(progress: window.usedPercent.toDouble(), min: 0, max: 100),
        const SizedBox(height: IdeSpacing.space4),
        Text(
          window.resetsAt == null
              ? '未提供重置时间'
              : '重置时间：${formatUsageDateTime(window.resetsAt)}',
          style: textStyles.caption.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

class _RecentTasksSection extends StatelessWidget {
  const _RecentTasksSection({
    required this.records,
    required this.onTaskPressed,
  });

  final List<AgentUsageRecord> records;
  final ValueChanged<AgentUsageRecord> onTaskPressed;

  @override
  Widget build(BuildContext context) {
    final visible = records.take(20).toList();
    return _SectionCard(
      title: '最近任务',
      subtitle: '仅展示统计元数据，不展示 Prompt 和文件内容',
      child: _UsageTable(
        minWidth: 780,
        headers: const ['时间', '项目', 'Agent', '模型', '耗时', 'Token', '状态'],
        flexes: const [2, 3, 2, 3, 2, 2, 2],
        rows: [
          for (final record in visible)
            [
              formatUsageDateTime(record.startedAt),
              record.projectName,
              record.providerName,
              record.model ?? '未知模型',
              formatUsageDuration(record.duration, compact: true),
              record.tokens.effectiveTotal == null
                  ? '不支持'
                  : formatUsageCount(record.tokens.effectiveTotal!),
              record.status.label,
            ],
        ],
        rowKeys: [for (final record in visible) record.id],
        onRowPressed: (index) => onTaskPressed(visible[index]),
      ),
    );
  }
}

class _ErrorAnalysisSection extends StatelessWidget {
  const _ErrorAnalysisSection({
    required this.errors,
    required this.records,
    required this.onCategoryPressed,
  });

  final List<UsageErrorBreakdown> errors;
  final List<AgentUsageRecord> records;
  final ValueChanged<UsageErrorCategory> onCategoryPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final failures = records.where((record) => record.status.isFailure).length;
    return _SectionCard(
      title: '失败分析',
      subtitle: '失败次数：$failures',
      child: errors.isEmpty
          ? Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: colors.success,
                ),
                const SizedBox(width: IdeSpacing.space8),
                Text('当前范围内没有失败任务', style: textStyles.bodyMedium),
              ],
            )
          : Wrap(
              spacing: IdeSpacing.space8,
              runSpacing: IdeSpacing.space8,
              children: [
                for (final error in errors)
                  PaneInteractiveSurface(
                    key: ValueKey<String>('usage-error-${error.category.name}'),
                    onPressed: () => onCategoryPressed(error.category),
                    padding: IdeSpacing.cardPadding,
                    borderRadius: IdeRadius.allMedium,
                    borderColor: colors.borderSubtle,
                    semanticLabel: '查看${error.category.label}任务',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: colors.error,
                        ),
                        const SizedBox(width: IdeSpacing.space6),
                        Text(error.category.label, style: textStyles.bodySmall),
                        const SizedBox(width: IdeSpacing.space12),
                        Text(
                          error.count.toString(),
                          style: textStyles.titleSmall.copyWith(
                            color: colors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return PanelCard(
      child: Padding(
        padding: IdeSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final heading = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textStyles.titleLarge),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: textStyles.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                );
                if (trailing == null) {
                  return heading;
                }
                if (constraints.maxWidth < 620) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heading,
                      const SizedBox(height: IdeSpacing.space8),
                      Align(alignment: Alignment.centerLeft, child: trailing),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: IdeSpacing.space12),
                    trailing!,
                  ],
                );
              },
            ),
            const SizedBox(height: IdeSpacing.space12),
            child,
          ],
        ),
      ),
    );
  }
}

class _UsageTable extends StatelessWidget {
  const _UsageTable({
    required this.minWidth,
    required this.headers,
    required this.flexes,
    required this.rows,
    this.rowKeys,
    this.onRowPressed,
  });

  final double minWidth;
  final List<String> headers;
  final List<int> flexes;
  final List<List<String>> rows;
  final List<String>? rowKeys;
  final ValueChanged<int>? onRowPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    if (rows.isEmpty) {
      return Text(
        '暂无数据',
        style: textStyles.bodyMedium.copyWith(color: colors.textSecondary),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = math.max(minWidth, constraints.maxWidth);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: IdeSpacing.space8,
                    vertical: IdeSpacing.space6,
                  ),
                  color: colors.surfaceElevated,
                  child: _UsageTableCells(
                    values: headers,
                    flexes: flexes,
                    header: true,
                  ),
                ),
                for (var index = 0; index < rows.length; index += 1) ...[
                  PaneInteractiveSurface(
                    key: rowKeys == null
                        ? ValueKey<int>(index)
                        : ValueKey<String>('usage-row-${rowKeys![index]}'),
                    onPressed: onRowPressed == null
                        ? null
                        : () => onRowPressed!(index),
                    button: onRowPressed != null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: IdeSpacing.space8,
                      vertical: IdeSpacing.space8,
                    ),
                    borderRadius: BorderRadius.zero,
                    semanticLabel: onRowPressed == null
                        ? null
                        : '打开${rows[index].first}详情',
                    child: _UsageTableCells(
                      values: rows[index],
                      flexes: flexes,
                    ),
                  ),
                  if (index + 1 < rows.length)
                    Divider(height: 1, color: colors.borderSubtle),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UsageTableCells extends StatelessWidget {
  const _UsageTableCells({
    required this.values,
    required this.flexes,
    this.header = false,
  });

  final List<String> values;
  final List<int> flexes;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Row(
      children: [
        for (var index = 0; index < values.length; index += 1)
          Expanded(
            flex: flexes[index],
            child: Padding(
              padding: const EdgeInsets.only(right: IdeSpacing.space8),
              child: Text(
                values[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (header ? textStyles.caption : textStyles.bodySmall)
                    .copyWith(
                      color: header ? colors.textSecondary : colors.textPrimary,
                      fontWeight: header ? FontWeight.w700 : FontWeight.w400,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

class _UsageLineChart extends StatelessWidget {
  const _UsageLineChart({
    required this.points,
    required this.metric,
    this.height = 210,
    super.key,
  });

  final List<UsageTrendPoint> points;
  final UsageTrendMetric metric;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final maximum = safeUsageChartMaximum(points);
    final labels = points.isEmpty
        ? const <String>[]
        : <String>[
            points.first.label,
            if (points.length > 2) points[points.length ~/ 2].label,
            if (points.length > 1) points.last.label,
          ];
    return Semantics(
      label: '${metric.label}趋势，共 ${points.length} 个时间点',
      child: RepaintBoundary(
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              Expanded(
                child: CustomPaint(
                  key: const ValueKey('usage-line-chart-canvas'),
                  painter: _UsageLineChartPainter(
                    points: points,
                    maximum: maximum,
                    lineColor: colors.accent,
                    gridColor: colors.borderSubtle,
                    fillColor: colors.primaryMuted,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: IdeSpacing.space4),
              if (labels.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final label in labels)
                      Text(
                        label,
                        style: textStyles.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageLineChartPainter extends CustomPainter {
  const _UsageLineChartPainter({
    required this.points,
    required this.maximum,
    required this.lineColor,
    required this.gridColor,
    required this.fillColor,
  });

  final List<UsageTrendPoint> points;
  final double maximum;
  final Color lineColor;
  final Color gridColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTWH(
      4,
      8,
      math.max(0, size.width - 8),
      size.height - 12,
    );
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var index = 0; index <= 3; index += 1) {
      final y = chart.top + (chart.height * index / 3);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }
    if (points.isEmpty) {
      return;
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fillPaint = Paint()
      ..color = fillColor.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    final path = Path();
    final fillPath = Path();
    var segmentStarted = false;
    Offset? firstPoint;
    Offset? lastPoint;
    for (var index = 0; index < points.length; index += 1) {
      final value = points[index].value;
      if (value == null) {
        segmentStarted = false;
        continue;
      }
      final x = points.length == 1
          ? chart.center.dx
          : chart.left + (chart.width * index / (points.length - 1));
      final normalized = (value / maximum).clamp(0.0, 1.0);
      final point = Offset(x, chart.bottom - (chart.height * normalized));
      if (!segmentStarted) {
        path.moveTo(point.dx, point.dy);
        firstPoint ??= point;
        segmentStarted = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
      lastPoint = point;
    }
    if (firstPoint != null && lastPoint != null) {
      fillPath
        ..moveTo(firstPoint.dx, chart.bottom)
        ..lineTo(firstPoint.dx, firstPoint.dy)
        ..addPath(path, Offset.zero)
        ..lineTo(lastPoint.dx, chart.bottom)
        ..close();
      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(path, linePaint);
    }
    final pointPaint = Paint()..color = lineColor;
    for (var index = 0; index < points.length; index += 1) {
      final value = points[index].value;
      if (value == null) {
        continue;
      }
      final x = points.length == 1
          ? chart.center.dx
          : chart.left + (chart.width * index / (points.length - 1));
      final y =
          chart.bottom - (chart.height * (value / maximum).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), 2.5, pointPaint);
    }
  }

  @override
  bool shouldRepaint(_UsageLineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.maximum != maximum ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.fillColor != fillColor;
  }
}

class _TaskDetailDrawer extends StatelessWidget {
  const _TaskDetailDrawer({required this.record});

  final AgentUsageRecord record;

  @override
  Widget build(BuildContext context) {
    return _DrawerSurface(
      title: '任务详情',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailRow(label: '项目', value: record.projectName),
          _DetailRow(label: '项目路径', value: record.projectPath),
          _DetailRow(label: 'Agent', value: record.providerName),
          _DetailRow(label: '模型', value: record.model ?? '未知模型'),
          _DetailRow(label: '来源', value: record.sourceKind),
          _DetailRow(
            label: '开始时间',
            value: formatUsageDateTime(record.startedAt),
          ),
          _DetailRow(
            label: '执行时间',
            value: formatUsageDuration(record.duration),
          ),
          _DetailRow(
            label: '首次响应',
            value: formatUsageDuration(record.timeToFirstToken),
          ),
          _DetailRow(
            label: 'Token',
            value: record.tokens.effectiveTotal == null
                ? '当前记录不支持 Token 统计'
                : '${formatUsageCount(record.tokens.effectiveTotal!)} '
                      '（输入 ${formatUsageCount(record.tokens.inputTokens ?? 0)} / '
                      '缓存 ${formatUsageCount(record.tokens.cachedInputTokens ?? 0)} / '
                      '输出 ${formatUsageCount(record.tokens.outputTokens ?? 0)} / '
                      '推理 ${formatUsageCount(record.tokens.reasoningTokens ?? 0)}）',
          ),
          _DetailRow(label: '状态', value: record.status.label),
          if (record.errorCategory case final category?) ...[
            _DetailRow(label: '错误分类', value: category.label),
            _DetailRow(
              label: '原因',
              value: record.errorMessage ?? record.errorCode ?? '未提供详细原因',
            ),
            _DetailRow(label: '下一步', value: category.nextAction),
          ],
        ],
      ),
    );
  }
}

class _ErrorListDrawer extends StatelessWidget {
  const _ErrorListDrawer({
    required this.category,
    required this.records,
    required this.onTaskPressed,
  });

  final UsageErrorCategory category;
  final List<AgentUsageRecord> records;
  final ValueChanged<AgentUsageRecord> onTaskPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return _DrawerSurface(
      title: category.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeStatusCard(
            tone: IdeStatusCardTone.info,
            title: '建议操作',
            body: Text(category.nextAction),
            margin: EdgeInsets.zero,
          ),
          const SizedBox(height: IdeSpacing.space12),
          Text('${records.length} 条任务', style: textStyles.titleSmall),
          const SizedBox(height: IdeSpacing.space8),
          for (final record in records) ...[
            PaneInteractiveSurface(
              key: ValueKey<String>('usage-error-task-${record.id}'),
              onPressed: () => onTaskPressed(record),
              padding: IdeSpacing.cardPadding,
              borderRadius: IdeRadius.allMedium,
              borderColor: colors.borderSubtle,
              alignment: Alignment.centerLeft,
              semanticLabel: '打开 ${record.projectName} 失败任务',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.projectName, style: textStyles.bodySmall),
                  Text(
                    record.errorMessage ?? record.errorCode ?? '未提供详细原因',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: IdeSpacing.space8),
          ],
        ],
      ),
    );
  }
}

class _DrawerSurface extends StatelessWidget {
  const _DrawerSurface({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
      child: ColoredBox(
        color: colors.surfaceOverlay,
        child: Padding(
          padding: IdeSpacing.all16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: textStyles.displaySmall)),
                  sf.IconButton.ghost(
                    key: const ValueKey('usage-drawer-close-button'),
                    onPressed: () => sf.closeOverlay(context),
                    density: sf.ButtonDensity.iconDense,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: IdeSpacing.space12),
              Expanded(child: SingleChildScrollView(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: IdeSpacing.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textStyles.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: IdeSpacing.space2),
          SelectableText(value, style: textStyles.bodyMedium),
        ],
      ),
    );
  }
}

class _EmptyUsageState extends StatelessWidget {
  const _EmptyUsageState({required this.onOpenAgentManagement});

  final VoidCallback onOpenAgentManagement;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return PanelCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IdeSpacing.space24,
          vertical: 40,
        ),
        child: Column(
          children: [
            Icon(
              Icons.query_stats_rounded,
              size: 36,
              color: colors.textTertiary,
            ),
            const SizedBox(height: IdeSpacing.space12),
            Text('暂无使用记录', style: textStyles.displaySmall),
            const SizedBox(height: IdeSpacing.space6),
            Text(
              '开始使用 Agent 后，这里会展示调用次数、性能和资源消耗。',
              textAlign: TextAlign.center,
              style: textStyles.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: IdeSpacing.space16),
            sf.PrimaryButton(
              key: const ValueKey('usage-open-agent-management-button'),
              onPressed: onOpenAgentManagement,
              size: sf.ButtonSize.small,
              child: const Text('打开 Agent 管理'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const SizedBox(width: 220, child: sf.Progress(progress: null)),
          const SizedBox(height: IdeSpacing.space12),
          Text(
            '正在索引 Codex 使用记录…',
            style: textStyles.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
