import 'package:app_ui/app_ui.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent, SliverGeometry;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const epoch = IdeLayoutEpoch(
    crossAxisExtentInPhysicalPixels: 400,
    textScaleKey: 1.0,
    localeKey: 'zh',
    typographyEpoch: 1,
  );

  const pattern = <double>[24, 80, 2000, 32, 600, 48];

  double patternHeight(int index) => pattern[index % pattern.length];

  group('19.2 IdeAnchoredDynamicSliverList', () {
    testWidgets('首帧只构建 viewport/cache item，不全量 build', (tester) async {
      final built = <String>{};
      final items = List<_Item>.generate(
        2000,
        (i) => _Item(id: 'i-$i', height: patternHeight(i)),
      );
      final harness = _Harness(items: items, epoch: epoch, onBuild: built.add);

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      expect(built.length, lessThan(100), reason: 'built=${built.length}');
      expect(built.length, greaterThan(0));
      expect(harness.controller.totalExtent, greaterThan(0));
    });

    testWidgets('max extent / scrollExtent 等于 extent index totalExtent', (
      tester,
    ) async {
      final items = List<_Item>.generate(
        80,
        (i) => _Item(id: 'i-$i', height: patternHeight(i)),
      );
      final harness = _Harness(items: items, epoch: epoch);

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      final render = tester.renderObject<RenderIdeAnchoredDynamicSliverList>(
        find.byType(IdeAnchoredDynamicSliverList),
      );
      expect(
        render.geometry!.scrollExtent,
        closeTo(harness.controller.totalExtent, 1.0),
      );
      expect(harness.controller.totalExtent, closeTo(_sumHeights(items), 1.0));
      // maxScrollExtent ≈ content - viewport，不是 totalExtent 本身。
      final position = _position(tester);
      expect(
        position.maxScrollExtent,
        closeTo(
          harness.controller.totalExtent - position.viewportDimension,
          2.0,
        ),
      );
    });

    testWidgets('滚入新项后总 extent 只按该项误差变化', (tester) async {
      final items = List<_Item>.generate(
        40,
        (i) => _Item(id: 'i-$i', height: i == 15 ? 400 : 50),
      );
      final harness = _Harness(
        items: items,
        epoch: epoch,
        // 第 15 项 estimate 故意偏小。
        estimateFor: (item, index) => index == 15 ? 50.0 : item.height,
      );

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      final before = harness.controller.totalExtent;
      final beforeAt15 = harness.controller.extentIndex.extentAt(15);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();

      final afterAt15 = harness.controller.extentIndex.extentAt(15);
      final after = harness.controller.totalExtent;
      if ((afterAt15 - beforeAt15).abs() > 0.5) {
        expect(after - before, closeTo(afterAt15 - beforeAt15, 1.0));
      }
      expect(afterAt15, closeTo(400, 1.0));
    });

    testWidgets('anchor 前 item 增高后，anchor 屏幕坐标变化 ≤ 1px', (tester) async {
      final items = List<_Item>.generate(
        30,
        (i) => _Item(id: 'i-$i', height: 40),
      );
      final harness = _Harness(items: items, epoch: epoch);

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      harness.scrollController.jumpTo(320);
      await tester.pumpAndSettle();

      const anchorId = 'i-10';
      final scrollView = find.byType(CustomScrollView);
      final topBefore = _itemViewportTop(tester, scrollView, anchorId);

      harness.updateItems([
        for (var i = 0; i < items.length; i++)
          if (i == 5) items[i].copyWith(height: 140, revision: 2) else items[i],
      ]);
      await tester.pumpAndSettle();

      final topAfter = _itemViewportTop(tester, scrollView, anchorId);
      expect(
        (topAfter - topBefore).abs(),
        lessThanOrEqualTo(1.0),
        reason:
            'before=$topBefore after=$topAfter '
            'pixels=${_position(tester).pixels}',
      );
    });

    testWidgets('anchor 后 item 增高后，scroll pixels 不变', (tester) async {
      final items = List<_Item>.generate(
        30,
        (i) => _Item(id: 'i-$i', height: 40),
      );
      final harness = _Harness(items: items, epoch: epoch);

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      harness.scrollController.jumpTo(200);
      await tester.pumpAndSettle();
      final pixelsBefore = _position(tester).pixels;

      harness.updateItems([
        for (var i = 0; i < items.length; i++)
          if (i == 25)
            items[i].copyWith(height: 300, revision: 2)
          else
            items[i],
      ]);
      await tester.pumpAndSettle();

      expect(_position(tester).pixels, closeTo(pixelsBefore, 1.0));
    });

    testWidgets('prepend 后原首屏 item 屏幕坐标不变', (tester) async {
      final items = List<_Item>.generate(
        20,
        (i) => _Item(id: 'i-$i', height: 50),
      );
      final harness = _Harness(items: items, epoch: epoch);

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      const trackedId = 'i-0';
      final scrollView = find.byType(CustomScrollView);
      final topBefore = _itemViewportTop(tester, scrollView, trackedId);

      harness.updateItems([
        for (var i = 0; i < 5; i++) _Item(id: 'p-$i', height: 40),
        ...harness.items,
      ]);
      await tester.pumpAndSettle();

      final topAfter = _itemViewportTop(tester, scrollView, trackedId);
      expect((topAfter - topBefore).abs(), lessThanOrEqualTo(1.0));
    });

    testWidgets('remove 锚点后 fallback 保持可读位置', (tester) async {
      final items = List<_Item>.generate(
        20,
        (i) => _Item(id: 'i-$i', height: 40),
      );
      final harness = _Harness(items: items, epoch: epoch);

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      harness.scrollController.jumpTo(200);
      await tester.pumpAndSettle();

      harness.updateItems([
        for (final item in harness.items)
          if (item.id != 'i-5') item,
      ]);
      await tester.pumpAndSettle();

      expect(harness.controller.indexOfId('i-5'), isNull);
      expect(harness.controller.indexOfId('i-6'), isNotNull);
      expect(_position(tester).pixels.isFinite, isTrue);
      expect(find.text('i-6'), findsOneWidget);
    });

    testWidgets('reorder 后 anchor ID 视口位置保持', (tester) async {
      final items = List<_Item>.generate(
        40,
        (i) => _Item(id: 'i-$i', height: 40),
      );
      final harness = _Harness(items: items, epoch: epoch);

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      // 总高 1600 > viewport 600，可稳定跳到中间。
      harness.scrollController.jumpTo(200);
      await tester.pumpAndSettle();

      const anchorId = 'i-8';
      final scrollView = find.byType(CustomScrollView);
      final topBefore = _itemViewportTop(tester, scrollView, anchorId);
      expect(_position(tester).pixels, closeTo(200, 1.0));

      final current = harness.items;
      harness.updateItems([...current.skip(3), ...current.take(3)]);
      await tester.pumpAndSettle();

      final topAfter = _itemViewportTop(tester, scrollView, anchorId);
      expect(
        (topAfter - topBefore).abs(),
        lessThanOrEqualTo(1.0),
        reason:
            'before=$topBefore after=$topAfter '
            'pixels=${_position(tester).pixels}',
      );
    });

    testWidgets('连续 0 高度项不会卡死', (tester) async {
      final items = <_Item>[
        const _Item(id: 'z0', height: 0),
        const _Item(id: 'z1', height: 0),
        const _Item(id: 'body', height: 120),
        const _Item(id: 'z2', height: 0),
        const _Item(id: 'tail', height: 40),
        for (var i = 0; i < 30; i++) _Item(id: 'r-$i', height: 50),
      ];
      final harness = _Harness(items: items, epoch: epoch);

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      expect(find.text('body'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(_position(tester).pixels.isFinite, isTrue);
    });

    testWidgets('correction 不产生无限 pump', (tester) async {
      final items = List<_Item>.generate(
        25,
        (i) => _Item(id: 'i-$i', height: 40),
      );
      final harness = _Harness(items: items, epoch: epoch);

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      harness.scrollController.jumpTo(120);
      await tester.pumpAndSettle();

      harness.updateItems([
        for (var i = 0; i < harness.items.length; i++)
          if (i == 1)
            harness.items[i].copyWith(height: 200, revision: 2)
          else
            harness.items[i],
      ]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_position(tester).pixels.isFinite, isTrue);
    });

    testWidgets('feature flag 可回退到普通 SliverList', (tester) async {
      final controller = IdeVirtualListController();
      final items = List<_Item>.generate(
        10,
        (i) => _Item(id: 'i-$i', height: 40),
      );
      controller.synchronizeNow(_descriptors(items), epoch: epoch);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                buildIdeVirtualSliver(
                  useAnchoredDynamic: false,
                  controller: controller,
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => SizedBox(
                      key: ValueKey(items[index].id),
                      height: items[index].height,
                      child: Text(items[index].id),
                    ),
                    childCount: items.length,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SliverList), findsOneWidget);
      expect(find.byType(IdeAnchoredDynamicSliverList), findsNothing);
    });

    testWidgets('geometry.scrollExtent 跟踪 index.totalExtent', (tester) async {
      final items = List<_Item>.generate(
        12,
        (i) => _Item(id: 'i-$i', height: patternHeight(i)),
      );
      final harness = _Harness(items: items, epoch: epoch);

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      final render = tester.renderObject<RenderIdeAnchoredDynamicSliverList>(
        find.byType(IdeAnchoredDynamicSliverList),
      );
      expect(
        render.geometry!.scrollExtent,
        closeTo(harness.controller.totalExtent, 0.5),
      );
    });

    test('anchored builder and extent estimation use the index', () {
      final populated = IdeVirtualListController()
        ..synchronizeNow(
          <IdeVirtualItemDescriptor>[
            const IdeVirtualItemDescriptor(
              id: 'a',
              kind: 'row',
              layoutRevision: 1,
              estimatedExtent: 40,
            ),
            const IdeVirtualItemDescriptor(
              id: 'b',
              kind: 'row',
              layoutRevision: 1,
              estimatedExtent: 60,
            ),
          ],
          epoch: epoch,
        );
      final delegate = SliverChildBuilderDelegate(
        (_, index) => SizedBox(height: index == 0 ? 40 : 60),
        childCount: 2,
      );
      final anchored = buildIdeVirtualSliver(
        useAnchoredDynamic: true,
        controller: populated,
        delegate: delegate,
      ) as IdeAnchoredDynamicSliverList;
      expect(anchored.estimateMaxScrollOffset(null, 0, 1, 0, 100), 100);

      final empty = IdeAnchoredDynamicSliverList(
        controller: IdeVirtualListController(),
        delegate: delegate,
      );
      expect(empty.estimateMaxScrollOffset(null, 0, 1, 0, 100), isNull);
    });

    testWidgets(
      'render object updates its controller and supports empty data',
      (
        tester,
      ) async {
        final first = IdeVirtualListController()
          ..synchronizeNow(<IdeVirtualItemDescriptor>[
            _descriptor('first'),
          ], epoch: epoch);
        final second = IdeVirtualListController()
          ..synchronizeNow(<IdeVirtualItemDescriptor>[
            _descriptor('second'),
          ], epoch: epoch);
        var active = first;
        late StateSetter rebuild;

        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return CustomScrollView(
                  slivers: <Widget>[
                    IdeAnchoredDynamicSliverList(
                      controller: active,
                      delegate: SliverChildBuilderDelegate(
                        (_, index) => const SizedBox(height: 40),
                        childCount: active.itemCount,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        var render = tester.renderObject<RenderIdeAnchoredDynamicSliverList>(
          find.byType(IdeAnchoredDynamicSliverList),
        );
        expect(render.controller, same(first));

        active = second;
        rebuild(() {});
        await tester.pumpAndSettle();
        render = tester.renderObject<RenderIdeAnchoredDynamicSliverList>(
          find.byType(IdeAnchoredDynamicSliverList),
        );
        expect(render.controller, same(second));

        active = IdeVirtualListController();
        rebuild(() {});
        await tester.pumpAndSettle();
        expect(
          tester
              .renderObject<RenderIdeAnchoredDynamicSliverList>(
                find.byType(IdeAnchoredDynamicSliverList, skipOffstage: false),
              )
              .geometry,
          SliverGeometry.zero,
        );
      },
    );

    testWidgets('missing delegate child returns finite empty geometry', (
      tester,
    ) async {
      final controller = IdeVirtualListController()
        ..synchronizeNow(<IdeVirtualItemDescriptor>[
          _descriptor('missing'),
        ], epoch: epoch);
      await tester.pumpWidget(
        MaterialApp(
          home: CustomScrollView(
            slivers: <Widget>[
              IdeAnchoredDynamicSliverList(
                controller: controller,
                delegate: SliverChildBuilderDelegate(
                  (_, _) => null,
                  childCount: 1,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final geometry = tester
          .renderObject<RenderIdeAnchoredDynamicSliverList>(
            find.byType(IdeAnchoredDynamicSliverList, skipOffstage: false),
          )
          .geometry!;
      expect(geometry.scrollExtent, 40);
      expect(geometry.maxPaintExtent, 40);
    });

    testWidgets('underestimated visible range expands and later collects', (
      tester,
    ) async {
      final items = List<_Item>.generate(
        100,
        (index) => _Item(id: 'expand-$index', height: 10),
      );
      final harness = _Harness(
        items: items,
        epoch: epoch,
        estimateFor: (_, _) => 200,
      );
      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();
      expect(harness.controller.debugLaidOutChildCount, greaterThan(3));

      harness.updateItems(<_Item>[
        for (var index = 0; index < items.length; index++)
          items[index].copyWith(
            height: index < 20 ? 120 : 10,
            revision: 2,
          ),
      ]);
      await tester.pumpAndSettle();
      expect(harness.controller.debugLaidOutChildCount, lessThanOrEqualTo(100));
    });
  });
}

IdeVirtualItemDescriptor _descriptor(String id) => IdeVirtualItemDescriptor(
  id: id,
  kind: 'row',
  layoutRevision: 1,
  estimatedExtent: 40,
);

@immutable
final class _Item {
  const _Item({required this.id, required this.height, this.revision = 1});

  final String id;
  final double height;
  final int revision;

  _Item copyWith({double? height, int? revision}) {
    return _Item(
      id: id,
      height: height ?? this.height,
      revision: revision ?? this.revision,
    );
  }
}

List<IdeVirtualItemDescriptor> _descriptors(
  List<_Item> items, {
  double Function(_Item item, int index)? estimateFor,
}) {
  return [
    for (var i = 0; i < items.length; i++)
      IdeVirtualItemDescriptor(
        id: items[i].id,
        kind: 'block',
        layoutRevision: items[i].revision,
        estimatedExtent: estimateFor?.call(items[i], i) ?? items[i].height,
      ),
  ];
}

double _sumHeights(List<_Item> items) {
  var sum = 0.0;
  for (final item in items) {
    sum += item.height;
  }
  return sum;
}

final class _Harness extends StatefulWidget {
  _Harness({
    required List<_Item> items,
    required this.epoch,
    this.onBuild,
    this.estimateFor,
  }) : initialItems = List<_Item>.of(items),
       controller = IdeVirtualListController(),
       scrollController = ScrollController(),
       super(key: GlobalKey<_HarnessState>());

  final List<_Item> initialItems;
  final IdeLayoutEpoch epoch;
  final void Function(String id)? onBuild;
  final double Function(_Item item, int index)? estimateFor;
  final IdeVirtualListController controller;
  final ScrollController scrollController;

  GlobalKey<_HarnessState> get stateKey => key! as GlobalKey<_HarnessState>;

  List<_Item> get items => stateKey.currentState?.items ?? initialItems;

  void updateItems(List<_Item> next) {
    stateKey.currentState!.updateItems(next);
  }

  @override
  State<_Harness> createState() => _HarnessState();
}

final class _HarnessState extends State<_Harness> {
  late List<_Item> items;

  @override
  void initState() {
    super.initState();
    items = List<_Item>.of(widget.initialItems);
    widget.controller.setItems(
      _descriptors(items, estimateFor: widget.estimateFor),
      epoch: widget.epoch,
    );
  }

  @override
  void dispose() {
    widget.scrollController.dispose();
    super.dispose();
  }

  void updateItems(List<_Item> next) {
    setState(() {
      items = List<_Item>.of(next);
      widget.controller.setItems(
        _descriptors(items, estimateFor: widget.estimateFor),
        epoch: widget.epoch,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final idToIndex = <String, int>{
      for (var i = 0; i < items.length; i++) items[i].id: i,
    };
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: CustomScrollView(
            controller: widget.scrollController,
            scrollCacheExtent: const ScrollCacheExtent.pixels(250),
            slivers: [
              IdeAnchoredDynamicSliverList(
                controller: widget.controller,
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = items[index];
                    widget.onBuild?.call(item.id);
                    return SizedBox(
                      key: ValueKey<String>(item.id),
                      height: item.height,
                      width: double.infinity,
                      child: Text(item.id),
                    );
                  },
                  childCount: items.length,
                  findChildIndexCallback: (key) {
                    if (key is ValueKey<String>) {
                      return idToIndex[key.value];
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

ScrollPosition _position(WidgetTester tester) {
  final scrollable = find.byType(Scrollable);
  return tester.state<ScrollableState>(scrollable).position;
}

double _itemViewportTop(WidgetTester tester, Finder scrollView, String id) {
  final viewportTop = tester.getRect(scrollView).top;
  final itemTop = tester.getRect(find.byKey(ValueKey<String>(id))).top;
  return itemTop - viewportTop;
}
