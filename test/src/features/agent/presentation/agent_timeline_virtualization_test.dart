import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/virtualization/ide_dynamic_sliver_list.dart';
import 'package:zeta/src/ui/core/virtualization/ide_virtual_item.dart';
import 'package:zeta/src/ui/core/virtualization/ide_virtual_list_controller.dart';

void main() {
  testWidgets('SliverList 首帧只构建视口内 item，滚动后回收首屏', (tester) async {
    final builtIds = <String>{};
    final items = <AgentTimelineViewportItem>[
      for (var i = 0; i < 100; i += 1) _footerItem('t$i'),
    ];
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await _pumpTimeline(
      tester,
      controller: controller,
      items: items,
      itemBuilder: (context, item) {
        builtIds.add(item.id);
        return _FixedHeightTile(label: item.id);
      },
    );

    // 600px 视口 / 80px item ≈ 8 + cache，应远小于 100。
    expect(builtIds.length, lessThan(30));
    expect(builtIds, contains('turn-footer-t0'));
    expect(builtIds, isNot(contains('turn-footer-t99')));

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(builtIds, contains('turn-footer-t99'));
    final visibleTiles = find.byType(_FixedHeightTile, skipOffstage: false);
    expect(visibleTiles.evaluate().length, lessThan(40));
  });

  testWidgets('findChildIndexCallback 保证 prepend 后 State 不串位', (tester) async {
    // 保持少量 item 全部位于视口内，避免回收干扰 State 断言。
    var items = <AgentTimelineViewportItem>[
      _footerItem('t1'),
      _footerItem('t2'),
      _footerItem('t3'),
    ];
    late StateSetter setHostState;

    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _TimelineHost(
        builder: (context, setState) {
          setHostState = setState;
          return _VirtualTimeline(
            items: items,
            itemBuilder: (context, item) => _StatefulNoteTile(
              key: ValueKey<String>(agentTimelineViewportItemKey(item)),
              label: item.id,
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    final stateT1 = tester.state<_StatefulNoteTileState>(
      find.byKey(const ValueKey<String>('timeline-viewport-turn-footer-t1')),
    );
    stateT1.note = 'anchor-t1';

    setHostState(() {
      items = <AgentTimelineViewportItem>[
        _footerItem('t0'),
        _footerItem('t1'),
        _footerItem('t2'),
        _footerItem('t3'),
      ];
    });
    await tester.pumpAndSettle();

    final stateAfter = tester.state<_StatefulNoteTileState>(
      find.byKey(const ValueKey<String>('timeline-viewport-turn-footer-t1')),
    );
    expect(stateAfter, same(stateT1));
    expect(stateAfter.note, 'anchor-t1');
    // 旧 index0 的 State 不应错误落到 t0 上。
    expect(find.text('turn-footer-t0:'), findsOneWidget);
    expect(find.text('turn-footer-t1:anchor-t1'), findsOneWidget);
  });

  testWidgets('19.5 IdeAnchoredDynamicSliverList 固定高度仍只构建视口+cache', (
    tester,
  ) async {
    final builtIds = <String>{};
    final items = <AgentTimelineViewportItem>[
      for (var i = 0; i < 100; i += 1) _footerItem('d$i'),
    ];
    final controller = ScrollController();
    final virtual = IdeVirtualListController();
    const epoch = IdeLayoutEpoch(
      crossAxisExtentInPhysicalPixels: 400,
      textScaleKey: 1.0,
      localeKey: 'zh',
      typographyEpoch: 1,
    );
    virtual.setItems([
      for (final item in items)
        IdeVirtualItemDescriptor(
          id: item.id,
          kind: 'turnFooter',
          layoutRevision: 1,
          estimatedExtent: 80,
        ),
    ], epoch: epoch);
    addTearDown(controller.dispose);

    await _pumpDynamicTimeline(
      tester,
      controller: controller,
      virtualListController: virtual,
      items: items,
      itemBuilder: (context, item) {
        builtIds.add(item.id);
        return _FixedHeightTile(label: item.id);
      },
    );

    expect(builtIds.length, lessThan(30));
    expect(virtual.totalExtent, closeTo(100 * 80, 1));
    final render = tester.renderObject<RenderIdeAnchoredDynamicSliverList>(
      find.byType(IdeAnchoredDynamicSliverList),
    );
    expect(render.geometry!.scrollExtent, closeTo(virtual.totalExtent, 1));
  });

  testWidgets('19.5 大幅动态高度：滚入后 total 只按单项 delta 变化', (tester) async {
    final items = <AgentTimelineViewportItem>[
      for (var i = 0; i < 40; i += 1) _footerItem('h$i'),
    ];
    final heights = List<double>.generate(40, (i) => i == 12 ? 400.0 : 50.0);
    final controller = ScrollController();
    final virtual = IdeVirtualListController();
    const epoch = IdeLayoutEpoch(
      crossAxisExtentInPhysicalPixels: 400,
      textScaleKey: 1.0,
      localeKey: 'zh',
      typographyEpoch: 1,
    );
    // 第 12 项 estimate 故意偏小。
    virtual.setItems([
      for (var i = 0; i < items.length; i++)
        IdeVirtualItemDescriptor(
          id: items[i].id,
          kind: 'turnFooter',
          layoutRevision: 1,
          estimatedExtent: 50,
        ),
    ], epoch: epoch);
    addTearDown(controller.dispose);

    await _pumpDynamicTimeline(
      tester,
      controller: controller,
      virtualListController: virtual,
      items: items,
      itemBuilder: (context, item) {
        final index = items.indexWhere((it) => it.id == item.id);
        return SizedBox(
          height: heights[index],
          width: double.infinity,
          child: Text(item.id),
        );
      },
    );

    final beforeAt12 = virtual.extentIndex.extentAt(12);
    final beforeTotal = virtual.totalExtent;
    controller.jumpTo(500);
    await tester.pumpAndSettle();

    final afterAt12 = virtual.extentIndex.extentAt(12);
    final afterTotal = virtual.totalExtent;
    expect(afterAt12, closeTo(400, 1));
    expect(afterTotal - beforeTotal, closeTo(afterAt12 - beforeAt12, 1));
  });
}

Future<void> _pumpDynamicTimeline(
  WidgetTester tester, {
  required List<AgentTimelineViewportItem> items,
  required Widget Function(BuildContext, AgentTimelineViewportItem) itemBuilder,
  required IdeVirtualListController virtualListController,
  ScrollController? controller,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _TimelineHost(
      builder: (context, setState) {
        return CustomScrollView(
          key: const ValueKey('agent-message-list'),
          controller: controller,
          slivers: [
            IdeAnchoredDynamicSliverList(
              controller: virtualListController,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = items[index];
                  final child = itemBuilder(context, item);
                  if (child.key != null) {
                    return child;
                  }
                  return KeyedSubtree(
                    key: ValueKey<String>(agentTimelineViewportItemKey(item)),
                    child: child,
                  );
                },
                childCount: items.length,
                findChildIndexCallback: (Key key) {
                  if (key is! ValueKey<String>) {
                    return null;
                  }
                  final value = key.value;
                  const prefix = 'timeline-viewport-';
                  if (!value.startsWith(prefix)) {
                    return null;
                  }
                  final id = value.substring(prefix.length);
                  final index = items.indexWhere((item) => item.id == id);
                  return index >= 0 ? index : null;
                },
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
              ),
            ),
          ],
        );
      },
    ),
  );
  await tester.pumpAndSettle();
}

AgentTurnFooterViewportItem _footerItem(String turnId) {
  return AgentTurnFooterViewportItem(
    turn: AgentConversationTurnGroup(
      id: turnId,
      status: AgentHistoryTurnStatus.completed,
      isStandby: false,
      entries: const <AgentTimelineEntry>[],
    ),
    isLive: false,
  );
}

Future<void> _pumpTimeline(
  WidgetTester tester, {
  required List<AgentTimelineViewportItem> items,
  required Widget Function(BuildContext, AgentTimelineViewportItem) itemBuilder,
  ScrollController? controller,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _TimelineHost(
      builder: (context, setState) {
        return _VirtualTimeline(
          items: items,
          itemBuilder: itemBuilder,
          controller: controller,
        );
      },
    ),
  );
  await tester.pump();
}

class _TimelineHost extends StatelessWidget {
  const _TimelineHost({required this.builder});

  final Widget Function(BuildContext context, StateSetter setState) builder;

  @override
  Widget build(BuildContext context) {
    final light = buildIdeThemeData(
      brightness: Brightness.light,
      uiFontFamily: 'JetBrainsMono',
      codeFontFamily: 'JetBrainsMono',
    );
    final dark = buildIdeThemeData(
      brightness: Brightness.dark,
      uiFontFamily: 'JetBrainsMono',
      codeFontFamily: 'JetBrainsMono',
    );
    return IdeThemeScope(
      themeMode: ThemeMode.dark,
      lightTheme: light,
      darkTheme: dark,
      child: sf.ShadcnApp(
        locale: ZetaLocalization.simplifiedChinese,
        supportedLocales: ZetaLocalization.supportedLocales,
        localizationsDelegates: ZetaLocalization.delegates,
        theme: buildShadcnTheme(light),
        darkTheme: buildShadcnTheme(dark),
        materialTheme: buildMaterialTheme(dark),
        themeMode: sf.ThemeMode.dark,
        home: sf.Scaffold(
          child: StatefulBuilder(
            builder: (context, setState) => builder(context, setState),
          ),
        ),
      ),
    );
  }
}

/// 与生产时间线同构的 turn 级 SliverList，用于验证虚拟化行为。
class _VirtualTimeline extends StatelessWidget {
  const _VirtualTimeline({
    required this.items,
    required this.itemBuilder,
    this.controller,
  });

  final List<AgentTimelineViewportItem> items;
  final Widget Function(BuildContext, AgentTimelineViewportItem) itemBuilder;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const ValueKey('agent-message-list'),
      controller: controller,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                final child = itemBuilder(context, item);
                // 若 itemBuilder 已带稳定 key，则不再包 KeyedSubtree。
                if (child.key != null) {
                  return child;
                }
                return KeyedSubtree(
                  key: ValueKey<String>(agentTimelineViewportItemKey(item)),
                  child: child,
                );
              },
              childCount: items.length,
              findChildIndexCallback: (Key key) {
                if (key is! ValueKey<String>) {
                  return null;
                }
                final value = key.value;
                const prefix = 'timeline-viewport-';
                if (!value.startsWith(prefix)) {
                  return null;
                }
                final id = value.substring(prefix.length);
                final index = items.indexWhere((item) => item.id == id);
                return index >= 0 ? index : null;
              },
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _FixedHeightTile extends StatelessWidget {
  const _FixedHeightTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      width: double.infinity,
      child: ColoredBox(
        color: Colors.blueGrey,
        child: Center(child: Text(label)),
      ),
    );
  }
}

class _StatefulNoteTile extends StatefulWidget {
  const _StatefulNoteTile({required this.label, super.key});

  final String label;

  @override
  State<_StatefulNoteTile> createState() => _StatefulNoteTileState();
}

class _StatefulNoteTileState extends State<_StatefulNoteTile> {
  String note = '';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      width: double.infinity,
      child: Center(child: Text('${widget.label}:$note')),
    );
  }
}
