import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_controller.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_page.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta_ui/zeta_ui.dart';

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
    expect(find.byKey(const ValueKey('usage-detail-tabs')), findsOneWidget);
    expect(find.text('Agent 统计'), findsOneWidget);
    expect(find.text('模型统计'), findsOneWidget);
    expect(find.text('项目列表'), findsOneWidget);
    expect(find.text('任务列表'), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-panel-agents')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('usage-main-chart-totalTokens')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('usage-overview-tokens')), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-overview-calls')), findsOneWidget);
    expect(find.text('Token 使用量'), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-filters-toolbar')), findsOneWidget);
    expect(
      tester
          .widget<IdeSurface>(
            find.byKey(const ValueKey('usage-filters-toolbar')),
          )
          .level,
      IdeSurfaceLevel.pane,
    );
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
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('usage-detail-tab-tasks')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('usage-panel-tasks')), findsOneWidget);
    expect(find.byType(IdeDataRow), findsWidgets);

    final taskRow = find.byKey(
      const ValueKey('usage-row-codex/thread-1/turn-1'),
    );
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
    expect(find.text('Token'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches detail tabs and shows model stats', (tester) async {
    final now = DateTime(2026, 7, 10, 12);
    final controller = UsageStatisticsController(
      repository: _UsageRepository(_source(now)),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);
    await _pumpUsagePage(tester, controller: controller);

    await tester.tap(find.byKey(const ValueKey('usage-detail-tab-models')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('usage-panel-models')), findsOneWidget);
    expect(find.text('推理 100', findRichText: true), findsOneWidget);
    expect(find.text('gpt-5'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('usage-detail-tab-projects')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('usage-panel-projects')), findsOneWidget);
    expect(find.text('zeta'), findsOneWidget);
  });

  testWidgets('adapts filters to a narrow viewport', (tester) async {
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
    expect(find.byKey(const ValueKey('usage-detail-tabs')), findsOneWidget);
    final timeRangeFilter = find.byKey(
      const ValueKey('usage-time-range-filter'),
    );
    final expectedHeight = IdeMetrics.controlNaturalHeightFor(
      IdeTextStyles.of(tester.element(timeRangeFilter)).bodySmall,
      size: IdeControlSize.regular,
    );
    expect(tester.getSize(timeRangeFilter).height, expectedHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aligns agent filter text style with time range trigger', (
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

    TextStyle? styleOf(ValueKey<String> key) {
      return tester
          .widget<Text>(
            find.descendant(of: find.byKey(key), matching: find.byType(Text)),
          )
          .style;
    }

    final timeStyle = styleOf(const ValueKey('usage-time-range-filter'));
    final agentStyle = styleOf(const ValueKey('usage-agent-filter'));
    final modelStyle = styleOf(const ValueKey('usage-model-filter'));

    expect(timeStyle?.fontSize, isNotNull);
    expect(agentStyle?.fontSize, timeStyle?.fontSize);
    expect(modelStyle?.fontSize, timeStyle?.fontSize);
  });

  testWidgets('keeps trend endpoints and labels inside chart bounds', (
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
    // SideTitleWidget 首帧后测量标签宽度，再回收首尾标签的位置。
    await tester.pump();

    final chartScope = find.byKey(
      const ValueKey('usage-main-chart-totalTokens'),
    );
    final chartFinder = find.descendant(
      of: chartScope,
      matching: find.byType(LineChart),
    );
    final chart = tester.widget<LineChart>(chartFinder);
    final data = chart.data;
    final bar = data.lineBarsData.single;

    expect(data.minX, lessThan(bar.spots.first.x));
    expect(data.maxX, greaterThan(bar.spots.last.x));
    expect(
      data.minY,
      lessThan(bar.spots.map((spot) => spot.y).reduce(math.min)),
    );
    expect(
      data.maxY,
      greaterThan(bar.spots.map((spot) => spot.y).reduce(math.max)),
    );
    // 发丝单色线：无面积填充、无常态数据点，网格走点阵。
    expect(bar.belowBarData.show, isFalse);
    expect(bar.barWidth, 1);
    expect(bar.dotData.show, isFalse);
    expect(data.gridData.getDrawingHorizontalLine(0).dashArray, isNotEmpty);

    final chartRect = tester.getRect(chartFinder);
    final bottomTitles = tester
        .widgetList<SideTitleWidget>(
          find.descendant(
            of: chartScope,
            matching: find.byType(SideTitleWidget),
          ),
        )
        .where((widget) => widget.meta.axisSide == AxisSide.bottom)
        .toList();
    expect(bottomTitles, isNotEmpty);
    for (final title in bottomTitles) {
      expect(title.fitInside.enabled, isTrue);
      final titleText = find.descendant(
        of: find.byWidget(title),
        matching: find.byType(Text),
      );
      expect(titleText, findsOneWidget);
      final titleRect = tester.getRect(titleText);
      expect(titleRect.left, greaterThanOrEqualTo(chartRect.left));
      expect(titleRect.right, lessThanOrEqualTo(chartRect.right));
    }
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

  testWidgets('paginates task list beyond page size', (tester) async {
    final now = DateTime(2026, 7, 10, 12);
    final records = <AgentUsageRecord>[
      for (var i = 0; i < 25; i += 1)
        AgentUsageRecord(
          threadId: 'thread-$i',
          turnId: 'turn-$i',
          providerId: 'codex',
          providerName: 'Codex',
          projectPath: r'C:\work\zeta',
          sourceKind: 'appServer',
          startedAt: DateTime(2026, 7, 10, 9).subtract(Duration(minutes: i)),
          status: UsageTaskStatus.completed,
          tokens: const UsageTokenBreakdown(totalTokens: 10),
        ),
    ];
    final controller = UsageStatisticsController(
      repository: _UsageRepository(
        UsageStatisticsSourceSnapshot(records: records, refreshedAt: now),
      ),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    await tester.runAsync(controller.initialize);
    await _pumpUsagePage(tester, controller: controller);

    await tester.tap(find.byKey(const ValueKey('usage-detail-tab-tasks')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('usage-task-pagination')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('usage-row-codex/thread-0/turn-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('usage-row-codex/thread-20/turn-20')),
      findsNothing,
    );

    // 翻到第 2 页：分页在页面 ListView 底部，需先滚入视口。
    final pagination = find.byKey(const ValueKey('usage-task-pagination'));
    await tester.scrollUntilVisible(
      pagination,
      300,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    final pageTwo = find.descendant(of: pagination, matching: find.text('2'));
    expect(pageTwo, findsOneWidget);
    await tester.tap(pageTwo);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('usage-row-codex/thread-20/turn-20')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('usage-row-codex/thread-0/turn-0')),
      findsNothing,
    );
  });

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
    await tester.tap(find.byKey(const ValueKey('usage-detail-tab-tasks')));
    await tester.pumpAndSettle();

    final firstDuplicateRow = find.byKey(
      const ValueKey('usage-row-codex/thread-1/turn-1'),
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
      find.byKey(const ValueKey('usage-row-codex/thread-1/turn-1#2')),
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
    expect(find.byKey(const ValueKey('usage-detail-tabs')), findsNothing);
  });

  testWidgets('cold load shows breathing skeleton instead of progress bar', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final now = DateTime(2026, 7, 10, 12);
      final repository = _DeferredUsageRepository(_source(now));
      final controller = UsageStatisticsController(
        repository: repository,
        clock: () => now,
      );
      addTearDown(controller.dispose);

      // 不 await initialize：保持 loading，断言 Skeleton。
      unawaited(controller.initialize());
      await _pumpUsagePage(tester, controller: controller);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('usage-statistics-loading')),
        findsOneWidget,
      );
      expect(find.byType(sf.Progress), findsNothing);
      expect(find.bySemanticsLabel('正在加载使用统计'), findsOneWidget);
      expect(find.textContaining('正在索引'), findsNothing);

      repository.complete();
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('usage-statistics-loading')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('usage-overview-tokens')),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('same records keep provider names across locales', (
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
      locale: ZetaLocalization.english,
    );
    expect(find.text('Usage statistics'), findsOneWidget);
    expect(find.text('Codex'), findsWidgets);
    expect(find.text('使用统计'), findsNothing);

    await _pumpUsagePage(tester, controller: controller);
    expect(find.text('使用统计'), findsOneWidget);
    expect(find.text('Codex'), findsWidgets);
  });
}

Future<void> _pumpUsagePage(
  WidgetTester tester, {
  required UsageStatisticsController controller,
  Size size = const Size(1200, 900),
  VoidCallback? onOpenAgentManagement,
  Locale locale = ZetaLocalization.simplifiedChinese,
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
        locale: locale,
        supportedLocales: ZetaLocalization.supportedLocales,
        localizationsDelegates: ZetaLocalization.delegates,
        theme: buildShadcnTheme(ideTheme),
        materialTheme: buildMaterialTheme(ideTheme),
        home: sf.Scaffold(
          child: UsageStatisticsPage(
            controller: controller,
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

/// 可控延迟仓库：用于断言冷加载 Skeleton，完成后再返回真实数据。
class _DeferredUsageRepository implements UsageStatisticsRepository {
  _DeferredUsageRepository(this.snapshot);

  final UsageStatisticsSourceSnapshot snapshot;
  final Completer<UsageStatisticsSourceSnapshot> _completer =
      Completer<UsageStatisticsSourceSnapshot>();

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete(snapshot);
    }
  }

  @override
  Future<UsageStatisticsSourceSnapshot> load({
    required DateTime earliest,
    bool forceRefresh = false,
  }) => _completer.future;
}
