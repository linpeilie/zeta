import 'package:app_ui/app_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/helpers.dart';

Future<void> _pumpIdeComponent(
  WidgetTester tester, {
  required Widget child,
  required Size size,
}) => tester.pumpShadcnApp(child, size: size);

void main() {
  group('19.3 IdeVirtualScrollbar', () {
    testWidgets('scrollbar 与列表共用同一 controller', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await _pumpIdeComponent(
        tester,
        size: const Size(400, 500),
        child: IdeVirtualScrollbar(
          controller: controller,
          semanticLabel: 'Virtual content scrollbar',
          child: ListView.builder(
            controller: controller,
            itemCount: 40,
            itemBuilder: (context, index) =>
                SizedBox(height: 40, child: Text('row-$index')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.hasClients, isTrue);
      final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
      expect(identical(scrollbar.controller, controller), isTrue);
    });

    testWidgets('自动 scrollbar 被禁用，不出现双 thumb', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await _pumpIdeComponent(
        tester,
        size: const Size(400, 500),
        child: IdeVirtualScrollbar(
          controller: controller,
          semanticLabel: 'Virtual content scrollbar',
          child: ListView.builder(
            controller: controller,
            itemCount: 30,
            itemBuilder: (context, index) =>
                SizedBox(height: 50, child: Text('item-$index')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 仅一层项目包装的 RawScrollbar；自动 Material Scrollbar 被关闭。
      expect(find.byType(RawScrollbar), findsOneWidget);
      expect(find.byType(Scrollbar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(IdeVirtualScrollbar),
          matching: find.byType(ScrollConfiguration),
        ),
        findsWidgets,
      );
    });

    testWidgets('thumb 使用真实 ScrollMetrics 且可滚到头尾', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await _pumpIdeComponent(
        tester,
        size: const Size(360, 400),
        child: IdeVirtualScrollbar(
          controller: controller,
          semanticLabel: 'Virtual content scrollbar',
          child: ListView.builder(
            controller: controller,
            itemCount: 50,
            itemBuilder: (context, index) => SizedBox(
              key: ValueKey('r-$index'),
              height: 40,
              child: Text('r-$index'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final maxExtent = controller.position.maxScrollExtent;
      expect(maxExtent, greaterThan(100));

      // 总高度来自真实 child 高度累加，而不是 itemCount × 某个错误均值。
      // 50 × 40 - viewport ≈ maxScrollExtent。
      expect(
        maxExtent,
        closeTo(50 * 40 - controller.position.viewportDimension, 2.0),
      );

      controller.jumpTo(maxExtent);
      await tester.pumpAndSettle();
      expect(controller.position.pixels, closeTo(maxExtent, 1.0));
      expect(controller.position.extentAfter, closeTo(0, 1.0));

      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(controller.position.pixels, closeTo(0, 1.0));
      expect(controller.position.extentBefore, closeTo(0, 1.0));
    });

    testWidgets('thumb 仅消费 ScrollMetrics，不另建 itemCount 模型', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const itemCount = 40;
      const itemHeight = 40.0;

      await _pumpIdeComponent(
        tester,
        size: const Size(360, 400),
        child: IdeVirtualScrollbar(
          controller: controller,
          semanticLabel: 'Virtual content scrollbar',
          child: ListView.builder(
            controller: controller,
            itemExtent: itemHeight,
            itemCount: itemCount,
            itemBuilder: (context, index) =>
                SizedBox(height: itemHeight, child: Text('h-$index')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final before = controller.position.maxScrollExtent;
      expect(before, greaterThan(0));

      // 滚动中途 maxScrollExtent 保持稳定；scrollbar 不引入第二套高度模型。
      controller.jumpTo((before / 2).clamp(0, before));
      await tester.pumpAndSettle();
      expect(
        controller.position.maxScrollExtent,
        closeTo(before, 1.0),
        reason:
            'max jumped from $before to ${controller.position.maxScrollExtent}',
      );

      final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
      expect(identical(scrollbar.controller, controller), isTrue);
      expect(
        scrollbar.controller!.position.maxScrollExtent,
        controller.position.maxScrollExtent,
      );
    });

    testWidgets('hover/drag 使用主题令牌而非裸色值', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await _pumpIdeComponent(
        tester,
        size: const Size(400, 500),
        child: IdeVirtualScrollbar(
          controller: controller,
          semanticLabel: 'Virtual content scrollbar',
          child: ListView.builder(
            controller: controller,
            itemCount: 20,
            itemBuilder: (context, index) =>
                SizedBox(height: 40, child: Text('t-$index')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(IdeVirtualScrollbar));
      final colors = context.appColors;
      final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
      expect(scrollbar.thumbColor, colors.textTertiary.withValues(alpha: 0.22));
      expect(scrollbar.trackColor, Colors.transparent);
      expect(scrollbar.trackVisibility, isFalse);
      expect(scrollbar.radius, Radius.circular(context.appRadii.small));
    });

    testWidgets('semantics label 存在', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await _pumpIdeComponent(
        tester,
        size: const Size(400, 500),
        child: IdeVirtualScrollbar(
          controller: controller,
          semanticLabel: 'Agent 对话滚动条',
          child: ListView.builder(
            controller: controller,
            itemCount: 10,
            itemBuilder: (context, index) =>
                SizedBox(height: 40, child: Text('s-$index')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Agent 对话滚动条'), findsOneWidget);
    });

    testWidgets('窄 viewport 可操作', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await _pumpIdeComponent(
        tester,
        size: const Size(280, 360),
        child: IdeVirtualScrollbar(
          controller: controller,
          semanticLabel: 'Virtual content scrollbar',
          thickness: 6,
          minThumbLength: 28,
          child: ListView.builder(
            controller: controller,
            itemCount: 60,
            itemBuilder: (context, index) =>
                SizedBox(height: 36, child: Text('n-$index')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.position.maxScrollExtent, greaterThan(0));
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(controller.position.pixels, greaterThan(0));
    });

    testWidgets('滚到底部按钮语义与点击', (tester) async {
      var pressed = false;
      await _pumpIdeComponent(
        tester,
        size: const Size(400, 400),
        child: IdeScrollToEndButton(
          onPressed: () => pressed = true,
          semanticLabel: '滚动到对话底部',
          newContentLabel: '有新内容',
          backToBottomLabel: '回到底部',
          hasNewContent: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('有新内容'), findsOneWidget);
      // PaneInteractiveSurface 会把 semanticLabel 挂到合并语义节点上。
      expect(
        tester.getSemantics(find.byType(IdeScrollToEndButton)).label,
        contains('滚动到对话底部'),
      );
      await tester.tap(find.byType(IdeScrollToEndButton));
      expect(pressed, isTrue);
    });

    testWidgets('IdeVirtualScrollShell 组合 scrollbar 与按钮', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var toEnd = false;

      await _pumpIdeComponent(
        tester,
        size: const Size(400, 500),
        child: IdeVirtualScrollShell(
          controller: controller,
          scrollbarSemanticLabel: 'Conversation scrollbar',
          scrollToEndSemanticLabel: '滚动到对话底部',
          newContentLabel: '有新内容',
          backToBottomLabel: '回到底部',
          showScrollToEndButton: true,
          onScrollToEnd: () => toEnd = true,
          child: ListView.builder(
            controller: controller,
            itemCount: 25,
            itemBuilder: (context, index) =>
                SizedBox(height: 40, child: Text('shell-$index')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RawScrollbar), findsOneWidget);
      expect(find.byType(IdeScrollToEndButton), findsOneWidget);
      await tester.tap(find.byType(IdeScrollToEndButton));
      expect(toEnd, isTrue);
    });

    testWidgets('桌面滚轮连续增量累加到同一个平滑目标', (tester) async {
      final controller = IdeSmoothScrollController(
        smoothScrollingEnabled: true,
      );
      addTearDown(controller.dispose);

      await _pumpIdeComponent(
        tester,
        size: const Size(400, 500),
        child: IdeVirtualScrollbar(
          controller: controller,
          semanticLabel: 'Virtual content scrollbar',
          child: ListView.builder(
            controller: controller,
            itemCount: 80,
            itemBuilder: (context, index) =>
                SizedBox(height: 40, child: Text('smooth-$index')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final position = tester.getCenter(find.byType(ListView));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.offset, inExclusiveRange(0, 120));

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.offset, closeTo(240, 1));
    });

    testWidgets('ticker 暂停时滚轮回退为即时滚动', (tester) async {
      final controller = IdeSmoothScrollController();
      addTearDown(controller.dispose);

      await _pumpIdeComponent(
        tester,
        size: const Size(400, 500),
        child: TickerMode(
          enabled: false,
          child: IdeVirtualScrollbar(
            controller: controller,
            semanticLabel: 'Virtual content scrollbar',
            child: ListView.builder(
              controller: controller,
              itemCount: 80,
              itemBuilder: (context, index) =>
                  SizedBox(height: 40, child: Text('paused-$index')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(ListView)),
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pump();

      expect(controller.offset, closeTo(120, 1));
    });

    testWidgets('关闭动效时滚轮即时更新且拖拽保持原生', (tester) async {
      final controller = IdeSmoothScrollController();
      addTearDown(controller.dispose);

      await _pumpIdeComponent(
        tester,
        size: const Size(400, 500),
        child: ListView.builder(
          controller: controller,
          itemCount: 80,
          itemBuilder: (context, index) =>
              SizedBox(height: 40, child: Text('native-$index')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(ListView)),
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pump();
      expect(controller.offset, closeTo(120, 1));

      await tester.drag(find.byType(ListView), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(120));
    });
  });
}
