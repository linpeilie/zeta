import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_controller.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_page.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/metrics/compact_metric_bar.dart';
import 'package:zeta/src/ui/core/rows/ide_data_row.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';

void main() {
  testWidgets('renders full statistics and opens task detail drawer', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 10, 12);
    final controller = UsageStatisticsController(
      repository: _UsageRepository(_source(now)),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);

    await _pumpUsagePage(tester, controller: controller);

    expect(find.byKey(const ValueKey('usage-statistics-page')), findsOneWidget);
    expect(find.text('使用统计'), findsOneWidget);
    expect(find.text('Agent 使用排行'), findsOneWidget);
    expect(find.text('项目使用排行'), findsOneWidget);
    expect(find.text('Token 分析'), findsOneWidget);
    expect(find.text('推理 100', findRichText: true), findsOneWidget);
    expect(find.text('ChatGPT Plus'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('usage-main-chart-calls')),
      findsOneWidget,
    );
    expect(find.byType(CompactMetricBar), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-filters-toolbar')), findsOneWidget);
    expect(
      tester
          .widget<IdeSurface>(
            find.byKey(const ValueKey('usage-filters-toolbar')),
          )
          .level,
      IdeSurfaceLevel.pane,
    );
    expect(find.byType(IdeDataRow), findsWidgets);
    expect(
      tester
          .widget<IdeSurface>(
            find.byKey(const ValueKey('usage-statistics-page')),
          )
          .level,
      IdeSurfaceLevel.canvas,
    );
    expect(
      tester
          .widget<IdeSurface>(
            find.byKey(const ValueKey('usage-primary-trend-pane')),
          )
          .level,
      IdeSurfaceLevel.pane,
    );
    expect(
      find.byKey(const ValueKey('usage-ranking-layout-equal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('usage-resource-layout-equal')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final taskRow = find.byKey(const ValueKey('usage-row-thread-1/turn-1'));
    await tester.ensureVisible(taskRow);
    await tester.pumpAndSettle();
    await tester.tap(taskRow);
    await tester.pumpAndSettle();

    expect(find.text('任务详情'), findsOneWidget);
    expect(
      tester
          .widget<IdeSurface>(
            find.byKey(const ValueKey('usage-drawer-surface')),
          )
          .level,
      IdeSurfaceLevel.popover,
    );
    expect(find.text('项目路径'), findsOneWidget);
    expect(find.text(r'C:\work\zeta'), findsWidgets);
    expect(find.text('首次响应'), findsOneWidget);
    expect(find.textContaining('Prompt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adapts filters and content to a narrow viewport', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 10, 12);
    final controller = UsageStatisticsController(
      repository: _UsageRepository(_source(now)),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);

    await _pumpUsagePage(
      tester,
      controller: controller,
      size: const Size(520, 820),
    );

    expect(
      find.byKey(const ValueKey('usage-time-range-filter')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('usage-project-filter')), findsNothing);
    expect(find.byKey(const ValueKey('usage-agent-filter')), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-model-filter')), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-custom-date-range')), findsNothing);
    expect(
      find.byKey(const ValueKey('usage-ranking-layout-stacked')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('usage-resource-layout-stacked')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('usage-time-range-filter')))
          .height,
      IdeMetrics.toolbarHeight,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens time range popover with shortcuts and calendar', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 10, 12);
    final controller = UsageStatisticsController(
      repository: _UsageRepository(_source(now)),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);

    await _pumpUsagePage(tester, controller: controller);

    expect(find.text('最近7天'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('usage-time-range-filter')));
    // Popover / Calendar 可能带持续动画，避免 pumpAndSettle 超时。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('usage-time-range-popover')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('usage-time-range-shortcuts')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('usage-time-range-calendar')),
      findsOneWidget,
    );
    expect(find.text('当天'), findsWidgets);
    expect(find.text('最近7天'), findsWidgets);
    expect(find.text('最近30天'), findsOneWidget);
    expect(find.text('1d'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('usage-time-range-preset-today')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.timePreset, UsageTimeRangePreset.today);
    expect(
      find.byKey(const ValueKey('usage-time-range-popover')),
      findsNothing,
    );
    expect(find.text('当天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'uses stacked rankings and a 6:4 resource layout at medium width',
    (tester) async {
      final now = DateTime(2026, 7, 10, 12);
      final controller = UsageStatisticsController(
        repository: _UsageRepository(_source(now)),
        clock: () => now,
      );
      addTearDown(controller.dispose);
      await tester.runAsync(controller.initialize);

      await _pumpUsagePage(
        tester,
        controller: controller,
        size: const Size(900, 900),
      );

      expect(
        find.byKey(const ValueKey('usage-ranking-layout-stacked')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('usage-resource-layout-sixty-forty')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('usage-table-horizontal-scroll')),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps table row keys unique for duplicate record ids', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 10, 12);
    final source = _source(now);
    final duplicate = AgentUsageRecord(
      threadId: 'thread-1',
      turnId: 'turn-1',
      providerId: 'codex',
      providerName: 'Codex',
      projectPath: r'C:\work\zeta',
      sourceKind: 'appServer',
      startedAt: DateTime(2026, 7, 10, 10),
      status: UsageTaskStatus.completed,
    );
    final controller = UsageStatisticsController(
      repository: _UsageRepository(
        UsageStatisticsSourceSnapshot(
          records: <AgentUsageRecord>[duplicate, ...source.records],
          refreshedAt: source.refreshedAt,
          quota: source.quota,
          warnings: source.warnings,
        ),
      ),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);

    await _pumpUsagePage(tester, controller: controller);

    final firstDuplicateRow = find.byKey(
      const ValueKey('usage-row-thread-1/turn-1'),
    );
    await tester.scrollUntilVisible(
      firstDuplicateRow,
      500,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(firstDuplicateRow, findsOneWidget);
    expect(
      find.byKey(const ValueKey('usage-row-thread-1/turn-1#2')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows empty state and opens Agent management callback', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 10, 12);
    final controller = UsageStatisticsController(
      repository: _UsageRepository(
        UsageStatisticsSourceSnapshot(records: const [], refreshedAt: now),
      ),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);
    var openedManagement = false;

    await _pumpUsagePage(
      tester,
      controller: controller,
      onOpenAgentManagement: () => openedManagement = true,
    );

    final button = find.byKey(
      const ValueKey('usage-open-agent-management-button'),
    );
    await tester.scrollUntilVisible(
      button,
      500,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.tap(button);
    await tester.pump();

    expect(openedManagement, isTrue);
    expect(find.text('暂无使用记录'), findsOneWidget);
  });
}

Future<void> _pumpUsagePage(
  WidgetTester tester, {
  required UsageStatisticsController controller,
  Size size = const Size(1200, 900),
  VoidCallback? onOpenAgentManagement,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
  final ideTheme = buildIdeThemeData(
    brightness: Brightness.light,
    codeFontFamily: 'JetBrainsMono',
  );
  await tester.pumpWidget(
    IdeThemeScope(
      themeMode: ThemeMode.light,
      lightTheme: ideTheme,
      darkTheme: buildIdeThemeData(
        brightness: Brightness.dark,
        codeFontFamily: 'JetBrainsMono',
      ),
      child: sf.ShadcnApp(
        theme: buildShadcnTheme(ideTheme),
        materialTheme: buildMaterialTheme(ideTheme),
        home: sf.Scaffold(
          child: UsageStatisticsPage(
            controller: controller,
            onBackPressed: () {},
            onOpenAgentManagement: onOpenAgentManagement ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

UsageStatisticsSourceSnapshot _source(DateTime now) {
  return UsageStatisticsSourceSnapshot(
    refreshedAt: now,
    quota: AgentUsageQuotaSnapshot(
      providerId: 'codex',
      providerName: 'Codex',
      planType: 'plus',
      windows: <AgentUsageWindow>[
        AgentUsageWindow(
          label: '主要额度',
          usedPercent: 35,
          resetsAt: now.add(const Duration(hours: 3)),
        ),
      ],
    ),
    records: <AgentUsageRecord>[
      AgentUsageRecord(
        threadId: 'thread-1',
        turnId: 'turn-1',
        providerId: 'codex',
        providerName: 'Codex',
        projectPath: r'C:\work\zeta',
        sourceKind: 'appServer',
        startedAt: DateTime(2026, 7, 10, 9),
        completedAt: DateTime(2026, 7, 10, 9, 3),
        duration: const Duration(minutes: 3),
        timeToFirstToken: const Duration(seconds: 2),
        model: 'gpt-5',
        status: UsageTaskStatus.completed,
        tokens: const UsageTokenBreakdown(
          inputTokens: 1200,
          cachedInputTokens: 300,
          outputTokens: 400,
          reasoningTokens: 100,
          totalTokens: 1600,
        ),
      ),
      AgentUsageRecord(
        threadId: 'thread-2',
        turnId: 'turn-2',
        providerId: 'codex',
        providerName: 'Codex',
        projectPath: r'C:\work\other',
        sourceKind: 'cli',
        startedAt: DateTime(2026, 7, 9, 9),
        completedAt: DateTime(2026, 7, 9, 9, 1),
        duration: const Duration(minutes: 1),
        model: 'gpt-5-mini',
        status: UsageTaskStatus.failed,
        errorCategory: UsageErrorCategory.timeout,
        errorMessage: 'Request timed out',
      ),
    ],
  );
}

class _UsageRepository implements UsageStatisticsRepository {
  _UsageRepository(this.snapshot);

  final UsageStatisticsSourceSnapshot snapshot;

  @override
  Future<UsageStatisticsSourceSnapshot> load({
    required DateTime earliest,
    bool forceRefresh = false,
  }) async => snapshot;
}
