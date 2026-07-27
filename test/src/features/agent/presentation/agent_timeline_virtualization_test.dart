import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';
import 'package:zeta/src/ui/core/app_theme.dart';

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
    expect(builtIds, contains('history-footer-t0'));
    expect(builtIds, isNot(contains('history-footer-t99')));

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(builtIds, contains('history-footer-t99'));
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
      find.byKey(const ValueKey<String>('timeline-viewport-history-footer-t1')),
    );
    stateT1.note = 'anchor-t1';

    setHostState(() {
      items = <AgentTimelineViewportItem>[
        const AgentLoadOlderViewportItem(),
        _footerItem('t0'),
        _footerItem('t1'),
        _footerItem('t2'),
        _footerItem('t3'),
      ];
    });
    await tester.pumpAndSettle();

    final stateAfter = tester.state<_StatefulNoteTileState>(
      find.byKey(const ValueKey<String>('timeline-viewport-history-footer-t1')),
    );
    expect(stateAfter, same(stateT1));
    expect(stateAfter.note, 'anchor-t1');
    // 旧 index0 的 State 不应错误落到 load-older 或 t0 上。
    expect(find.text('history-footer-t0:'), findsOneWidget);
    expect(find.text('history-footer-t1:anchor-t1'), findsOneWidget);
  });
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
