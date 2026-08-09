import 'dart:async';

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
  testWidgets('默认 Provider Tab 仅展示 Codex 和 Grok', (tester) async {
    final controller = AgentUsagePanelController(
      repository: _ImmediatePanelRepository(const <AgentUsagePanelEntry>[
        AgentUsagePanelEntry(providerId: 'codex', providerName: 'Codex'),
        AgentUsagePanelEntry(providerId: 'grok', providerName: 'Grok'),
      ]),
    );
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller);

    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Grok'), findsOneWidget);
    expect(find.textContaining('CLI'), findsNothing);
  });

  testWidgets('按 Provider Tab 展示今日 Token，并只展示可用套餐', (tester) async {
    final controller = AgentUsagePanelController(
      repository: _ImmediatePanelRepository(_usageEntries),
    );
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller);

    expect(find.text('Agent 统计'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-usage-tabs')), findsOneWidget);
    expect(find.text('Codex Work'), findsOneWidget);
    expect(find.text('Grok Personal'), findsOneWidget);
    expect(find.textContaining('CLI'), findsNothing);
    expect(find.text('1.6K'), findsOneWidget);
    expect(find.text('ChatGPT Plus'), findsOneWidget);
    expect(find.text('5 小时'), findsOneWidget);
    expect(find.text('剩余 75%'), findsOneWidget);
    expect(find.text('1 周'), findsOneWidget);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('agent-usage-plan-section')))
          .dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('agent-usage-token-section')))
            .dy,
      ),
    );

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

  testWidgets('目录到达即展示 Tabs，单项完成后独立停止呼吸动画', (tester) async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);
    await _pumpPanel(tester, controller);

    final events = repository.controllers.single;
    events.add(_directoryFor(_usageEntries));
    await tester.pump();

    final codexTab = find.byKey(const ValueKey('agent-usage-tab-codex-work'));
    final grokTab = find.byKey(const ValueKey('agent-usage-tab-grok-personal'));
    expect(find.byKey(const ValueKey('agent-usage-tabs')), findsOneWidget);
    expect(
      find.descendant(
        of: codexTab,
        matching: find.byKey(const ValueKey('ide-tab-loading-label')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: grokTab,
        matching: find.byKey(const ValueKey('ide-tab-loading-label')),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Codex Work，正在加载'), findsOneWidget);

    events.add(AgentUsagePanelProviderLoaded(_usageEntries.first));
    await tester.pump();
    expect(
      find.descendant(
        of: codexTab,
        matching: find.byKey(const ValueKey('ide-tab-loading-label')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: grokTab,
        matching: find.byKey(const ValueKey('ide-tab-loading-label')),
      ),
      findsOneWidget,
    );

    await tester.tap(grokTab);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('agent-usage-provider-loading-grok-personal')),
      findsOneWidget,
    );
    // 无 entry 时用呼吸 Skeleton 占位，不再展示进度条文案。
    expect(find.bySemanticsLabel('正在读取 Agent 用量'), findsOneWidget);
    expect(find.textContaining('正在读取'), findsNothing);

    events
      ..add(AgentUsagePanelProviderLoaded(_usageEntries.last))
      ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21, 12)))
      ..close();
    await tester.pump();
  });

  testWidgets('可容纳的 Provider Tab 组在面板内水平居中', (tester) async {
    final controller = AgentUsagePanelController(
      repository: _ImmediatePanelRepository(_usageEntries),
    );
    addTearDown(controller.dispose);
    await _pumpPanel(tester, controller, width: 420);

    final panelCenter = tester.getCenter(
      find.byKey(const ValueKey('context-panel-card')),
    );
    final tabsCenter = tester.getCenter(find.byType(sf.Tabs));

    expect(tabsCenter.dx, closeTo(panelCenter.dx, 1));
  });

  testWidgets('Provider Tabs 超宽时可横向滚动且不溢出', (tester) async {
    final entries = <AgentUsagePanelEntry>[
      for (var index = 0; index < 6; index++)
        AgentUsagePanelEntry(
          providerId: 'provider-$index',
          providerName: 'Provider $index Very Long Name',
        ),
    ];
    final controller = AgentUsagePanelController(
      repository: _ImmediatePanelRepository(entries),
    );
    addTearDown(controller.dispose);
    await _pumpPanel(tester, controller, width: 260);

    final tabs = find.byKey(const ValueKey('agent-usage-tabs'));
    final horizontalScroll = find.descendant(
      of: tabs,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
    );
    expect(horizontalScroll, findsOneWidget);

    await tester.drag(horizontalScroll, const Offset(-180, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('刷新保留旧内容，并在失败后附加局部错误', (tester) async {
    final repository = _RefreshPanelRepository(_usageEntries.first);
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);
    await _pumpPanel(tester, controller);
    expect(find.text('1.6K'), findsOneWidget);

    final refresh = controller.refresh();
    await tester.pump();
    // 有旧数据时不替换为 Skeleton，也不再展示顶栏进度条。
    expect(find.text('1.6K'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-usage-panel-loading')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('agent-usage-provider-loading-codex-work')),
      findsNothing,
    );

    final events = repository.refreshEvents;
    events
      ..add(_directoryFor(<AgentUsagePanelEntry>[_usageEntries.first]))
      ..add(
        const AgentUsagePanelProviderFailed(
          provider: AgentUsagePanelProvider(
            providerId: 'codex-work',
            providerName: 'Codex Work',
          ),
          message: 'Codex 暂时不可用',
        ),
      )
      ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21, 13)))
      ..close();
    await refresh;
    await tester.pump();

    expect(find.text('1.6K'), findsOneWidget);
    expect(find.text('Codex 暂时不可用'), findsOneWidget);
  });

  testWidgets('静默刷新保留旧内容且不展示加载 Skeleton', (tester) async {
    final repository = _RefreshPanelRepository(_usageEntries.first);
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);
    await _pumpPanel(tester, controller);
    expect(find.text('1.6K'), findsOneWidget);

    final refresh = controller.refresh(showLoading: false);
    await tester.pump();
    expect(find.text('1.6K'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-usage-panel-loading')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('agent-usage-provider-loading-codex-work')),
      findsNothing,
    );

    final events = repository.refreshEvents;
    events
      ..add(_directoryFor(<AgentUsagePanelEntry>[_usageEntries.first]))
      ..add(AgentUsagePanelProviderLoaded(_usageEntries.first))
      ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21, 14)))
      ..close();
    await refresh;
    await tester.pump();

    expect(find.text('1.6K'), findsOneWidget);
    expect(controller.isLoading, isFalse);
  });

  testWidgets('冷加载展示呼吸 Skeleton 而非进度条', (tester) async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);
    await _pumpPanel(tester, controller);

    expect(
      find.byKey(const ValueKey('agent-usage-panel-loading')),
      findsOneWidget,
    );
    expect(find.byType(sf.LinearProgressIndicator), findsNothing);
    expect(find.byType(sf.Progress), findsNothing);
    expect(find.bySemanticsLabel('正在读取 Agent 用量'), findsOneWidget);
  });

  testWidgets('单 Provider 不显示 Tabs', (tester) async {
    final controller = AgentUsagePanelController(
      repository: _ImmediatePanelRepository(<AgentUsagePanelEntry>[
        _usageEntries.first,
      ]),
    );
    addTearDown(controller.dispose);
    await _pumpPanel(tester, controller);

    expect(find.byKey(const ValueKey('agent-usage-tabs')), findsNothing);
    expect(find.text('Codex Work'), findsOneWidget);
  });

  testWidgets('目录加载失败时提供重试入口', (tester) async {
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

  testWidgets('有套餐但无窗口百分比时默认剩余 100%', (tester) async {
    final controller = AgentUsagePanelController(
      repository: _ImmediatePanelRepository(const <AgentUsagePanelEntry>[
        AgentUsagePanelEntry(
          providerId: 'grok',
          providerName: 'Grok',
          quota: AgentUsageQuotaSnapshot(
            providerId: 'grok',
            providerName: 'Grok',
            planType: 'SuperGrok',
            limitName: '1 周',
            windows: <AgentUsageWindow>[],
          ),
        ),
      ]),
    );
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller);

    expect(find.text('SuperGrok'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-usage-plan-section')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent-usage-window-0')), findsOneWidget);
    expect(find.text('1 周'), findsWidgets);
    expect(find.text('剩余 100%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final _usageEntries = <AgentUsagePanelEntry>[
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
        const AgentUsageWindow(label: '1 周', usedPercent: 40),
      ],
    ),
  ),
  const AgentUsagePanelEntry(
    providerId: 'grok-personal',
    providerName: 'Grok Personal',
  ),
];

AgentUsagePanelProvidersDiscovered _directoryFor(
  List<AgentUsagePanelEntry> entries,
) {
  return AgentUsagePanelProvidersDiscovered(
    providers: <AgentUsagePanelProvider>[
      for (final entry in entries)
        AgentUsagePanelProvider(
          providerId: entry.providerId,
          providerName: entry.providerName,
        ),
    ],
  );
}

Future<void> _pumpPanel(
  WidgetTester tester,
  AgentUsagePanelController controller, {
  double width = 320,
}) async {
  unawaited(controller.refresh());
  tester.view
    ..physicalSize = Size(width, 520)
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

class _ImmediatePanelRepository implements AgentUsagePanelRepository {
  const _ImmediatePanelRepository(this.entries);

  final List<AgentUsagePanelEntry> entries;

  @override
  Stream<AgentUsagePanelLoadEvent> load({bool forceRefresh = false}) async* {
    yield _directoryFor(entries);
    for (final entry in entries) {
      yield AgentUsagePanelProviderLoaded(entry);
    }
    yield AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21, 12));
  }
}

class _ControlledPanelRepository implements AgentUsagePanelRepository {
  final List<StreamController<AgentUsagePanelLoadEvent>> controllers =
      <StreamController<AgentUsagePanelLoadEvent>>[];

  @override
  Stream<AgentUsagePanelLoadEvent> load({bool forceRefresh = false}) {
    final controller = StreamController<AgentUsagePanelLoadEvent>();
    controllers.add(controller);
    return controller.stream;
  }
}

class _RefreshPanelRepository implements AgentUsagePanelRepository {
  _RefreshPanelRepository(this.entry);

  final AgentUsagePanelEntry entry;
  var _loadCount = 0;
  late final StreamController<AgentUsagePanelLoadEvent> refreshEvents;

  @override
  Stream<AgentUsagePanelLoadEvent> load({bool forceRefresh = false}) {
    _loadCount += 1;
    if (_loadCount == 1) {
      return _ImmediatePanelRepository(<AgentUsagePanelEntry>[entry]).load();
    }
    refreshEvents = StreamController<AgentUsagePanelLoadEvent>();
    return refreshEvents.stream;
  }
}

class _RetryRepository implements AgentUsagePanelRepository {
  var loadCount = 0;

  @override
  Stream<AgentUsagePanelLoadEvent> load({bool forceRefresh = false}) async* {
    loadCount += 1;
    if (loadCount == 1) {
      throw StateError('offline');
    }
    yield AgentUsagePanelProvidersDiscovered(
      providers: const <AgentUsagePanelProvider>[],
    );
    yield AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21));
  }
}
