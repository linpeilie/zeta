import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/usage_statistics/application/usage_statistics_controller.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_report_builder.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_formatters.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_time_range_filter.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_status_card.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/rows/ide_data_row.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';
import 'package:zeta/src/ui/core/workbench/ide_page_header.dart';
import 'package:zeta/src/ui/core/workbench/ide_section.dart';

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
                        _TrendSection(report: report),
                        const SizedBox(height: IdeSpacing.space16),
                        if (report.records.isEmpty)
                          _EmptyUsageState(
                            onOpenAgentManagement: widget.onOpenAgentManagement,
                          )
                        else
                          _UsageDetailTabs(
                            controller: controller,
                            report: report,
                            onTaskPressed: (record) =>
                                _openTaskDrawer(context, record),
                            onProjectSelected: controller.selectProject,
                          ),
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
    final agents = report?.agentOptions ?? const <String>[];
    final models = report?.modelOptions ?? const <String>[];
    // 与页面内其它内容卡片一致使用 pane 表面，避免 IdeToolbar 的
    // surfaceElevated 在 canvas 上形成突兀的抬升色带。
    return IdeSurface.pane(
      key: const ValueKey('usage-filters-toolbar'),
      padding: IdeSpacing.panelPadding,
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
                    child: UsageTimeRangeFilter(
                      controller: controller,
                      width: fieldWidth,
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
    final colors = IdeColors.of(context);
    final tokenCard = _OverviewMetricCard(
      key: const ValueKey('usage-overview-tokens'),
      label: 'Token 使用量',
      value: overview.tokens.hasData
          ? formatUsageCount(overview.tokens.effectiveTotal ?? 0)
          : '—',
      detail: overview.tokens.hasData
          ? '输入 ${formatUsageCount(overview.tokens.inputTokens ?? 0)} · '
                '输出 ${formatUsageCount(overview.tokens.outputTokens ?? 0)} · '
                '推理 ${formatUsageCount(overview.tokens.reasoningTokens ?? 0)}'
          : '当前筛选下暂无 Token 统计',
      icon: Icons.data_usage_rounded,
      accent: colors.intelligenceAccent,
      semanticLabel:
          'Token 使用量 ${overview.tokens.hasData ? formatUsageCount(overview.tokens.effectiveTotal ?? 0) : '暂无数据'}',
    );
    final callsCard = _OverviewMetricCard(
      key: const ValueKey('usage-overview-calls'),
      label: '调用次数',
      value: formatUsageCount(overview.totalCalls),
      icon: Icons.bolt_rounded,
      accent: colors.accent,
      semanticLabel: '调用次数 ${formatUsageCount(overview.totalCalls)}',
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < IdeMetrics.stackedRowBreakpoint;
        if (stacked) {
          return Column(
            key: const ValueKey('usage-overview-layout-stacked'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tokenCard,
              const SizedBox(height: IdeSpacing.space8),
              callsCard,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            key: const ValueKey('usage-overview-layout-equal'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tokenCard),
              const SizedBox(width: IdeSpacing.space8),
              Expanded(child: callsCard),
            ],
          ),
        );
      },
    );
  }
}

/// 概况区双指标卡片：大号数值 + 图标徽章 + 可选次级说明。
class _OverviewMetricCard extends StatelessWidget {
  const _OverviewMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.semanticLabel,
    this.detail,
    super.key,
  });

  final String label;
  final String value;
  final String? detail;
  final IconData icon;
  final Color accent;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    // 与 Token 卡片一致：始终预留最多 2 行 meta 高度，避免无 detail 时变矮。
    final detailStyle = textStyles.meta.copyWith(color: colors.textSecondary);
    final detailLineHeight =
        (detailStyle.fontSize ?? 10) * (detailStyle.height ?? 1.2);
    final detailSlotHeight = detailLineHeight;

    return Semantics(
      label: semanticLabel,
      child: IdeSurface.pane(
        padding: IdeSpacing.panelPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: IdeRadius.allMedium,
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: IdeSpacing.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.toolbarLabel.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: IdeSpacing.space4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.metricValue.copyWith(color: accent),
                  ),
                  const SizedBox(height: IdeSpacing.space6),
                  SizedBox(
                    height: detailSlotHeight,
                    width: double.infinity,
                    child: detail == null
                        ? null
                        : Text(
                            detail!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: detailStyle,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendSection extends StatelessWidget {
  const _TrendSection({required this.report});

  final UsageStatisticsReport report;

  @override
  Widget build(BuildContext context) {
    return IdeSurface.pane(
      key: const ValueKey('usage-primary-trend-pane'),
      padding: IdeSpacing.panelPadding,
      child: IdeSection(
        title: '使用趋势',
        subtitle: 'Token 消耗 · 粒度根据时间范围自动调整',
        child: _UsageLineChart(
          key: const ValueKey('usage-main-chart-totalTokens'),
          points: report.tokenTrend,
          metric: UsageTrendMetric.totalTokens,
        ),
      ),
    );
  }
}

/// 趋势图下方详情区 Tab。
enum _UsageDetailTab { agents, models, projects, tasks }

/// 趋势图下方四栏：Agent / 模型 / 项目 / 任务。
class _UsageDetailTabs extends StatefulWidget {
  const _UsageDetailTabs({
    required this.controller,
    required this.report,
    required this.onTaskPressed,
    required this.onProjectSelected,
  });

  final UsageStatisticsController controller;
  final UsageStatisticsReport report;
  final ValueChanged<AgentUsageRecord> onTaskPressed;
  final ValueChanged<String?> onProjectSelected;

  @override
  State<_UsageDetailTabs> createState() => _UsageDetailTabsState();
}

class _UsageDetailTabsState extends State<_UsageDetailTabs> {
  static const int _taskPageSize = 20;

  _UsageDetailTab _tab = _UsageDetailTab.agents;
  int _taskPage = 1;

  @override
  void didUpdateWidget(covariant _UsageDetailTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final totalPages = _taskTotalPages(widget.report.records.length);
    if (_taskPage > totalPages) {
      _taskPage = totalPages;
    }
  }

  int _taskTotalPages(int recordCount) {
    if (recordCount <= 0) {
      return 1;
    }
    return ((recordCount + _taskPageSize - 1) / _taskPageSize).floor();
  }

  @override
  Widget build(BuildContext context) {
    return IdeSurface.pane(
      key: const ValueKey('usage-detail-tabs'),
      padding: IdeSpacing.panelPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeTabs<_UsageDetailTab>(
            key: const ValueKey('usage-detail-tab-bar'),
            value: _tab,
            semanticLabel: '使用统计详情分类',
            items: const [
              IdeTabItem(
                key: ValueKey('usage-detail-tab-agents'),
                value: _UsageDetailTab.agents,
                label: 'Agent 统计',
              ),
              IdeTabItem(
                key: ValueKey('usage-detail-tab-models'),
                value: _UsageDetailTab.models,
                label: '模型统计',
              ),
              IdeTabItem(
                key: ValueKey('usage-detail-tab-projects'),
                value: _UsageDetailTab.projects,
                label: '项目列表',
              ),
              IdeTabItem(
                key: ValueKey('usage-detail-tab-tasks'),
                value: _UsageDetailTab.tasks,
                label: '任务列表',
              ),
            ],
            onChanged: (value) {
              setState(() {
                _tab = value;
              });
            },
          ),
          const SizedBox(height: IdeSpacing.space12),
          switch (_tab) {
            _UsageDetailTab.agents => _AgentStatsPanel(
              controller: widget.controller,
              entries: widget.report.agentRanking,
            ),
            _UsageDetailTab.models => _ModelStatsPanel(report: widget.report),
            _UsageDetailTab.projects => _ProjectListPanel(
              entries: widget.report.projectRanking,
              onProjectSelected: widget.onProjectSelected,
            ),
            _UsageDetailTab.tasks => _TaskListPanel(
              records: widget.report.records,
              page: _taskPage,
              pageSize: _taskPageSize,
              onPageChanged: (page) {
                setState(() {
                  _taskPage = page;
                });
              },
              onTaskPressed: widget.onTaskPressed,
            ),
          },
        ],
      ),
    );
  }
}

class _AgentStatsPanel extends StatelessWidget {
  const _AgentStatsPanel({required this.controller, required this.entries});

  final UsageStatisticsController controller;
  final List<UsageAgentRankEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Column(
      key: const ValueKey('usage-panel-agents'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '按当前筛选范围汇总',
                style: textStyles.meta.copyWith(color: colors.textSecondary),
              ),
            ),
            _UsageFilters._select<UsageRankSort>(
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
          ],
        ),
        const SizedBox(height: IdeSpacing.space8),
        _UsageTable(
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
      ],
    );
  }
}

class _ModelStatsPanel extends StatelessWidget {
  const _ModelStatsPanel({required this.report});

  final UsageStatisticsReport report;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final tokens = report.overview.tokens;
    return Column(
      key: const ValueKey('usage-panel-models'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '模型 Token 消耗与占比',
          style: textStyles.meta.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: IdeSpacing.space8),
        if (!tokens.hasData && report.modelShares.isEmpty)
          Text(
            '当前筛选下暂无模型统计',
            style: textStyles.bodyMedium.copyWith(color: colors.textSecondary),
          )
        else ...[
          if (tokens.hasData) ...[
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
          ],
          _UsageTable(
            minWidth: 520,
            headers: const ['模型', 'Token', '占比'],
            flexes: const [4, 2, 2],
            rows: [
              for (final share in report.modelShares)
                [
                  share.model,
                  formatUsageCount(share.totalTokens),
                  '${(share.ratio * 100).toStringAsFixed(1)}%',
                ],
            ],
            rowKeys: [for (final share in report.modelShares) share.model],
          ),
        ],
      ],
    );
  }
}

class _ProjectListPanel extends StatelessWidget {
  const _ProjectListPanel({
    required this.entries,
    required this.onProjectSelected,
  });

  final List<UsageProjectRankEntry> entries;
  final ValueChanged<String?> onProjectSelected;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Column(
      key: const ValueKey('usage-panel-projects'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '按当前筛选范围汇总 · 点击项目可聚焦该项目',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textStyles.meta.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: IdeSpacing.space8),
        _UsageTable(
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
          onRowPressed: (index) =>
              onProjectSelected(entries[index].projectPath),
        ),
      ],
    );
  }
}

class _TaskListPanel extends StatelessWidget {
  const _TaskListPanel({
    required this.records,
    required this.page,
    required this.pageSize,
    required this.onPageChanged,
    required this.onTaskPressed,
  });

  final List<AgentUsageRecord> records;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<AgentUsageRecord> onTaskPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final totalPages = records.isEmpty
        ? 1
        : ((records.length + pageSize - 1) / pageSize).floor();
    final safePage = page.clamp(1, totalPages);
    final start = (safePage - 1) * pageSize;
    final visible = records.skip(start).take(pageSize).toList();

    return Column(
      key: const ValueKey('usage-panel-tasks'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '共 ${records.length} 条 · 每页 $pageSize 条 · 仅展示统计元数据',
          style: textStyles.meta.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: IdeSpacing.space8),
        _UsageTable(
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
        if (records.length > pageSize) ...[
          const SizedBox(height: IdeSpacing.space12),
          Align(
            alignment: Alignment.centerRight,
            child: sf.Pagination(
              key: const ValueKey('usage-task-pagination'),
              page: safePage,
              totalPages: totalPages,
              maxPages: 5,
              onPageChanged: onPageChanged,
              hidePreviousOnFirstPage: true,
              hideNextOnLastPage: true,
            ),
          ),
        ],
      ],
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
    super.key,
  });

  final List<UsageTrendPoint> points;
  final UsageTrendMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final brightness = sf.Theme.of(context).brightness;
    final fillColor = colors.accent.withValues(
      alpha: brightness == Brightness.dark ? 0.10 : 0.07,
    );
    final maximum = safeUsageChartMaximum(points);
    final yInterval = maximum / 3;
    // 折线与圆点有实际宽度，数据点不能贴在裁剪边界上，否则首尾、零值和最大值
    // 只能绘制一部分。单点数据居中，多点数据按横轴跨度保留稳定比例的安全区。
    final lastPointX = points.isEmpty ? 0.0 : (points.length - 1).toDouble();
    final horizontalPadding = switch (points.length) {
      0 => 0.0,
      1 => 0.5,
      _ => math.max(0.05, lastPointX * 0.02),
    };
    final chartMinX = points.isEmpty ? 0.0 : -horizontalPadding;
    final chartMaxX = points.isEmpty ? 1.0 : lastPointX + horizontalPadding;
    final verticalPadding = maximum * 0.06;
    // 缺失日期统一按 0 绘制，保证时间轴连续、无断点。
    final spots = <FlSpot>[
      for (var index = 0; index < points.length; index += 1)
        FlSpot(index.toDouble(), points[index].value ?? 0),
    ];
    final hasValues = points.isNotEmpty;
    final labelIndices = <int>{
      if (points.isNotEmpty) 0,
      if (points.length > 2) points.length ~/ 2,
      if (points.length > 1) points.length - 1,
    };
    final titleStyle = textStyles.caption.copyWith(color: colors.textTertiary);

    return Semantics(
      label: '${metric.label}趋势，共 ${points.length} 个时间点',
      child: RepaintBoundary(
        child: SizedBox(
          height: 210,
          child: LineChart(
            key: const ValueKey('usage-line-chart-canvas'),
            LineChartData(
              minX: chartMinX,
              maxX: chartMaxX,
              minY: -verticalPadding,
              maxY: maximum + verticalPadding,
              clipData: const FlClipData.all(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: yInterval,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: colors.borderSubtle, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: yInterval,
                    getTitlesWidget: (value, meta) {
                      // 与水平网格对齐：0、1/3、2/3、max。
                      final step = (value / yInterval).round();
                      if ((value - step * yInterval).abs() > yInterval * 0.01) {
                        return const SizedBox.shrink();
                      }
                      if (step < 0 || step > 3) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        child: Text(
                          _formatTrendAxisValue(metric: metric, value: value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: titleStyle,
                        ),
                      );
                    },
                  ),
                ),
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
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
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
                    belowBarData: BarAreaData(
                      show: true,
                      color: fillColor,
                      cutOffY: 0,
                      applyCutOffY: true,
                    ),
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
  return '$label · ${_formatTrendAxisValue(metric: metric, value: value)}';
}

/// Y 轴与 Tooltip 共用的趋势数值格式化。
String _formatTrendAxisValue({
  required UsageTrendMetric metric,
  required double value,
}) {
  return switch (metric) {
    UsageTrendMetric.calls ||
    UsageTrendMetric.totalTokens => formatUsageCount(value),
    UsageTrendMetric.successRate => formatUsagePercent(value),
    UsageTrendMetric.averageResponse || UsageTrendMetric.averageDuration =>
      formatUsageDuration(Duration(milliseconds: value.round()), compact: true),
  };
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
