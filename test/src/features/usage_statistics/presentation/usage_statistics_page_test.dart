import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_controller.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_page.dart';
import 'package:zeta/src/ui/core/app_theme.dart';

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
    expect(find.text('ChatGPT Plus'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('usage-main-chart-calls')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final taskRow = find.byKey(const ValueKey('usage-row-thread-1/turn-1'));
    await tester.scrollUntilVisible(
      taskRow,
      500,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.tap(taskRow);
    await tester.pumpAndSettle();

    expect(find.text('任务详情'), findsOneWidget);
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
    await tester.runAsync(
      () => controller.selectTimePreset(UsageTimeRangePreset.custom),
    );

    await _pumpUsagePage(
      tester,
      controller: controller,
      size: const Size(520, 820),
    );

    expect(
      find.byKey(const ValueKey('usage-time-range-filter')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('usage-project-filter')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('usage-custom-date-range')),
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
      providerName: 'Codex CLI',
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
        providerName: 'Codex CLI',
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
          totalTokens: 1600,
        ),
      ),
      AgentUsageRecord(
        threadId: 'thread-2',
        turnId: 'turn-2',
        providerId: 'codex',
        providerName: 'Codex CLI',
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
