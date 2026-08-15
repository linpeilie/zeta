import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_provider_icon.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_controller.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/presentation/agent_usage_panel.dart';
import 'package:zeta/src/features/usage_statistics/presentation/agent_usage_quota_gallery.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/ui/core/ide_skeleton.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

/// 展开态弹层的根节点；折叠摘要仍留在锚点上，断言需按弹层限定范围。
final _popover = find.byKey(const ValueKey('agent-usage-popover'));

Finder _inPopover(Finder matching) =>
    find.descendant(of: _popover, matching: matching);

double _expectGalleryCardWidths(
  WidgetTester tester, {
  required int windowCount,
}) {
  final gallery = find.byKey(const ValueKey('agent-usage-quota-gallery'));
  expect(gallery, findsOneWidget);
  final gallerySize = tester.getSize(gallery);
  expect(gallerySize.height, agentUsageQuotaGalleryHeight);
  final expectedWidth = agentUsageQuotaCardWidth(
    viewportWidth: gallerySize.width,
    windowCount: windowCount,
  );
  for (var index = 0; index < windowCount && index < 2; index++) {
    expect(
      tester
          .getSize(find.byKey(ValueKey<String>('agent-usage-window-$index')))
          .width,
      closeTo(expectedWidth, 0.5),
    );
  }
  return gallerySize.height;
}

Future<void> _hoverAt(WidgetTester tester, Offset location) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: location);
  addTearDown(gesture.removePointer);
  await tester.pump();
}

Future<void> _pumpQuotaWindows(
  WidgetTester tester,
  List<AgentUsageWindow> windows,
) async {
  final controller = AgentUsagePanelController(
    repository: _ImmediatePanelRepository(<AgentUsagePanelEntry>[
      AgentUsagePanelEntry(
        providerId: 'codex',
        providerName: 'Codex',
        quota: AgentUsageQuotaSnapshot(
          providerId: 'codex',
          providerName: 'Codex',
          planType: 'plus',
          windows: windows,
        ),
      ),
    ]),
  );
  addTearDown(controller.dispose);
  await _pumpPanel(tester, controller);
}

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

    expect(_inPopover(find.text('Codex')), findsOneWidget);
    expect(_inPopover(find.text('Grok')), findsOneWidget);
    expect(find.textContaining('CLI'), findsNothing);
  });

  testWidgets('按 Provider Tab 展示今日 Token，并只展示可用套餐', (tester) async {
    final controller = AgentUsagePanelController(
      repository: _ImmediatePanelRepository(_usageEntries),
    );
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller);

    expect(find.text('Agent 统计'), findsNothing);
    expect(find.byType(Pane), findsNothing);
    expect(find.byKey(const ValueKey('agent-usage-tabs')), findsOneWidget);
    expect(find.text('Codex Work'), findsOneWidget);
    expect(find.text('Grok Personal'), findsOneWidget);
    expect(find.textContaining('CLI'), findsNothing);
    expect(_inPopover(find.text('1.6K')), findsOneWidget);
    expect(_inPopover(find.text('ChatGPT Plus')), findsOneWidget);
    expect(_inPopover(find.text('套餐')), findsNothing);
    expect(_inPopover(find.textContaining('重置 ')), findsNothing);
    expect(_inPopover(find.text('5 小时')), findsOneWidget);
    expect(_inPopover(find.text('75%')), findsOneWidget);
    expect(_inPopover(find.text('1 周')), findsOneWidget);
    expect(_inPopover(find.text('可用重置卡')), findsOneWidget);
    expect(_inPopover(find.text('2 张')), findsOneWidget);

    final firstWindow = find.byKey(
      const ValueKey<String>('agent-usage-window-0'),
    );
    final progressFinder = find.descendant(
      of: firstWindow,
      matching: find.byType(sf.LinearProgressIndicator),
    );
    expect(progressFinder, findsOneWidget);

    final progress = tester.widget<sf.LinearProgressIndicator>(progressFinder);
    expect(tester.getSize(progressFinder).height, 4);
    expect(progress.value, 0.75);
    expect(progress.minHeight, 4);
    expect(progress.color, IdeColors.light.textSecondary);
    expect(progress.backgroundColor, IdeColors.light.borderSubtle);
    expect(progress.borderRadius, IdeRadius.allMicro);
    expect(progress.showSparks, isFalse);
    expect(progress.disableAnimation, isTrue);

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

    expect(_inPopover(find.text('暂无统计')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-usage-plan-section')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('agent-usage-reset-credit-count')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('今日 Token 子项按 2×2 网格排布在浅灰圆角容器中', (tester) async {
    final controller = AgentUsagePanelController(
      repository: _ImmediatePanelRepository(_usageEntries),
    );
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller);

    final input = _inPopover(find.text('1.2K'));
    final cachedInput = _inPopover(find.text('300'));
    final output = _inPopover(find.text('400'));
    final reasoning = _inPopover(find.text('100'));
    expect(input, findsOneWidget);
    expect(cachedInput, findsOneWidget);
    expect(output, findsOneWidget);
    expect(reasoning, findsOneWidget);

    // 第一行“输入/缓存输入”、第二行“输出/推理”，行内左右并排、行间上下堆叠。
    expect(
      tester.getTopLeft(input).dy,
      closeTo(tester.getTopLeft(cachedInput).dy, 0.5),
    );
    expect(
      tester.getTopLeft(output).dy,
      closeTo(tester.getTopLeft(reasoning).dy, 0.5),
    );
    expect(
      tester.getTopLeft(output).dy,
      greaterThan(tester.getTopLeft(input).dy),
    );
    expect(
      tester.getTopLeft(input).dx,
      lessThan(tester.getTopLeft(cachedInput).dx),
    );
    expect(
      tester.getTopLeft(output).dx,
      lessThan(tester.getTopLeft(reasoning).dx),
    );

    // 每个单元格内标签靠左、数值靠右，两端对齐同一行。
    final inputLabel = _inPopover(find.text('输入'));
    expect(
      tester.getTopLeft(inputLabel).dx,
      lessThan(tester.getTopLeft(input).dx),
    );
    expect(
      tester.getCenter(inputLabel).dy,
      closeTo(tester.getCenter(input).dy, 1),
    );

    // 网格背景复用与套餐额度卡片一致的浅灰底 + 小圆角。
    final tokenSection = find.byKey(
      const ValueKey('agent-usage-token-section'),
    );
    final grid = find.descendant(
      of: tokenSection,
      matching: find.byType(DecoratedBox),
    );
    expect(grid, findsOneWidget);
    final decoration =
        tester.widget<DecoratedBox>(grid).decoration as BoxDecoration;
    final colors = IdeColors.of(tester.element(tokenSection));
    expect(decoration.color, colors.hoverSurface);
    expect(decoration.borderRadius, IdeRadius.allSmall);

    // 标签统一降级为次级灰色，数值保持深色并加粗。
    final inputLabelStyle = tester.widget<Text>(inputLabel).style;
    expect(inputLabelStyle?.color, colors.textSecondary);
    final inputValueStyle = tester.widget<Text>(input).style;
    expect(inputValueStyle?.color, colors.textPrimary);
    expect(inputValueStyle?.fontWeight, FontWeight.w700);

    expect(tester.takeException(), isNull);
  });

  testWidgets('目录到达即展示 Tabs，只有选中项按需显示加载动画', (tester) async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);
    await _pumpPanel(tester, controller);

    repository.directory.complete(_directoryFor(_usageEntries));
    await tester.pump();
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
      findsNothing,
    );
    expect(find.bySemanticsLabel('Codex Work，正在加载'), findsOneWidget);

    repository.requests.single.complete(_usageEntries.first);
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
      findsNothing,
    );

    await tester.tap(grokTab);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('agent-usage-provider-loading-grok-personal')),
      findsOneWidget,
    );
    // 无 entry 时用呼吸 Skeleton 占位，不再展示进度条文案。
    expect(_inPopover(find.bySemanticsLabel('正在读取 Agent 用量')), findsOneWidget);
    expect(find.textContaining('正在读取'), findsNothing);

    repository.requests.last.complete(_usageEntries.last);
    await tester.pump();
  });

  testWidgets('Provider Tabs 与右侧刷新操作保持同一行', (tester) async {
    final controller = AgentUsagePanelController(
      repository: _ImmediatePanelRepository(_usageEntries),
    );
    addTearDown(controller.dispose);
    await _pumpPanel(tester, controller, width: 420);

    final tabsCenter = tester.getCenter(find.byType(sf.Tabs));
    final refreshCenter = tester.getCenter(
      find.byKey(const ValueKey('agent-usage-refresh-button')),
    );

    expect(refreshCenter.dx, greaterThan(tabsCenter.dx));
    expect(refreshCenter.dy, closeTo(tabsCenter.dy, 1));
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
    expect(_inPopover(find.text('1.6K')), findsOneWidget);

    final refresh = controller.refresh();
    await tester.pump();
    // 有旧数据时不替换为 Skeleton，也不再展示顶栏进度条。
    expect(_inPopover(find.text('1.6K')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-usage-panel-loading')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('agent-usage-provider-loading-codex-work')),
      findsNothing,
    );

    repository.refreshResult.completeError(StateError('sensitive failure'));
    await refresh;
    await tester.pump();

    expect(_inPopover(find.text('1.6K')), findsOneWidget);
    expect(_inPopover(find.text('Agent 用量暂时无法读取')), findsOneWidget);
  });

  testWidgets('静默刷新保留旧内容且不展示加载 Skeleton', (tester) async {
    final repository = _RefreshPanelRepository(_usageEntries.first);
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);
    await _pumpPanel(tester, controller);
    expect(_inPopover(find.text('1.6K')), findsOneWidget);

    final refresh = controller.refresh(showLoading: false);
    await tester.pump();
    expect(_inPopover(find.text('1.6K')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-usage-panel-loading')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('agent-usage-provider-loading-codex-work')),
      findsNothing,
    );

    repository.refreshResult.complete(
      _panelResult(_usageEntries.first, DateTime(2026, 7, 21, 14)),
    );
    await refresh;
    await tester.pump();

    expect(_inPopover(find.text('1.6K')), findsOneWidget);
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
    expect(_inPopover(find.bySemanticsLabel('正在读取 Agent 用量')), findsOneWidget);
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
    expect(_inPopover(find.text('Agent 用量暂时无法读取')), findsOneWidget);

    await tester.tap(
      _inPopover(find.byKey(const ValueKey('agent-usage-retry-button'))),
    );
    await tester.pump();
    await tester.pump();

    expect(_inPopover(find.text('暂无已启用的 Agent')), findsOneWidget);
    expect(repository.discoverCount, 2);
  });

  testWidgets('plan-only 展开态隐藏套餐区，只保留 Token 统计', (tester) async {
    final controller = AgentUsagePanelController(
      repository: _ImmediatePanelRepository(const <AgentUsagePanelEntry>[
        AgentUsagePanelEntry(
          providerId: 'claude-code',
          providerName: 'Claude Code',
          todayTokens: UsageTokenBreakdown(totalTokens: 42),
          quota: AgentUsageQuotaSnapshot(
            providerId: 'claude-code',
            providerName: 'Claude Code',
            planType: 'Claude Pro',
            windows: <AgentUsageWindow>[],
          ),
        ),
      ]),
    );
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller);

    expect(
      find.byKey(const ValueKey('agent-usage-plan-section')),
      findsNothing,
    );
    expect(_inPopover(find.text('Claude Pro')), findsNothing);
    expect(_inPopover(find.text('额度详情暂不可用')), findsNothing);
    expect(find.byKey(const ValueKey('agent-usage-window-0')), findsNothing);
    expect(_inPopover(find.byType(sf.LinearProgressIndicator)), findsNothing);
    expect(_inPopover(find.text('0%')), findsNothing);
    expect(_inPopover(find.text('100%')), findsNothing);
    expect(
      _inPopover(find.byKey(const ValueKey('agent-usage-token-section'))),
      findsOneWidget,
    );
    expect(_inPopover(find.text('42')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Claude 套餐按 API 顺序展示通用及模型周窗口', (tester) async {
    final controller = AgentUsagePanelController(
      repository: const _ImmediatePanelRepository(<AgentUsagePanelEntry>[
        AgentUsagePanelEntry(
          providerId: 'claude-code',
          providerName: 'Claude Code',
          quota: AgentUsageQuotaSnapshot(
            providerId: 'claude-code',
            providerName: 'Claude Code',
            planType: 'Claude Max',
            windows: <AgentUsageWindow>[
              AgentUsageWindow(label: '5h', usedPercent: 10),
              AgentUsageWindow(label: '1 周', usedPercent: 20),
              AgentUsageWindow(label: 'Sonnet 1 周', usedPercent: 30),
              AgentUsageWindow(label: 'Opus 1 周', usedPercent: 40),
            ],
            credits: AgentUsageCredits(hasCredits: true, unlimited: true),
          ),
        ),
      ]),
    );
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller);

    expect(_inPopover(find.text('Claude Max')), findsOneWidget);
    expect(_inPopover(find.text('5h')), findsOneWidget);
    expect(_inPopover(find.text('1 周')), findsOneWidget);
    expect(_inPopover(find.text('Sonnet 1 周')), findsOneWidget);
    expect(_inPopover(find.text('Opus 1 周')), findsOneWidget);
    expect(
      _inPopover(find.byType(sf.LinearProgressIndicator)),
      findsNWidgets(4),
    );
    expect(find.text('额度详情暂不可用'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('额度卡片使用紧凑内边距和元信息重置时间样式', (tester) async {
    await _pumpQuotaWindows(tester, <AgentUsageWindow>[
      AgentUsageWindow(
        label: '5h',
        usedPercent: 25,
        resetsAt: DateTime.now().add(const Duration(hours: 2)),
      ),
    ]);

    final card = find.byKey(const ValueKey<String>('agent-usage-window-0'));
    final padding = find.descendant(of: card, matching: find.byType(Padding));
    expect(padding, findsOneWidget);
    expect(tester.widget<Padding>(padding).padding, IdeSpacing.all6);

    final metaStyle = IdeTextStyles.of(tester.element(card)).meta;
    final resetText = find.descendant(
      of: card,
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && widget.style == metaStyle,
      ),
    );
    expect(resetText, findsOneWidget);
  });

  test('套餐卡片宽度按窗口数量分配', () {
    expect(agentUsageQuotaCardWidth(viewportWidth: 200, windowCount: 1), 200);
    expect(
      agentUsageQuotaCardWidth(viewportWidth: 200, windowCount: 2),
      (200 - agentUsageQuotaGalleryGap) / 2,
    );
    expect(agentUsageQuotaCardWidth(viewportWidth: 200, windowCount: 3), 80);
    expect(agentUsageQuotaCardWidth(viewportWidth: 200, windowCount: 4), 80);
  });

  testWidgets('一套餐窗口占满画廊宽度', (tester) async {
    await _pumpQuotaWindows(tester, <AgentUsageWindow>[
      const AgentUsageWindow(label: '5 小时', usedPercent: 25),
    ]);
    _expectGalleryCardWidths(tester, windowCount: 1);
  });

  testWidgets('两套餐窗口各占一半并保留间距', (tester) async {
    await _pumpQuotaWindows(tester, <AgentUsageWindow>[
      const AgentUsageWindow(label: '5 小时', usedPercent: 25),
      const AgentUsageWindow(label: '1 周', usedPercent: 40),
    ]);
    _expectGalleryCardWidths(tester, windowCount: 2);
  });

  testWidgets('三套以上窗口各占 40% 且画廊高度固定', (tester) async {
    await _pumpQuotaWindows(tester, <AgentUsageWindow>[
      const AgentUsageWindow(label: '5h', usedPercent: 10),
      const AgentUsageWindow(label: '1 周', usedPercent: 20),
      const AgentUsageWindow(label: 'Sonnet 1 周', usedPercent: 30),
    ]);
    final threeHeight = _expectGalleryCardWidths(tester, windowCount: 3);

    await _pumpQuotaWindows(tester, <AgentUsageWindow>[
      const AgentUsageWindow(label: '5h', usedPercent: 10),
      const AgentUsageWindow(label: '1 周', usedPercent: 20),
      const AgentUsageWindow(label: 'Sonnet 1 周', usedPercent: 30),
      const AgentUsageWindow(label: 'Opus 1 周', usedPercent: 40),
    ]);
    final fourHeight = _expectGalleryCardWidths(tester, windowCount: 4);
    expect(fourHeight, threeHeight);
  });

  testWidgets('超过两张时 Hover 显示箭头并按卡片距离横滑', (tester) async {
    await _pumpQuotaWindows(tester, <AgentUsageWindow>[
      const AgentUsageWindow(label: '5h', usedPercent: 10),
      const AgentUsageWindow(label: '1 周', usedPercent: 20),
      const AgentUsageWindow(label: 'Sonnet 1 周', usedPercent: 30),
      const AgentUsageWindow(label: 'Opus 1 周', usedPercent: 40),
    ]);

    final gallery = find.byKey(const ValueKey('agent-usage-quota-gallery'));
    final next = find.byKey(const ValueKey('agent-usage-quota-next-button'));
    await _hoverAt(tester, tester.getCenter(gallery));
    expect(next, findsOneWidget);

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('agent-usage-quota-gallery-scroll')),
    );
    final controller = scrollView.controller!;
    expect(controller.offset, 0);

    await tester.tap(next);
    await tester.pump();
    await tester.pump(IdeMotion.durationNormal);

    final cardWidth = tester
        .getSize(find.byKey(const ValueKey<String>('agent-usage-window-0')))
        .width;
    expect(
      controller.offset,
      closeTo(cardWidth + agentUsageQuotaGalleryGap, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开态不展示零张或缺失的重置卡数量', (tester) async {
    final controller = AgentUsagePanelController(
      repository: const _ImmediatePanelRepository(<AgentUsagePanelEntry>[
        AgentUsagePanelEntry(
          providerId: 'provider-zero',
          providerName: 'Provider Zero',
          quota: AgentUsageQuotaSnapshot(
            providerId: 'provider-zero',
            providerName: 'Provider Zero',
            planType: 'plus',
            windows: <AgentUsageWindow>[],
            availableResetCreditCount: 0,
          ),
        ),
        AgentUsagePanelEntry(
          providerId: 'provider-missing',
          providerName: 'Provider Missing',
          quota: AgentUsageQuotaSnapshot(
            providerId: 'provider-missing',
            providerName: 'Provider Missing',
            planType: 'plus',
            windows: <AgentUsageWindow>[],
          ),
        ),
      ]),
    );
    addTearDown(controller.dispose);

    // 宽度需容纳弹层内的 Tabs 与开合、刷新操作，Tab 才不会被裁到操作区下方。
    await _pumpPanel(tester, controller, width: 420);

    expect(
      find.byKey(const ValueKey('agent-usage-reset-credit-count')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('agent-usage-tab-provider-missing')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('agent-usage-reset-credit-count')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('折叠态有套餐时显示图标、套餐、最短窗口与今日 Token 三行', (tester) async {
    const entry = AgentUsagePanelEntry(
      providerId: 'provider-paid',
      providerName: 'Provider Paid',
      todayTokens: UsageTokenBreakdown(totalTokens: 1600),
      quota: AgentUsageQuotaSnapshot(
        providerId: 'provider-paid',
        providerName: 'Provider Paid',
        planType: 'plus',
        availableResetCreditCount: 2,
        windows: <AgentUsageWindow>[
          AgentUsageWindow(
            label: '1 周',
            usedPercent: 40,
            windowDuration: Duration(days: 7),
          ),
          AgentUsageWindow(
            label: '5 小时',
            usedPercent: 25,
            windowDuration: Duration(hours: 5),
          ),
        ],
      ),
    );
    final controller = AgentUsagePanelController(
      repository: const _ImmediatePanelRepository(<AgentUsagePanelEntry>[
        entry,
      ]),
    );
    addTearDown(controller.dispose);
    AgentUsagePanelMode? requestedMode;

    await _pumpPanelContent(
      tester,
      controller,
      mode: AgentUsagePanelMode.collapsed,
      height: 104,
      onModeChanged: (mode) => requestedMode = mode,
    );

    expect(find.byType(PanelCard), findsNothing);
    expect(find.byType(AgentProviderIcon), findsOneWidget);
    expect(find.text('ChatGPT Plus'), findsOneWidget);
    expect(find.text('Provider Paid'), findsNothing);
    expect(
      find.byKey(const ValueKey('agent-usage-compact-quota')),
      findsOneWidget,
    );
    expect(find.text('5 小时'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('1 周'), findsNothing);
    expect(find.text('今日 Token'), findsOneWidget);
    expect(find.text('1.6K'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-usage-reset-credit-count')),
      findsNothing,
    );

    final header = find.byKey(const ValueKey('agent-usage-compact-header'));
    final quota = find.byKey(const ValueKey('agent-usage-compact-quota'));
    final tokens = find.byKey(const ValueKey('agent-usage-compact-tokens'));
    expect(tester.getTopLeft(header).dy, lessThan(tester.getTopLeft(quota).dy));
    expect(tester.getTopLeft(quota).dy, lessThan(tester.getTopLeft(tokens).dy));

    expect(_popover, findsNothing);

    await tester.tap(find.byKey(const ValueKey('agent-usage-expand-button')));
    expect(requestedMode, AgentUsagePanelMode.expanded);
    expect(tester.takeException(), isNull);
  });

  testWidgets('折叠态 plan-only 隐藏套餐行且不伪造进度', (tester) async {
    final controller = AgentUsagePanelController(
      repository: const _ImmediatePanelRepository(<AgentUsagePanelEntry>[
        AgentUsagePanelEntry(
          providerId: 'claude-code',
          providerName: 'Claude Code',
          todayTokens: UsageTokenBreakdown(totalTokens: 1600),
          quota: AgentUsageQuotaSnapshot(
            providerId: 'claude-code',
            providerName: 'Claude Code',
            planType: 'Claude Max',
            windows: <AgentUsageWindow>[],
          ),
        ),
      ]),
    );
    addTearDown(controller.dispose);

    await _pumpPanelContent(
      tester,
      controller,
      mode: AgentUsagePanelMode.collapsed,
      height: 104,
      onModeChanged: (_) {},
    );

    expect(find.text('Claude Max'), findsOneWidget);
    expect(find.text('额度详情暂不可用'), findsNothing);
    expect(
      find.byKey(const ValueKey('agent-usage-compact-quota-unavailable')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('agent-usage-compact-quota')),
      findsNothing,
    );
    expect(find.byType(sf.LinearProgressIndicator), findsNothing);
    expect(find.text('0%'), findsNothing);
    expect(find.text('100%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('折叠态无套餐时显示 Provider 与 Token 横线两行', (tester) async {
    final controller = AgentUsagePanelController(
      repository: const _ImmediatePanelRepository(<AgentUsagePanelEntry>[
        AgentUsagePanelEntry(
          providerId: 'provider-free',
          providerName: 'Provider Free',
        ),
      ]),
    );
    addTearDown(controller.dispose);

    await _pumpPanelContent(
      tester,
      controller,
      mode: AgentUsagePanelMode.collapsed,
      height: 80,
      onModeChanged: (_) {},
    );

    expect(find.byType(AgentProviderIcon), findsOneWidget);
    expect(find.text('Provider Free'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-usage-compact-quota')),
      findsNothing,
    );
    expect(find.text('今日 Token'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-usage-compact-token-value')),
      findsOneWidget,
    );
    expect(find.text('-'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('折叠态冷加载使用三行呼吸 Skeleton 并保留展开按钮', (tester) async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);
    AgentUsagePanelMode? requestedMode;

    await _pumpPanelContent(
      tester,
      controller,
      mode: AgentUsagePanelMode.collapsed,
      height: 88,
      onModeChanged: (mode) => requestedMode = mode,
    );

    expect(
      find.byKey(const ValueKey('agent-usage-compact-loading')),
      findsOneWidget,
    );
    expect(find.byType(IdeSkeletonLine), findsNWidgets(3));
    expect(find.bySemanticsLabel('正在读取 Agent 用量'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-usage-expand-button')),
      findsOneWidget,
    );
    expect(find.byType(sf.Progress), findsNothing);

    await tester.tap(find.byKey(const ValueKey('agent-usage-expand-button')));
    expect(requestedMode, AgentUsagePanelMode.expanded);
    expect(tester.takeException(), isNull);
  });

  testWidgets('折叠态 Provider 读取失败保持单行错误和重试入口', (tester) async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    await _pumpPanelContent(
      tester,
      controller,
      mode: AgentUsagePanelMode.collapsed,
      height: 88,
      onModeChanged: (_) {},
    );

    repository.directory.complete(const <AgentUsagePanelProvider>[
      AgentUsagePanelProvider(
        providerId: 'provider-error',
        providerName: 'Provider Error',
      ),
    ]);
    await tester.pump();
    await tester.pump();
    repository.requests.single.fail();
    await tester.pump();

    final errorText = find.text('Agent 用量暂时无法读取');
    expect(errorText, findsOneWidget);
    expect(tester.widget<Text>(errorText).maxLines, 1);
    expect(tester.widget<Text>(errorText).overflow, TextOverflow.ellipsis);
    expect(
      find.byKey(const ValueKey('agent-usage-retry-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('agent-usage-retry-button')));
    await tester.pump();

    expect(repository.requests, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('折叠态长文本在紧凑高度内省略且不溢出', (tester) async {
    const longName =
        'A very long provider display name that must stay inside the sidebar';
    final controller = AgentUsagePanelController(
      repository: const _ImmediatePanelRepository(<AgentUsagePanelEntry>[
        AgentUsagePanelEntry(
          providerId: 'provider-long',
          providerName: longName,
        ),
      ]),
    );
    addTearDown(controller.dispose);

    await _pumpPanelContent(
      tester,
      controller,
      mode: AgentUsagePanelMode.collapsed,
      width: 180,
      height: 80,
      onModeChanged: (_) {},
    );

    final title = tester.widget<Text>(
      find.byKey(const ValueKey('agent-usage-compact-title')),
    );
    expect(title.data, longName);
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开态在折叠摘要上方弹出 Popover 并保留摘要锚点', (tester) async {
    final controller = AgentUsagePanelController(
      repository: _ImmediatePanelRepository(_usageEntries),
    );
    addTearDown(controller.dispose);
    AgentUsagePanelMode? requestedMode;

    await _pumpPanelContent(
      tester,
      controller,
      mode: AgentUsagePanelMode.expanded,
      height: 520,
      onModeChanged: (mode) => requestedMode = mode,
    );

    expect(find.byType(PanelCard), findsNothing);
    expect(find.byType(Pane), findsNothing);
    expect(find.text('Agent 统计'), findsNothing);
    expect(_popover, findsOneWidget);

    // 摘要仍留在原位作为锚点，弹层整体位于摘要上方。
    final anchor = find.byKey(const ValueKey('agent-usage-compact'));
    expect(anchor, findsOneWidget);
    expect(
      tester.getBottomLeft(_popover).dy,
      lessThanOrEqualTo(tester.getTopLeft(anchor).dy),
    );

    // 弹层不占满左栏宽度：相对锚点左右各内缩 4。
    final anchorRect = tester.getRect(anchor);
    final popoverRect = tester.getRect(_popover);
    expect(popoverRect.left, closeTo(anchorRect.left + 4, 0.01));
    expect(popoverRect.right, closeTo(anchorRect.right - 4, 0.01));

    final tabs = find.byKey(const ValueKey('agent-usage-tabs'));
    final refresh = find.byKey(const ValueKey('agent-usage-refresh-button'));
    expect(_inPopover(tabs), findsOneWidget);
    expect(
      _inPopover(find.byKey(const ValueKey('agent-usage-collapse-button'))),
      findsNothing,
    );
    expect(_inPopover(refresh), findsOneWidget);
    expect(
      tester.getCenter(refresh).dx,
      greaterThan(tester.getTopRight(tabs).dx),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('agent-usage-tabs-toolbar')))
          .dy,
      greaterThanOrEqualTo(
        tester
            .getBottomLeft(
              find.byKey(const ValueKey('agent-usage-token-section')),
            )
            .dy,
      ),
    );
    // 折叠摘要自身不滚动；仅弹层正文在可用高度内滚动。
    expect(
      find.descendant(
        of: find.byType(AgentUsagePanelContent),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.vertical,
        ),
      ),
      findsNothing,
    );
    expect(
      _inPopover(
        find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.vertical,
        ),
      ),
      findsOneWidget,
    );
    expect(
      _inPopover(find.byKey(const ValueKey('agent-usage-plan-section'))),
      findsOneWidget,
    );
    expect(
      _inPopover(find.byKey(const ValueKey('agent-usage-token-section'))),
      findsOneWidget,
    );
    expect(_inPopover(find.text('5 小时')), findsOneWidget);
    expect(_inPopover(find.text('1.6K')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-usage-expand-button')));
    await tester.pumpAndSettle();
    expect(requestedMode, AgentUsagePanelMode.collapsed);
    expect(_popover, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开态点击摘要开合按钮请求折叠', (tester) async {
    final controller = AgentUsagePanelController(
      repository: _ImmediatePanelRepository(_usageEntries),
    );
    addTearDown(controller.dispose);
    AgentUsagePanelMode? requestedMode;

    await _pumpPanelContent(
      tester,
      controller,
      mode: AgentUsagePanelMode.expanded,
      height: 520,
      onModeChanged: (mode) => requestedMode = mode,
    );

    final toggle = find.byKey(const ValueKey('agent-usage-expand-button'));
    expect(
      tester
          .widget<Icon>(
            find.descendant(of: toggle, matching: find.byType(Icon)),
          )
          .icon,
      Icons.keyboard_arrow_down_rounded,
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(requestedMode, AgentUsagePanelMode.collapsed);
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开态点击弹层外部收敛回折叠态', (tester) async {
    final controller = AgentUsagePanelController(
      repository: _ImmediatePanelRepository(_usageEntries),
    );
    addTearDown(controller.dispose);
    AgentUsagePanelMode? requestedMode;

    await _pumpPanelContent(
      tester,
      controller,
      mode: AgentUsagePanelMode.expanded,
      height: 520,
      onModeChanged: (mode) => requestedMode = mode,
    );
    expect(_popover, findsOneWidget);

    await tester.tapAt(const Offset(160, 8));
    await tester.pumpAndSettle();

    expect(requestedMode, AgentUsagePanelMode.collapsed);
    expect(_popover, findsNothing);
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
      availableResetCreditCount: 2,
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

List<AgentUsagePanelProvider> _directoryFor(
  List<AgentUsagePanelEntry> entries,
) {
  return <AgentUsagePanelProvider>[
    for (final entry in entries)
      AgentUsagePanelProvider(
        providerId: entry.providerId,
        providerName: entry.providerName,
      ),
  ];
}

AgentUsagePanelProviderResult _panelResult(
  AgentUsagePanelEntry entry,
  DateTime refreshedAt,
) => AgentUsagePanelProviderResult(entry: entry, refreshedAt: refreshedAt);

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
        home: sf.Scaffold(
          // 统计区在真实左栏中贴底且横向撑满，弹层才有向上展开的空间与宽度。
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              AgentUsagePanelContent(
                controller: controller,
                mode: AgentUsagePanelMode.expanded,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await _settlePopover(tester);
}

/// 展开态弹层在帧末挂载，需再走一帧并跑完过渡。
Future<void> _settlePopover(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpPanelContent(
  WidgetTester tester,
  AgentUsagePanelController controller, {
  required AgentUsagePanelMode mode,
  required ValueChanged<AgentUsagePanelMode> onModeChanged,
  double width = 320,
  double height = 104,
}) async {
  unawaited(controller.refresh());
  tester.view
    ..physicalSize = Size(width, height)
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              AgentUsagePanelContent(
                controller: controller,
                mode: mode,
                onModeChanged: onModeChanged,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  if (mode == AgentUsagePanelMode.expanded) {
    await _settlePopover(tester);
  }
}

class _ImmediatePanelRepository implements AgentUsagePanelRepository {
  const _ImmediatePanelRepository(this.entries);

  final List<AgentUsagePanelEntry> entries;

  @override
  Future<List<AgentUsagePanelProvider>> discoverProviders() async =>
      _directoryFor(entries);

  @override
  Future<AgentUsagePanelProviderResult?> loadProvider(
    String providerId, {
    bool forceRefresh = false,
  }) async {
    final entry = entries
        .where((entry) => entry.providerId == providerId)
        .first;
    return _panelResult(entry, DateTime(2026, 7, 21, 12));
  }
}

class _ControlledPanelRepository implements AgentUsagePanelRepository {
  final Completer<List<AgentUsagePanelProvider>> directory =
      Completer<List<AgentUsagePanelProvider>>();
  final List<_PanelProviderRequest> requests = <_PanelProviderRequest>[];

  @override
  Future<List<AgentUsagePanelProvider>> discoverProviders() => directory.future;

  @override
  Future<AgentUsagePanelProviderResult?> loadProvider(
    String providerId, {
    bool forceRefresh = false,
  }) {
    final request = _PanelProviderRequest();
    requests.add(request);
    return request.result.future;
  }
}

class _RefreshPanelRepository implements AgentUsagePanelRepository {
  _RefreshPanelRepository(this.entry);

  final AgentUsagePanelEntry entry;
  var _loadCount = 0;
  late final Completer<AgentUsagePanelProviderResult?> refreshResult;

  @override
  Future<List<AgentUsagePanelProvider>> discoverProviders() async =>
      _directoryFor(<AgentUsagePanelEntry>[entry]);

  @override
  Future<AgentUsagePanelProviderResult?> loadProvider(
    String providerId, {
    bool forceRefresh = false,
  }) {
    _loadCount += 1;
    if (_loadCount == 1) {
      return Future<AgentUsagePanelProviderResult?>.value(
        _panelResult(entry, DateTime(2026, 7, 21, 12)),
      );
    }
    refreshResult = Completer<AgentUsagePanelProviderResult?>();
    return refreshResult.future;
  }
}

class _RetryRepository implements AgentUsagePanelRepository {
  var discoverCount = 0;

  @override
  Future<List<AgentUsagePanelProvider>> discoverProviders() async {
    discoverCount += 1;
    if (discoverCount == 1) {
      throw StateError('offline');
    }
    return const <AgentUsagePanelProvider>[];
  }

  @override
  Future<AgentUsagePanelProviderResult?> loadProvider(
    String providerId, {
    bool forceRefresh = false,
  }) async {
    fail('empty directory must not load a provider');
  }
}

final class _PanelProviderRequest {
  final Completer<AgentUsagePanelProviderResult?> result =
      Completer<AgentUsagePanelProviderResult?>();

  void complete(AgentUsagePanelEntry entry) {
    result.complete(_panelResult(entry, DateTime(2026, 8, 12)));
  }

  void fail() {
    result.completeError(StateError('sensitive provider failure'));
  }
}
