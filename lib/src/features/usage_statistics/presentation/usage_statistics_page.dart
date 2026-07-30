import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_controller.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_report_builder.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_formatters.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_status_card.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/metrics/compact_metric_bar.dart';
import 'package:zeta/src/ui/core/rows/ide_data_row.dart';
import 'package:zeta/src/ui/core/rows/ide_list_row.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';
import 'package:zeta/src/ui/core/workbench/ide_page_header.dart';
import 'package:zeta/src/ui/core/workbench/ide_section.dart';
import 'package:zeta/src/ui/core/workbench/ide_toolbar.dart';

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
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return IdeSurface.canvas(
      key: const ValueKey('usage-statistics-page'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdePageHeader(
            title: '使用统计',
            subtitle: '分析调用、性能、Token、项目与套餐额度',
            leading: sf.IconButton.ghost(
              key: const ValueKey('usage-statistics-back-button'),
              onPressed: widget.onBackPressed,
              size: sf.ButtonSize.small,
              density: sf.ButtonDensity.iconDense,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
            ),
          ),
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
        final wide = constraints.maxWidth >= IdeMetrics.wideBreakpoint;
        final medium = constraints.maxWidth >= IdeMetrics.mediumBreakpoint;
        final pagePadding = medium
            ? IdeSpacing.pagePadding
            : IdeSpacing.pagePaddingCompact;
        return ListView(
          key: const ValueKey('usage-statistics-scroll-view'),
          padding: EdgeInsets.zero,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: math.min(
                  constraints.maxWidth,
                  IdeMetrics.analyticsContentMaxWidth,
                ),
                child: Padding(
                  padding: pagePadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        _UsageOverviewBar(overview: report.overview),
                        const SizedBox(height: IdeSpacing.space12),
                        _TrendSection(controller: controller, report: report),
                        const SizedBox(height: IdeSpacing.space16),
                        if (report.records.isEmpty)
                          _EmptyUsageState(
                            onOpenAgentManagement: widget.onOpenAgentManagement,
                          )
                        else ...[
                          _ResponsivePair(
                            debugLabel: 'usage-ranking-layout',
                            layout: wide
                                ? _UsagePairLayout.equal
                                : _UsagePairLayout.stacked,
                            left: _AgentRankingSection(
                              controller: controller,
                              entries: report.agentRanking,
                            ),
                            right: _ProjectRankingSection(
                              entries: report.projectRanking,
                              onProjectSelected: controller.selectProject,
                            ),
                          ),
                          const SizedBox(height: IdeSpacing.space16),
                          _ResponsivePair(
                            debugLabel: 'usage-resource-layout',
                            layout: wide
                                ? _UsagePairLayout.equal
                                : medium
                                ? _UsagePairLayout.sixtyForty
                                : _UsagePairLayout.stacked,
                            left: _TokenAnalysisSection(report: report),
                            right: _QuotaSection(
                              quota: controller.source?.quota,
                            ),
                          ),
                          const SizedBox(height: IdeSpacing.space16),
                          _RecentTasksSection(
                            records: report.records,
                            onTaskPressed: (record) =>
                                _openTaskDrawer(context, record),
                          ),
                          const SizedBox(height: IdeSpacing.space16),
                          _ErrorAnalysisSection(
                            errors: report.errors,
                            records: report.records,
                            onCategoryPressed: (category) {
                              _openErrorDrawer(
                                context,
                                category,
                                report.records,
                              );
                            },
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
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
    return IdeToolbar(
      key: const ValueKey('usage-filters-toolbar'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < IdeMetrics.mediumBreakpoint;
          final singleColumn = constraints.maxWidth < 440;
          final fieldWidth = singleColumn
              ? constraints.maxWidth
              : compact
              ? math.max(0.0, (constraints.maxWidth - IdeSpacing.space8) / 2)
              : 190.0;
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
                        for (final model in models) _SelectOption(model, model),
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
                        if (compact)
                          Expanded(
                            child: Text(
                              '最后更新：${formatUsageClock(controller.lastUpdated)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: textStyles.caption.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          )
                        else
                          Text(
                            '最后更新：${formatUsageClock(controller.lastUpdated)}',
                            style: textStyles.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        const SizedBox(width: IdeSpacing.space8),
                        SizedBox(
                          height: IdeMetrics.toolbarHeight,
                          child: sf.OutlineButton(
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
                    height: IdeMetrics.toolbarHeight,
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
      constraints: BoxConstraints.tightFor(
        width: width,
        height: IdeMetrics.toolbarHeight,
      ),
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

class _UsageOverviewBar extends StatelessWidget {
  const _UsageOverviewBar({required this.overview});

  final UsageOverview overview;

  @override
  Widget build(BuildContext context) {
    final comparison = overview.callComparison;
    final comparisonText = comparison.changePercent == null
        ? comparison.current > 0
              ? '上一周期无调用'
              : '与上一周期持平'
        : '${comparison.changePercent! >= 0 ? '↑' : '↓'} '
              '${comparison.changePercent!.abs().toStringAsFixed(1)}% · 相比上一周期';
    return CompactMetricBar(
      items: [
        CompactMetricItem(
          label: '调用次数',
          value: formatUsageCount(overview.totalCalls),
          detail: comparisonText,
          icon: Icons.bolt_rounded,
        ),
        CompactMetricItem(
          label: '成功率',
          value: formatUsagePercent(overview.successRate),
          detail: '失败：${overview.failedCalls} 次',
          icon: Icons.check_circle_outline_rounded,
        ),
        CompactMetricItem(
          label: '平均响应时间',
          value: formatUsageDuration(overview.averageResponse),
          detail: overview.responseSampleCount == 0
              ? '暂无可靠 TTFT 样本'
              : '有效样本：${overview.responseSampleCount}',
          icon: Icons.speed_rounded,
        ),
        CompactMetricItem(
          label: '平均任务耗时',
          value: formatUsageDuration(overview.averageDuration),
          detail: '按 Codex turn 统计',
          icon: Icons.timer_outlined,
        ),
        CompactMetricItem(
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
  }
}

class _TrendSection extends StatelessWidget {
  const _TrendSection({required this.controller, required this.report});

  final UsageStatisticsController controller;
  final UsageStatisticsReport report;

  @override
  Widget build(BuildContext context) {
    return IdeSurface.pane(
      key: const ValueKey('usage-primary-trend-pane'),
      padding: IdeSpacing.panelPadding,
      child: IdeSection(
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
      ),
    );
  }
}

enum _UsagePairLayout { stacked, equal, sixtyForty }

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({
    required this.debugLabel,
    required this.layout,
    required this.left,
    required this.right,
  });

  final String debugLabel;
  final _UsagePairLayout layout;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (layout == _UsagePairLayout.stacked) {
      return Column(
        key: ValueKey<String>('$debugLabel-stacked'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          left,
          const SizedBox(height: IdeSpacing.space12),
          right,
        ],
      );
    }
    final leftFlex = layout == _UsagePairLayout.sixtyForty ? 3 : 1;
    final rightFlex = layout == _UsagePairLayout.sixtyForty ? 2 : 1;
    return Row(
      key: ValueKey<String>(
        '$debugLabel-${layout == _UsagePairLayout.equal ? 'equal' : 'sixty-forty'}',
      ),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: leftFlex, child: left),
        const SizedBox(width: IdeSpacing.space12),
        Expanded(flex: rightFlex, child: right),
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
    return IdeSection(
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
    return IdeSection(
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
    return IdeSection(
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
    return IdeSection(
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
    return IdeSection(
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
    return IdeSection(
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
          : Column(
              children: [
                for (var index = 0; index < errors.length; index += 1)
                  IdeListRow(
                    key: ValueKey<String>(
                      'usage-error-${errors[index].category.name}',
                    ),
                    title: errors[index].category.label,
                    subtitle: errors[index].category.nextAction,
                    leading: Icon(Icons.error_outline, color: colors.error),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          errors[index].count.toString(),
                          style: textStyles.titleSmall.copyWith(
                            color: colors.error,
                          ),
                        ),
                        const SizedBox(width: IdeSpacing.space4),
                        const Icon(Icons.chevron_right_rounded, size: 16),
                      ],
                    ),
                    onPressed: () => onCategoryPressed(errors[index].category),
                    showDivider: index < errors.length - 1,
                    semanticLabel: '查看${errors[index].category.label}任务',
                  ),
              ],
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
        return ClipRect(
          child: SingleChildScrollView(
            key: const ValueKey('usage-table-horizontal-scroll'),
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  IdeDataRow(values: headers, flexes: flexes, header: true),
                  for (var index = 0; index < rows.length; index += 1)
                    IdeDataRow(
                      key: _rowKey(index),
                      values: rows[index],
                      flexes: flexes,
                      onPressed: onRowPressed == null
                          ? null
                          : () => onRowPressed!(index),
                      showDivider: index + 1 < rows.length,
                      semanticLabel: onRowPressed == null
                          ? null
                          : '打开${rows[index].first}详情',
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Key _rowKey(int index) {
    final keys = rowKeys;
    if (keys == null) {
      return ValueKey<int>(index);
    }
    final base = keys[index];
    var occurrence = 1;
    for (var previous = 0; previous < index; previous += 1) {
      if (keys[previous] == base) {
        occurrence += 1;
      }
    }
    final suffix = occurrence == 1 ? '' : '#$occurrence';
    return ValueKey<String>('usage-row-$base$suffix');
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
    final brightness = sf.Theme.of(context).brightness;
    final fillColor = colors.accent.withValues(
      alpha: brightness == Brightness.dark ? 0.10 : 0.07,
    );
    final maximum = safeUsageChartMaximum(points);
    final hasValues = points.any((point) => point.value != null);
    final spots = <FlSpot>[
      for (var index = 0; index < points.length; index += 1)
        if (points[index].value case final value?)
          FlSpot(index.toDouble(), value)
        else
          FlSpot.nullSpot,
    ];
    final labelIndices = <int>{
      if (points.isNotEmpty) 0,
      if (points.length > 2) points.length ~/ 2,
      if (points.length > 1) points.length - 1,
    };
    final maxX = points.length <= 1 ? 1.0 : (points.length - 1).toDouble();
    final titleStyle = textStyles.caption.copyWith(color: colors.textTertiary);

    return Semantics(
      label: '${metric.label}趋势，共 ${points.length} 个时间点',
      child: RepaintBoundary(
        child: SizedBox(
          height: height,
          child: LineChart(
            key: const ValueKey('usage-line-chart-canvas'),
            LineChartData(
              minX: 0,
              maxX: maxX,
              minY: 0,
              maxY: maximum,
              clipData: const FlClipData.all(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maximum / 3,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: colors.borderSubtle, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: points.isNotEmpty,
                    reservedSize: 22,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if ((value - index).abs() > 0.001 ||
                          !labelIndices.contains(index) ||
                          index < 0 ||
                          index >= points.length) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 4,
                        child: Text(points[index].label, style: titleStyle),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                enabled: hasValues,
                handleBuiltInTouches: true,
                getTouchedSpotIndicator: (barData, spotIndexes) {
                  return [
                    for (final _ in spotIndexes)
                      TouchedSpotIndicatorData(
                        FlLine(
                          color: colors.accent.withValues(alpha: 0.35),
                          strokeWidth: 1,
                        ),
                        FlDotData(
                          getDotPainter: (spot, percent, bar, index) {
                            return FlDotCirclePainter(
                              radius: 3.5,
                              color: colors.accent,
                              strokeWidth: 0,
                            );
                          },
                        ),
                      ),
                  ];
                },
                touchTooltipData: LineTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  tooltipBorderRadius: IdeRadius.allSmall,
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: IdeSpacing.space8,
                    vertical: IdeSpacing.space4,
                  ),
                  getTooltipColor: (_) => colors.surfaceOverlay,
                  getTooltipItems: (touchedSpots) {
                    return [
                      for (final touched in touchedSpots)
                        LineTooltipItem(
                          _formatTrendTooltip(
                            metric: metric,
                            label: points[touched.x.toInt()].label,
                            value: touched.y,
                          ),
                          textStyles.caption.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ];
                  },
                ),
              ),
              lineBarsData: [
                if (hasValues)
                  LineChartBarData(
                    spots: spots,
                    color: colors.accent,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    isStrokeJoinRound: true,
                    preventCurveOverShooting: true,
                    dotData: FlDotData(
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 2.5,
                          color: colors.accent,
                          strokeWidth: 0,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(show: true, color: fillColor),
                  ),
              ],
            ),
            duration: Duration.zero,
          ),
        ),
      ),
    );
  }
}

/// 将趋势点格式化为悬浮提示文案。
String _formatTrendTooltip({
  required UsageTrendMetric metric,
  required String label,
  required double value,
}) {
  final formatted = switch (metric) {
    UsageTrendMetric.calls ||
    UsageTrendMetric.totalTokens => formatUsageCount(value),
    UsageTrendMetric.successRate => formatUsagePercent(value),
    UsageTrendMetric.averageResponse || UsageTrendMetric.averageDuration =>
      formatUsageDuration(Duration(milliseconds: value.round()), compact: true),
  };
  return '$label · $formatted';
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
          _DetailRow(label: '来源', value: _sourceKindLabel(record.sourceKind)),
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
          for (var index = 0; index < records.length; index += 1)
            IdeListRow(
              key: ValueKey<String>('usage-error-task-${records[index].id}'),
              title: records[index].projectName,
              subtitle:
                  records[index].errorMessage ??
                  records[index].errorCode ??
                  '未提供详细原因',
              trailing: const Icon(Icons.chevron_right_rounded, size: 16),
              onPressed: () => onTaskPressed(records[index]),
              showDivider: index < records.length - 1,
              semanticLabel: '打开 ${records[index].projectName} 失败任务',
            ),
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
      child: IdeSurface.popover(
        key: const ValueKey('usage-drawer-surface'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IdePageHeader(
              title: title,
              actions: [
                sf.IconButton.ghost(
                  key: const ValueKey('usage-drawer-close-button'),
                  onPressed: () => sf.closeOverlay(context),
                  density: sf.ButtonDensity.iconDense,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: IdeSpacing.all16,
                child: SingleChildScrollView(child: child),
              ),
            ),
          ],
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

String _sourceKindLabel(String sourceKind) {
  return switch (sourceKind) {
    'cli' => '本地记录',
    'appServer' => 'App Server',
    _ => sourceKind,
  };
}

class _EmptyUsageState extends StatelessWidget {
  const _EmptyUsageState({required this.onOpenAgentManagement});

  final VoidCallback onOpenAgentManagement;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return IdeSurface.pane(
      key: const ValueKey('usage-empty-state-pane'),
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
