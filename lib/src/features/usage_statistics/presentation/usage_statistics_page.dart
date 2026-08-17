import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/usage_statistics/application/usage_statistics_controller.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_report_builder.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_formatters.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_l10n.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_time_range_filter.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';
import 'package:zeta/src/ui/core/ide_button.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_select.dart';
import 'package:zeta/src/ui/core/ide_skeleton.dart';
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
    required this.onOpenAgentManagement,
    super.key,
  });

  final UsageStatisticsController controller;
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
            title: context.l10n.usagePageTitle,
            subtitle: context.l10n.usagePageSubtitle,
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
                      // 冷加载用 Skeleton 占位；有旧数据时的刷新保留内容，不再插顶栏进度条。
                      if (controller.errorMessage case final error?)
                        IdeStatusCard(
                          tone: IdeStatusCardTone.error,
                          title: context.l10n.usageLoadFailedTitle,
                          body: Text(error),
                          footer: Align(
                            alignment: Alignment.centerLeft,
                            child: IdeButton(
                              onPressed: controller.refresh,
                              label: context.l10n.usageReload,
                            ),
                          ),
                        ),
                      for (final warning in controller.warnings)
                        IdeStatusCard(
                          tone: IdeStatusCardTone.warning,
                          title: context.l10n.usagePartialUnavailable,
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
    sf.showOverlay<void>(
      context,
      sf.DrawerConfiguration(
        expands: narrow,
        position: narrow ? sf.OverlayPosition.bottom : sf.OverlayPosition.end,
        builder: (drawerContext) => _TaskDetailDrawer(record: record),
      ),
      adaptive: false,
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
                    label: context.l10n.usageTimeRangeLabel,
                    width: fieldWidth,
                    child: UsageTimeRangeFilter(
                      controller: controller,
                      width: fieldWidth,
                    ),
                  ),
                  _LabeledFilter(
                    label: 'Agent',
                    width: fieldWidth,
                    child: IdeSelect<String>(
                      key: const ValueKey('usage-agent-filter'),
                      width: fieldWidth,
                      value: controller.providerId ?? _all,
                      options: <IdeSelectOption<String>>[
                        IdeSelectOption(_all, context.l10n.usageAllAgents),
                        for (final agent in agents)
                          IdeSelectOption(agent, _providerName(report, agent)),
                      ],
                      onChanged: (value) => controller.selectProvider(
                        value == null || value == _all ? null : value,
                      ),
                    ),
                  ),
                  _LabeledFilter(
                    label: context.l10n.usageModelLabel,
                    width: fieldWidth,
                    child: IdeSelect<String>(
                      key: const ValueKey('usage-model-filter'),
                      width: fieldWidth,
                      value: controller.model ?? _all,
                      options: <IdeSelectOption<String>>[
                        IdeSelectOption(_all, context.l10n.usageAllModels),
                        for (final model in models)
                          IdeSelectOption(model, model),
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
                              context.l10n.usageLastUpdated(
                                formatUsageClock(controller.lastUpdated),
                              ),
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
                            context.l10n.usageLastUpdated(
                              formatUsageClock(controller.lastUpdated),
                            ),
                            style: textStyles.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        const SizedBox(width: IdeSpacing.space8),
                        IdeButton.toolbar(
                          key: const ValueKey('usage-refresh-button'),
                          label: context.l10n.usageRefresh,
                          leadingIcon: Icons.refresh_rounded,
                          onPressed: controller.loading
                              ? null
                              : controller.refresh,
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
    final l10n = context.l10n;
    final tokenCard = _OverviewMetricCard(
      key: const ValueKey('usage-overview-tokens'),
      label: l10n.usageTokenUsageLabel,
      value: overview.tokens.hasData
          ? formatUsageCount(overview.tokens.effectiveTotal ?? 0)
          : '—',
      detail: overview.tokens.hasData
          ? l10n.usageTokenBreakdownLine(
              formatUsageCount(overview.tokens.inputTokens ?? 0),
              formatUsageCount(overview.tokens.outputTokens ?? 0),
              formatUsageCount(overview.tokens.reasoningTokens ?? 0),
            )
          : l10n.usageNoTokenStats,
      icon: Icons.data_usage_rounded,
      semanticLabel: l10n.usageTokenUsageAmount(
        overview.tokens.hasData
            ? formatUsageCount(overview.tokens.effectiveTotal ?? 0)
            : formatUsagePercent(null, empty: l10n.usageNoData),
      ),
    );
    final callsCard = _OverviewMetricCard(
      key: const ValueKey('usage-overview-calls'),
      label: l10n.usageCallCount,
      value: formatUsageCount(overview.totalCalls),
      icon: Icons.bolt_rounded,
      semanticLabel: l10n.usageCallCountSemantic(
        formatUsageCount(overview.totalCalls),
      ),
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

/// 概况区双指标卡片：中性小图标 + 大号数值 + 可选次级说明。
class _OverviewMetricCard extends StatelessWidget {
  const _OverviewMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.semanticLabel,
    this.detail,
    super.key,
  });

  final String label;
  final String value;
  final String? detail;
  final IconData icon;
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
            // 图标不带彩色底：36×36 的着色方块在两张卡上重复出现，是仪表盘
            // 观感最强的来源。降为中性小图标，让大号数字自己承担层级。
            Icon(icon, size: 16, color: colors.textTertiary),
            const SizedBox(width: IdeSpacing.space8),
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
                    // 数值用主前景色而不是品牌色：这是要读的数据，不是要点击的
                    // 行动点。着色的大数字会让整页读起来像营销仪表盘。
                    style: textStyles.metricValue,
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
        title: context.l10n.usageTrendTitle,
        subtitle: context.l10n.usageTrendSubtitle,
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
            semanticLabel: context.l10n.usageDetailTabsSemantic,
            items: [
              IdeTabItem(
                key: const ValueKey('usage-detail-tab-agents'),
                value: _UsageDetailTab.agents,
                label: context.l10n.usageAgentStats,
              ),
              IdeTabItem(
                key: const ValueKey('usage-detail-tab-models'),
                value: _UsageDetailTab.models,
                label: context.l10n.usageModelStats,
              ),
              IdeTabItem(
                key: const ValueKey('usage-detail-tab-projects'),
                value: _UsageDetailTab.projects,
                label: context.l10n.usageProjectList,
              ),
              IdeTabItem(
                key: const ValueKey('usage-detail-tab-tasks'),
                value: _UsageDetailTab.tasks,
                label: context.l10n.usageTaskList,
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
                context.l10n.usageRankSummary,
                style: textStyles.meta.copyWith(color: colors.textSecondary),
              ),
            ),
            IdeSelect<UsageRankSort>(
              key: const ValueKey('usage-agent-rank-sort'),
              width: 140,
              value: controller.rankSort,
              options: [
                for (final sort in UsageRankSort.values)
                  IdeSelectOption(sort, sort.localizedLabel(context.l10n)),
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
          headers: [
            'Agent',
            context.l10n.usageHeaderCalls,
            context.l10n.usageHeaderSuccessRate,
            context.l10n.usageHeaderToken,
            context.l10n.usageHeaderFailures,
            context.l10n.usageHeaderAverageDuration,
          ],
          flexes: const [3, 2, 2, 2, 2, 2],
          identifierColumns: const {0},
          numericColumns: const {1, 2, 3, 4, 5},
          rows: [
            for (final entry in entries)
              [
                entry.providerName,
                formatUsageCount(entry.calls),
                formatUsagePercent(
                  entry.successRate,
                  empty: context.l10n.usageNoData,
                ),
                entry.totalTokens == null
                    ? context.l10n.usageUnsupported
                    : formatUsageCount(entry.totalTokens!),
                entry.failures.toString(),
                formatUsageDuration(
                  entry.averageDuration,
                  compact: true,
                  empty: context.l10n.usageNoData,
                ),
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
          context.l10n.usageModelTokenShare,
          style: textStyles.meta.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: IdeSpacing.space8),
        if (!tokens.hasData && report.modelShares.isEmpty)
          Text(
            context.l10n.usageNoModelStats,
            style: textStyles.bodyMedium.copyWith(color: colors.textSecondary),
          )
        else ...[
          if (tokens.hasData) ...[
            Wrap(
              spacing: IdeSpacing.space12,
              runSpacing: IdeSpacing.space6,
              children: [
                _InlineMetric(
                  label: context.l10n.usageTokenTotal,
                  value: formatUsageCount(tokens.effectiveTotal ?? 0),
                ),
                _InlineMetric(
                  label: context.l10n.usageTokenInput,
                  value: formatUsageCount(tokens.inputTokens ?? 0),
                ),
                _InlineMetric(
                  label: context.l10n.usageTokenCachedInput,
                  value: formatUsageCount(tokens.cachedInputTokens ?? 0),
                ),
                _InlineMetric(
                  label: context.l10n.usageTokenOutput,
                  value: formatUsageCount(tokens.outputTokens ?? 0),
                ),
                _InlineMetric(
                  label: context.l10n.usageTokenReasoning,
                  value: formatUsageCount(tokens.reasoningTokens ?? 0),
                ),
              ],
            ),
            const SizedBox(height: IdeSpacing.space12),
          ],
          _UsageTable(
            minWidth: 520,
            headers: [
              context.l10n.usageHeaderModel,
              context.l10n.usageHeaderToken,
              context.l10n.usageHeaderShare,
            ],
            flexes: const [4, 2, 2],
            identifierColumns: const {0},
            numericColumns: const {1, 2},
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
          context.l10n.usageProjectSummary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textStyles.meta.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: IdeSpacing.space8),
        _UsageTable(
          minWidth: 620,
          headers: [
            context.l10n.usageHeaderProject,
            context.l10n.usageHeaderCalls,
            context.l10n.usageHeaderToken,
            context.l10n.usageHeaderAverageDuration,
            context.l10n.usageHeaderLastUsed,
          ],
          flexes: const [3, 2, 2, 2, 2],
          numericColumns: const {1, 2, 3},
          rows: [
            for (final entry in entries)
              [
                entry.projectName,
                formatUsageCount(entry.calls),
                entry.totalTokens == null
                    ? context.l10n.usageUnsupported
                    : formatUsageCount(entry.totalTokens!),
                formatUsageDuration(
                  entry.averageDuration,
                  compact: true,
                  empty: context.l10n.usageNoData,
                ),
                formatUsageRelativeTime(
                  entry.lastUsedAt,
                  DateTime.now(),
                  l10n: context.l10n,
                ),
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
          context.l10n.usageTaskListSummary('${records.length}', '$pageSize'),
          style: textStyles.meta.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: IdeSpacing.space8),
        _UsageTable(
          minWidth: 780,
          headers: [
            context.l10n.usageHeaderTime,
            context.l10n.usageHeaderProject,
            'Agent',
            context.l10n.usageHeaderModel,
            context.l10n.usageHeaderDuration,
            context.l10n.usageHeaderToken,
            context.l10n.usageHeaderStatus,
          ],
          flexes: const [2, 3, 2, 3, 2, 2, 2],
          identifierColumns: const {2, 3},
          numericColumns: const {4, 5},
          rows: [
            for (final record in visible)
              [
                formatUsageDateTime(
                  record.startedAt,
                  empty: context.l10n.usageNoData,
                ),
                record.projectName,
                record.providerName,
                record.model ?? context.l10n.usageUnknownModel,
                formatUsageDuration(
                  record.duration,
                  compact: true,
                  empty: context.l10n.usageNoData,
                ),
                record.tokens.effectiveTotal == null
                    ? context.l10n.usageUnsupported
                    : formatUsageCount(record.tokens.effectiveTotal!),
                record.status.localizedLabel(context.l10n),
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
    this.numericColumns = const <int>{},
    this.identifierColumns = const <int>{},
  });

  final double minWidth;
  final List<String> headers;
  final List<int> flexes;
  final List<List<String>> rows;
  final List<String>? rowKeys;
  final ValueChanged<int>? onRowPressed;

  /// 按数值列渲染的列下标，交给 [IdeDataRow] 做等宽右对齐。
  final Set<int> numericColumns;

  /// 按机器标识符渲染的列下标（模型 ID、Agent 名）。
  final Set<int> identifierColumns;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    if (rows.isEmpty) {
      return Text(
        context.l10n.usageNoData,
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
                  IdeDataRow(
                    values: headers,
                    flexes: flexes,
                    header: true,
                    numericColumns: numericColumns,
                  ),
                  for (var index = 0; index < rows.length; index += 1)
                    IdeDataRow(
                      key: _rowKey(index),
                      values: rows[index],
                      flexes: flexes,
                      numericColumns: numericColumns,
                      identifierColumns: identifierColumns,
                      onPressed: onRowPressed == null
                          ? null
                          : () => onRowPressed!(index),
                      showDivider: index + 1 < rows.length,
                      semanticLabel: onRowPressed == null
                          ? null
                          : context.l10n.usageOpenDetail(rows[index].first),
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
    final maximum = safeUsageChartMaximum(points);
    final yInterval = maximum / 3;
    // 折线与 hover 圆点有实际宽度，数据点不能贴在裁剪边界上，否则首尾、零值和
    // 最大值只能绘制一部分。单点数据居中，多点数据按横轴跨度保留稳定比例的安全区。
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
      label: context.l10n.usageTrendSemantic(
        metric.localizedLabel(context.l10n),
        '${points.length}',
      ),
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
                // 点阵而不是实线：网格只需要提供刻度参照，不该在视觉上
                // 和数据曲线竞争。1 实 3 虚渲染出来接近点阵底。
                getDrawingHorizontalLine: (_) => FlLine(
                  color: colors.borderSubtle,
                  strokeWidth: 1,
                  dashArray: const <int>[1, 3],
                ),
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
                          _formatTrendAxisValue(
                            metric: metric,
                            value: value,
                            empty: context.l10n.usageNoData,
                          ),
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
                            empty: context.l10n.usageNoData,
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
                    // 单色发丝线：桌面开发者工具的监控图靠精确度取胜，不靠
                    // 粗折线和渐变面积。品牌色只留给 hover 指示，避免一条
                    // 常驻的彩色曲线在单色界面里变成最抢眼的东西。
                    color: colors.textSecondary,
                    barWidth: 1,
                    isStrokeCapRound: true,
                    isStrokeJoinRound: true,
                    preventCurveOverShooting: true,
                    // 常态不画数据点：点密时会连成一条粗带，反而看不清趋势。
                    // 精确读数由 hover 指示器和 tooltip 提供。
                    dotData: const FlDotData(show: false),
                    // 不要面积填充。它是 SaaS 仪表盘的默认观感，且在炭黑底上
                    // 只会糊成一块噪点，对读数没有任何帮助。
                    belowBarData: BarAreaData(show: false),
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
  required String empty,
}) {
  return '$label · ${_formatTrendAxisValue(metric: metric, value: value, empty: empty)}';
}

/// Y 轴与 Tooltip 共用的趋势数值格式化。
String _formatTrendAxisValue({
  required UsageTrendMetric metric,
  required double value,
  required String empty,
}) {
  return switch (metric) {
    UsageTrendMetric.calls ||
    UsageTrendMetric.totalTokens => formatUsageCount(value),
    UsageTrendMetric.successRate => formatUsagePercent(value, empty: empty),
    UsageTrendMetric.averageResponse ||
    UsageTrendMetric.averageDuration => formatUsageDuration(
      Duration(milliseconds: value.round()),
      compact: true,
      empty: empty,
    ),
  };
}

class _TaskDetailDrawer extends StatelessWidget {
  const _TaskDetailDrawer({required this.record});

  final AgentUsageRecord record;

  @override
  Widget build(BuildContext context) {
    return _DrawerSurface(
      title: context.l10n.usageTaskDetail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailRow(
            label: context.l10n.usageFieldProject,
            value: record.projectName,
          ),
          _DetailRow(
            label: context.l10n.usageFieldProjectPath,
            value: record.projectPath,
          ),
          _DetailRow(label: 'Agent', value: record.providerName),
          _DetailRow(
            label: context.l10n.usageModelLabel,
            value: record.model ?? context.l10n.usageUnknownModel,
          ),
          _DetailRow(
            label: context.l10n.usageFieldSource,
            value: _sourceKindLabel(record.sourceKind, context.l10n),
          ),
          _DetailRow(
            label: context.l10n.usageFieldStartTime,
            value: formatUsageDateTime(
              record.startedAt,
              empty: context.l10n.usageNoData,
            ),
          ),
          _DetailRow(
            label: context.l10n.usageFieldDuration,
            value: formatUsageDuration(
              record.duration,
              empty: context.l10n.usageNoData,
            ),
          ),
          _DetailRow(
            label: context.l10n.usageFieldFirstResponse,
            value: formatUsageDuration(
              record.timeToFirstToken,
              empty: context.l10n.usageNoData,
            ),
          ),
          _DetailRow(
            label: context.l10n.usageHeaderToken,
            value: record.tokens.effectiveTotal == null
                ? context.l10n.usageTokenNotSupported
                : context.l10n.usageTokenFullDetail(
                    formatUsageCount(record.tokens.effectiveTotal!),
                    formatUsageCount(record.tokens.inputTokens ?? 0),
                    formatUsageCount(record.tokens.cachedInputTokens ?? 0),
                    formatUsageCount(record.tokens.outputTokens ?? 0),
                    formatUsageCount(record.tokens.reasoningTokens ?? 0),
                  ),
          ),
          _DetailRow(
            label: context.l10n.usageFieldStatus,
            value: record.status.localizedLabel(context.l10n),
          ),
          if (record.errorCategory case final category?) ...[
            _DetailRow(
              label: context.l10n.usageFieldErrorCategory,
              value: category.localizedLabel(context.l10n),
            ),
            _DetailRow(
              label: context.l10n.usageFieldReason,
              value:
                  record.errorMessage ??
                  record.errorCode ??
                  context.l10n.usageNoReason,
            ),
            _DetailRow(
              label: context.l10n.usageFieldNextStep,
              value: category.localizedNextAction(context.l10n),
            ),
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

String _sourceKindLabel(String sourceKind, AppLocalizations l10n) {
  return switch (sourceKind) {
    'cli' => l10n.usageSourceKindCli,
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
              sf.LucideIcons.chartLine,
              size: 36,
              color: colors.textTertiary,
            ),
            const SizedBox(height: IdeSpacing.space12),
            Text(context.l10n.usageEmptyTitle, style: textStyles.displaySmall),
            const SizedBox(height: IdeSpacing.space6),
            Text(
              context.l10n.usageEmptyBody,
              textAlign: TextAlign.center,
              style: textStyles.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: IdeSpacing.space16),
            IdeButton(
              key: const ValueKey('usage-open-agent-management-button'),
              label: context.l10n.usageOpenAgentManagement,
              variant: IdeButtonVariant.primary,
              onPressed: onOpenAgentManagement,
            ),
          ],
        ),
      ),
    );
  }
}

/// 使用统计冷加载骨架：概况卡 + 趋势区 + 列表行，贴近真实页面结构。
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.usageLoading,
      container: true,
      child: const Column(
        key: ValueKey('usage-statistics-loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OverviewSkeleton(),
          SizedBox(height: IdeSpacing.space12),
          _TrendSkeleton(),
          SizedBox(height: IdeSpacing.space16),
          _DetailSkeleton(),
        ],
      ),
    );
  }
}

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < IdeMetrics.stackedRowBreakpoint;
        final cards = const [
          _OverviewMetricSkeleton(),
          _OverviewMetricSkeleton(),
        ];
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cards[0],
              const SizedBox(height: IdeSpacing.space8),
              cards[1],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: IdeSpacing.space8),
              Expanded(child: cards[1]),
            ],
          ),
        );
      },
    );
  }
}

class _OverviewMetricSkeleton extends StatelessWidget {
  const _OverviewMetricSkeleton();

  @override
  Widget build(BuildContext context) {
    return IdeSurface.pane(
      padding: IdeSpacing.panelPadding,
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IdeSkeletonBlock(width: 36, height: 36),
          SizedBox(width: IdeSpacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                IdeSkeletonLine(width: 72, height: 10),
                SizedBox(height: IdeSpacing.space4),
                IdeSkeletonLine(width: 96, height: 22),
                SizedBox(height: IdeSpacing.space6),
                IdeSkeletonLine(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendSkeleton extends StatelessWidget {
  const _TrendSkeleton();

  @override
  Widget build(BuildContext context) {
    return IdeSurface.pane(
      padding: IdeSpacing.panelPadding,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeSkeletonLine(width: 72, height: 14),
          SizedBox(height: IdeSpacing.space4),
          IdeSkeletonLine(width: 180, height: 10),
          SizedBox(height: IdeSpacing.space12),
          IdeSkeletonBlock(height: 180),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return IdeSurface.pane(
      padding: IdeSpacing.panelPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              IdeSkeletonLine(width: 72, height: 28),
              SizedBox(width: IdeSpacing.space8),
              IdeSkeletonLine(width: 72, height: 28),
              SizedBox(width: IdeSpacing.space8),
              IdeSkeletonLine(width: 72, height: 28),
              SizedBox(width: IdeSpacing.space8),
              IdeSkeletonLine(width: 72, height: 28),
            ],
          ),
          const SizedBox(height: IdeSpacing.space12),
          for (var i = 0; i < 5; i++) ...[
            if (i > 0) const SizedBox(height: IdeSpacing.space8),
            const _DetailRowSkeleton(),
          ],
        ],
      ),
    );
  }
}

class _DetailRowSkeleton extends StatelessWidget {
  const _DetailRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(flex: 3, child: IdeSkeletonLine(height: 14)),
        SizedBox(width: IdeSpacing.space12),
        Expanded(flex: 2, child: IdeSkeletonLine(height: 14)),
        SizedBox(width: IdeSpacing.space12),
        IdeSkeletonLine(width: 48, height: 14),
      ],
    );
  }
}
