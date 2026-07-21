import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_controller.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/presentation/agent_usage_panel.dart';
import 'package:zeta/src/ui/core/app_theme.dart';

void main() {
  testWidgets('按 Provider Tab 展示今日 Token，并只展示可用套餐', (tester) async {
    final controller = AgentUsagePanelController(
      repository: _PanelRepository(
        AgentUsagePanelSnapshot(
          refreshedAt: DateTime(2026, 7, 21, 12),
          entries: <AgentUsagePanelEntry>[
            AgentUsagePanelEntry(
              providerId: 'codex-work',
              providerName: 'Codex Work',
              todayTokens: const UsageTokenBreakdown(
                inputTokens: 1200,
                cachedInputTokens: 300,
                outputTokens: 400,
                reasoningTokens: 100,
                totalTokens: 1600,
              ),
              quota: AgentUsageQuotaSnapshot(
                providerId: 'codex-work',
                providerName: 'Codex Work',
                planType: 'plus',
                windows: <AgentUsageWindow>[
                  AgentUsageWindow(
                    label: '5 小时',
                    usedPercent: 25,
                    resetsAt: DateTime(2026, 7, 21, 15),
                  ),
                  const AgentUsageWindow(label: '周', usedPercent: 40),
                ],
              ),
            ),
            const AgentUsagePanelEntry(
              providerId: 'grok-personal',
              providerName: 'Grok Personal',
            ),
          ],
        ),
      ),
    );
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller);

    expect(find.text('Agent 统计'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-usage-tabs')), findsOneWidget);
    expect(find.text('1.6K'), findsOneWidget);
    expect(find.text('ChatGPT Plus'), findsOneWidget);
    expect(find.text('5 小时'), findsOneWidget);
    expect(find.text('剩余 75%'), findsOneWidget);
    expect(find.text('周'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('agent-usage-tab-grok-personal')),
    );
    await tester.pump();

    expect(find.text('暂无统计'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-usage-plan-section')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('失败时提供重试入口', (tester) async {
    final repository = _RetryRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller);
    expect(find.text('Agent 用量暂时无法读取'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-usage-retry-button')));
    await tester.pump();
    await tester.pump();

    expect(find.text('暂无已启用的 Agent'), findsOneWidget);
    expect(repository.loadCount, 2);
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  AgentUsagePanelController controller,
) async {
  tester.view
    ..physicalSize = const Size(320, 520)
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
        home: sf.Scaffold(child: AgentUsagePanel(controller: controller)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _PanelRepository implements AgentUsagePanelRepository {
  const _PanelRepository(this.snapshot);

  final AgentUsagePanelSnapshot snapshot;

  @override
  Future<AgentUsagePanelSnapshot> load({bool forceRefresh = false}) async {
    return snapshot;
  }
}

class _RetryRepository implements AgentUsagePanelRepository {
  var loadCount = 0;

  @override
  Future<AgentUsagePanelSnapshot> load({bool forceRefresh = false}) async {
    loadCount += 1;
    if (loadCount == 1) {
      throw StateError('offline');
    }
    return AgentUsagePanelSnapshot(
      entries: const <AgentUsagePanelEntry>[],
      refreshedAt: DateTime(2026, 7, 21),
    );
  }
}
