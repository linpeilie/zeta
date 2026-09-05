@Tags(['slow', 'perf'])
library;

import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_ui/zeta_ui.dart';

import '../../../../support/scroll_metrics_trace.dart';

/// 阶段 5 / 详设 19.6：2,000 项混合高度性能与稳定性回归。
///
/// 与阶段 0 场景 A 对照：新路径在滚入极高项时，maxScrollExtent 不得再因
/// “新均值 × 剩余项”发生数十万像素的跳变。
void main() {
  const itemCount = 2000;
  const coldEstimate = 50.0;
  const epoch = IdeLayoutEpoch(
    crossAxisExtentInPhysicalPixels: 400,
    textScaleKey: 1.0,
    localeKey: 'zh',
    typographyEpoch: 1,
  );

  testWidgets('19.6 混合高度 2000 项：虚拟化 + 无全局平均放大', (tester) async {
    final stopwatch = Stopwatch()..start();
    final builtIds = <String>{};
    final controller = ScrollController();
    final virtual = IdeVirtualListController()..resetDebugMetrics();
    addTearDown(controller.dispose);

    // 冷启动统一 estimate；真实高度沿用阶段 0 混合模式。
    virtual.setItems([
      for (var i = 0; i < itemCount; i++)
        IdeVirtualItemDescriptor(
          id: 'perf-$i',
          kind: _kindForIndex(i),
          layoutRevision: 1,
          estimatedExtent: coldEstimate,
        ),
    ], epoch: epoch);

    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;

    const scrollKey = ValueKey<String>('perf-mixed-scroll');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            key: scrollKey,
            controller: controller,
            slivers: [
              IdeAnchoredDynamicSliverList(
                controller: virtual,
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final id = 'perf-$index';
                    builtIds.add(id);
                    return SizedBox(
                      key: ValueKey<String>(id),
                      height: _mixedExtent(index),
                      width: double.infinity,
                      child: Text(id),
                    );
                  },
                  childCount: itemCount,
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<String>) {
                      return null;
                    }
                    final id = key.value;
                    if (!id.startsWith('perf-')) {
                      return null;
                    }
                    return int.tryParse(id.substring(5));
                  },
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final initialPumpMs = stopwatch.elapsedMilliseconds;

    final trace = ScrollMetricsTrace('perf-A');
    final scrollView = find.byKey(scrollKey);
    final initial = trace.capture(
      tester,
      label: 'initial',
      scrollView: scrollView,
      itemKeyPrefix: 'perf-',
    );

    // --- 与阶段 0 对照：首帧必须保持虚拟化 ---
    expect(builtIds.length, lessThan(100), reason: 'built=${builtIds.length}');
    expect(initial.builtChildCount, lessThan(100), reason: '$initial');
    expect(virtual.extentIndex.length, itemCount);
    // 首帧会测 viewport/cache 内项，total 可略偏离纯 estimate 总和，
    // 但绝不能变成“全量真实高度”或被均值放大。
    final pureEstimateTotal = itemCount * coldEstimate;
    expect(
      (virtual.totalExtent - pureEstimateTotal).abs(),
      lessThan(20_000),
      reason:
          '首帧 total=${virtual.totalExtent} estimateTotal=$pureEstimateTotal',
    );

    // geometry 与 index total 对齐。
    final render = tester.renderObject<RenderIdeAnchoredDynamicSliverList>(
      find.byType(IdeAnchoredDynamicSliverList),
    );
    expect(render.geometry!.scrollExtent, closeTo(virtual.totalExtent, 1));

    final maxAfterInitial = controller.position.maxScrollExtent;
    controller.jumpTo(1800);
    await tester.pump();
    final beforeExtreme = trace.capture(
      tester,
      label: 'before-extreme',
      scrollView: scrollView,
      itemKeyPrefix: 'perf-',
    );

    controller.jumpTo(2600);
    await tester.pump();
    final afterExtreme = trace.capture(
      tester,
      label: 'after-extreme',
      scrollView: scrollView,
      itemKeyPrefix: 'perf-',
    );

    final maxDelta =
        afterExtreme.maxScrollExtent - beforeExtreme.maxScrollExtent;

    // 阶段 0：max 从 ~105k 跳到 ~344k（+239k）。新路径应远小于此。
    // 允许已布局窗口内多项实测累计（cache 内若干项），但禁止“均值×剩余项”。
    expect(
      maxDelta.abs(),
      lessThan(25_000),
      reason:
          '滚入极高项时 maxScrollExtent 不得再被全局平均放大：'
          'delta=$maxDelta before=$beforeExtreme after=$afterExtreme '
          'phase0~239043',
    );

    // 若 total 已稳定为 index 真源，normalized 不应在内容前进时大幅反降。
    // 允许小幅波动，但不允许阶段 0 那种 0.017→0.007 级别的反向跳变伴随巨大 max 增长。
    if (maxDelta.abs() > 1) {
      final normalizedDrop =
          beforeExtreme.normalizedOffset - afterExtreme.normalizedOffset;
      expect(
        normalizedDrop,
        lessThan(0.05),
        reason:
            'normalized 不应因 max 暴涨而大幅反降：'
            '$beforeExtreme -> $afterExtreme',
      );
    }

    // 末尾定位：未测项仍为 estimate，跟随 max 时会逐步收敛（与阶段 0 相同手法）。
    ScrollMetricsSample atEnd = afterExtreme;
    for (var attempt = 0; attempt < 16; attempt += 1) {
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      atEnd = trace.capture(
        tester,
        label: 'end-$attempt',
        scrollView: scrollView,
        itemKeyPrefix: 'perf-',
      );
      if (atEnd.endDistance <= 1.0) {
        break;
      }
    }
    expect(atEnd.builtChildCount, lessThan(100), reason: '$atEnd');
    // 允许少量残余：estimate 与实测仍可能差一截，但必须保持虚拟化。
    expect(atEnd.endDistance, lessThan(10_000), reason: '$atEnd');
    expect(virtual.extentIndex.length, itemCount);

    // 滚动过程中已测项应增加，但绝不等于全量 2000（cache 窗口）。
    expect(virtual.measuredCount, greaterThan(0));
    expect(virtual.measuredCount, lessThan(itemCount));
    expect(virtual.debugLaidOutChildCount, lessThan(100));
    expect(virtual.debugMeasurementUpdateCount, greaterThan(0));

    stopwatch.stop();
    final summary =
        'phase5-perf initialPumpMs=$initialPumpMs '
        'builtFirst=${builtIds.length} '
        'max0=${maxAfterInitial.toStringAsFixed(1)} '
        'beforeExt=${beforeExtreme.maxScrollExtent.toStringAsFixed(1)} '
        'afterExt=${afterExtreme.maxScrollExtent.toStringAsFixed(1)} '
        'maxDelta=${maxDelta.toStringAsFixed(1)} '
        'measured=${virtual.measuredCount} '
        'fresh=${virtual.freshMeasurementCount} '
        'records=${virtual.extentIndex.length} '
        'corrections=${virtual.debugAnchorCorrectionCount} '
        'maxCorr=${virtual.debugMaxSingleCorrection.toStringAsFixed(1)} '
        'laidOut=${virtual.debugLaidOutChildCount} '
        'measureUpdates=${virtual.debugMeasurementUpdateCount} '
        'endBuilt=${atEnd.builtChildCount} '
        'totalMs=${stopwatch.elapsedMilliseconds}';
    developer.log(summary, name: 'zeta.scroll.perf.phase5');

    // 便于本地复制：仅在显式 diagnostics 时已由 ScrollMetricsTrace 处理。
    // ignore: avoid_print — 性能报告测试输出，非常驻路径。
    // 使用 developer.log 即可；此处不再 print。
  });

  testWidgets('19.6 锚点前增高：viewport 偏差 ≤1px，并记录 correction', (tester) async {
    final items = List<double>.filled(40, 40.0);
    final controller = ScrollController();
    final virtual = IdeVirtualListController()..resetDebugMetrics();
    addTearDown(controller.dispose);

    virtual.setItems([
      for (var i = 0; i < items.length; i++)
        IdeVirtualItemDescriptor(
          id: 'a-$i',
          kind: 'block',
          layoutRevision: 1,
          estimatedExtent: 40,
        ),
    ], epoch: epoch);

    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            key: const ValueKey('perf-anchor-scroll'),
            controller: controller,
            slivers: [
              IdeAnchoredDynamicSliverList(
                controller: virtual,
                delegate: SliverChildBuilderDelegate(
                  (context, index) => SizedBox(
                    key: ValueKey<String>('a-$index'),
                    height: items[index],
                    child: Text('a-$index'),
                  ),
                  childCount: items.length,
                  findChildIndexCallback: (key) {
                    if (key is ValueKey<String> && key.value.startsWith('a-')) {
                      return int.tryParse(key.value.substring(2));
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
    await tester.pumpAndSettle();

    controller.jumpTo(200);
    await tester.pumpAndSettle();

    final scrollView = find.byKey(const ValueKey('perf-anchor-scroll'));
    final topBefore = itemViewportTop(
      tester,
      scrollView: scrollView,
      itemKey: const ValueKey<String>('a-8'),
    );

    // 增高锚点前的 a-3（layoutRevision 变化触发 remeasure）。
    items[3] = 140;
    virtual.setItems([
      for (var i = 0; i < items.length; i++)
        IdeVirtualItemDescriptor(
          id: 'a-$i',
          kind: 'block',
          layoutRevision: i == 3 ? 2 : 1,
          estimatedExtent: items[i],
        ),
    ], epoch: epoch);
    await tester.pumpAndSettle();

    final topAfter = itemViewportTop(
      tester,
      scrollView: scrollView,
      itemKey: const ValueKey<String>('a-8'),
    );
    expect(
      (topAfter - topBefore).abs(),
      lessThanOrEqualTo(1.0),
      reason:
          'before=$topBefore after=$topAfter '
          'corr=${virtual.debugAnchorCorrectionCount} '
          'maxCorr=${virtual.debugMaxSingleCorrection}',
    );
    // correction 计数用于可观测性；视觉稳定是硬门槛。
    developer.log(
      'phase5-anchor corr=${virtual.debugAnchorCorrectionCount} '
      'maxCorr=${virtual.debugMaxSingleCorrection} '
      'topBefore=$topBefore topAfter=$topAfter',
      name: 'zeta.scroll.perf.phase5',
    );
  });
}

/// 阶段 0 场景 A 同源高度模式。
double _mixedExtent(int index) {
  if (index < 60) {
    return index.isEven ? 24 : 80;
  }
  const pattern = <double>[2000, 32, 600, 48, 24, 80];
  return pattern[(index - 60) % pattern.length];
}

String _kindForIndex(int index) {
  final h = _mixedExtent(index);
  if (h >= 1000) {
    return 'agentMarkdown';
  }
  if (h >= 200) {
    return 'commandGroup';
  }
  return 'turnFooter';
}
