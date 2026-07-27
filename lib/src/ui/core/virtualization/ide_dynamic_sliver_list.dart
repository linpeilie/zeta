/// 锚定动态高度虚拟列表：自然布局 child + ExtentIndex 总高 + 锚点修正。
///
/// v1 仅支持垂直、[AxisDirection.down]、[GrowthDirection.forward]、非 reverse。
/// 不依赖 Agent feature。layout 期间可更新 extent index，但不得同步触发
/// 上层 ChangeNotifier rebuild。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'ide_virtual_item.dart';
import 'ide_virtual_list_controller.dart';

/// scrollOffsetCorrection 的最小阈值（logical px）。
const double kIdeScrollCorrectionEpsilon = 0.5;

/// 单 frame 内允许的最大 correction 次数。
const int kIdeMaxCorrectionsPerFrame = 2;

/// 在 feature flag 下构建动态高度 sliver 或普通 [SliverList]。
///
/// 仅通用层/测试层使用，便于与默认 [SliverList] 并存对照。
Widget buildIdeVirtualSliver({
  required bool useAnchoredDynamic,
  required IdeVirtualListController controller,
  required SliverChildDelegate delegate,
}) {
  if (useAnchoredDynamic) {
    return IdeAnchoredDynamicSliverList(
      controller: controller,
      delegate: delegate,
    );
  }
  return SliverList(delegate: delegate);
}

/// 动态高度、锚点稳定的虚拟列表 sliver。
///
/// child 按自然高度布局；未显示项高度来自 [IdeExtentIndex] 的
/// estimate/measured。
class IdeAnchoredDynamicSliverList extends SliverMultiBoxAdaptorWidget {
  /// 创建锚定动态高度 sliver。
  const IdeAnchoredDynamicSliverList({
    super.key,
    required this.controller,
    required super.delegate,
  });

  /// 持有 extent index 与 descriptor 序列的控制器。
  final IdeVirtualListController controller;

  @override
  RenderIdeAnchoredDynamicSliverList createRenderObject(BuildContext context) {
    final element = context as SliverMultiBoxAdaptorElement;
    return RenderIdeAnchoredDynamicSliverList(
      childManager: element,
      controller: controller,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderIdeAnchoredDynamicSliverList renderObject,
  ) {
    if (!identical(renderObject.controller, controller)) {
      renderObject.controller = controller;
      renderObject.markNeedsLayout();
    }
  }

  @override
  double? estimateMaxScrollOffset(
    SliverConstraints? constraints,
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) {
    // 使用 extent index 总高，避免默认“已布局均值 × 剩余项”放大。
    if (controller.extentIndex.length > 0) {
      return controller.extentIndex.totalExtent;
    }
    return super.estimateMaxScrollOffset(
      constraints,
      firstIndex,
      lastIndex,
      leadingScrollOffset,
      trailingScrollOffset,
    );
  }
}

/// 动态高度虚拟列表的 RenderSliver。
class RenderIdeAnchoredDynamicSliverList extends RenderSliverMultiBoxAdaptor {
  /// 创建 render object。
  RenderIdeAnchoredDynamicSliverList({
    required super.childManager,
    required this.controller,
  });

  /// 关联的虚拟列表控制器。
  IdeVirtualListController controller;

  Duration? _correctionFrameStamp;
  int _correctionsThisFrame = 0;

  IdeLayoutEpoch _fallbackEpoch(SliverConstraints constraints) {
    final existing = controller.epoch;
    final crossPhysical = constraints.crossAxisExtent.round().clamp(0, 1 << 30);
    return IdeLayoutEpoch(
      crossAxisExtentInPhysicalPixels: crossPhysical,
      textScaleKey: existing?.textScaleKey ?? 1.0,
      localeKey: existing?.localeKey ?? 'und',
      typographyEpoch: existing?.typographyEpoch ?? 0,
    );
  }

  void _assertSupportedConfiguration(SliverConstraints constraints) {
    assert(() {
      final axisDirection = applyGrowthDirectionToAxisDirection(
        constraints.axisDirection,
        constraints.growthDirection,
      );
      if (constraints.axis != Axis.vertical ||
          axisDirection != AxisDirection.down ||
          constraints.growthDirection != GrowthDirection.forward) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('IdeAnchoredDynamicSliverList 仅支持垂直 forward 列表。'),
          ErrorDescription(
            'axis=${constraints.axis}, axisDirection=$axisDirection, '
            'growth=${constraints.growthDirection}',
          ),
        ]);
      }
      return true;
    }());
  }

  void _noteCorrectionFrame() {
    final stamp = SchedulerBinding.instance.currentFrameTimeStamp;
    if (_correctionFrameStamp != stamp) {
      _correctionFrameStamp = stamp;
      _correctionsThisFrame = 0;
    }
  }

  bool _canCorrectThisFrame() {
    _noteCorrectionFrame();
    return _correctionsThisFrame < kIdeMaxCorrectionsPerFrame;
  }

  void _consumeCorrectionBudget() {
    _noteCorrectionFrame();
    _correctionsThisFrame += 1;
  }

  void _resetCorrectionBudgetOnSuccess() {
    _noteCorrectionFrame();
    _correctionsThisFrame = 0;
  }

  @override
  void performLayout() {
    final SliverConstraints constraints = this.constraints;
    _assertSupportedConfiguration(constraints);

    childManager.didStartLayout();
    childManager.setDidUnderflow(false);

    final controller = this.controller;
    final extentIndex = controller.extentIndex;

    // 1. 非空旧序列上先捕获锚点，再应用 pending synchronize。
    IdeAnchorSnapshot? anchorSnapshot;
    if (extentIndex.length > 0) {
      anchorSnapshot = controller.captureAnchor(constraints.scrollOffset);
    }
    if (controller.hasPendingSequence) {
      controller.applyPendingSequence();
    }

    if (extentIndex.length == 0) {
      geometry = SliverGeometry.zero;
      childManager.didFinishLayout();
      return;
    }

    final IdeLayoutEpoch epoch =
        extentIndex.epoch ?? _fallbackEpoch(constraints);

    final double scrollOffset =
        constraints.scrollOffset + constraints.cacheOrigin;
    assert(scrollOffset >= 0.0);
    final double remainingExtent = constraints.remainingCacheExtent;
    assert(remainingExtent >= 0.0);
    final double targetEndScrollOffset = scrollOffset + remainingExtent;
    final BoxConstraints childConstraints = constraints.asBoxConstraints();

    // 2. 用当前索引定位布局区间。
    var firstIndex = extentIndex.indexAtOffset(scrollOffset);
    if (firstIndex < 0) {
      firstIndex = 0;
    }
    var lastIndex = extentIndex.indexAtOffset(
      math.max(scrollOffset, targetEndScrollOffset - precisionErrorTolerance),
    );
    if (lastIndex < 0) {
      lastIndex = extentIndex.length - 1;
    }
    while (lastIndex < extentIndex.length - 1 &&
        extentIndex.endOf(lastIndex) < targetEndScrollOffset) {
      lastIndex += 1;
    }
    firstIndex = firstIndex.clamp(0, extentIndex.length - 1);
    lastIndex = lastIndex.clamp(firstIndex, extentIndex.length - 1);

    // 3. 回收区间外 child。
    if (firstChild != null) {
      collectGarbage(
        calculateLeadingGarbage(firstIndex: firstIndex),
        calculateTrailingGarbage(lastIndex: lastIndex),
      );
    } else {
      collectGarbage(0, 0);
    }

    // 4. 确保 firstChild 落在 firstIndex。
    if (firstChild == null) {
      final layoutOffset = extentIndex.offsetOf(firstIndex);
      if (!addInitialChild(index: firstIndex, layoutOffset: layoutOffset)) {
        geometry = SliverGeometry(
          scrollExtent: extentIndex.totalExtent,
          maxPaintExtent: extentIndex.totalExtent,
        );
        childManager.didFinishLayout();
        return;
      }
    }

    // 向前补齐 leading。
    while (firstChild != null && indexOf(firstChild!) > firstIndex) {
      final insertIndex = indexOf(firstChild!) - 1;
      final child = insertAndLayoutLeadingChild(
        childConstraints,
        parentUsesSize: true,
      );
      if (child == null) {
        break;
      }
      _measureAndPlaceChild(child: child, index: insertIndex, epoch: epoch);
    }

    // 布局 firstChild。
    if (firstChild != null) {
      final index = indexOf(firstChild!);
      firstChild!.layout(childConstraints, parentUsesSize: true);
      _measureAndPlaceChild(child: firstChild!, index: index, epoch: epoch);
    }

    // 向后布局；测量后若未覆盖 cache 终点则扩展。
    var trailing = firstChild;
    var safety = 0;
    while (trailing != null && safety < extentIndex.length + 8) {
      safety += 1;
      final trailingIndex = indexOf(trailing);

      if (trailingIndex >= lastIndex) {
        if (extentIndex.endOf(trailingIndex) >= targetEndScrollOffset ||
            trailingIndex >= extentIndex.length - 1) {
          break;
        }
        lastIndex = math.min(lastIndex + 1, extentIndex.length - 1);
      }

      final nextIndex = trailingIndex + 1;
      if (nextIndex > lastIndex || nextIndex >= extentIndex.length) {
        break;
      }

      var next = childAfter(trailing);
      if (next == null || indexOf(next) != nextIndex) {
        next = insertAndLayoutChild(
          childConstraints,
          after: trailing,
          parentUsesSize: true,
        );
        if (next == null) {
          break;
        }
      } else {
        next.layout(childConstraints, parentUsesSize: true);
      }
      _measureAndPlaceChild(child: next, index: nextIndex, epoch: epoch);
      trailing = next;
    }

    // 测量后可能缩小所需 trailing，回收多余 child。
    if (firstChild != null && lastChild != null) {
      final actualLast = indexOf(lastChild!);
      if (actualLast > lastIndex) {
        collectGarbage(0, actualLast - lastIndex);
      }
    }

    // 5. 统一用索引写回 layoutOffset。
    _assignOffsetsFromIndex();

    // 6. 锚点 correction。
    final correction = controller.computeScrollCorrection(anchorSnapshot);
    if (correction.abs() > kIdeScrollCorrectionEpsilon &&
        _canCorrectThisFrame()) {
      _consumeCorrectionBudget();
      assert(() {
        debugPrint(
          'IdeAnchoredDynamicSliverList correction=$correction '
          'anchor=${anchorSnapshot?.anchor.itemId} '
          'n=$_correctionsThisFrame',
        );
        return true;
      }());
      geometry = SliverGeometry(scrollOffsetCorrection: correction);
      return;
    }

    _resetCorrectionBudgetOnSuccess();

    assert(firstChild != null);
    assert(debugAssertChildListIsNonEmptyAndContiguous());

    final scrollExtent = extentIndex.totalExtent;
    final leadingScrollOffset = childScrollOffset(firstChild!)!;
    final trailingScrollOffset =
        childScrollOffset(lastChild!)! + paintExtentOf(lastChild!);

    final paintExtent = calculatePaintOffset(
      constraints,
      from: leadingScrollOffset,
      to: trailingScrollOffset,
    );
    final cacheExtent = calculateCacheOffset(
      constraints,
      from: leadingScrollOffset,
      to: trailingScrollOffset,
    );
    final targetEndScrollOffsetForPaint =
        constraints.scrollOffset + constraints.remainingPaintExtent;

    geometry = SliverGeometry(
      scrollExtent: scrollExtent,
      paintExtent: paintExtent,
      cacheExtent: cacheExtent,
      maxPaintExtent: scrollExtent,
      hasVisualOverflow:
          trailingScrollOffset > targetEndScrollOffsetForPaint ||
          constraints.scrollOffset > 0.0,
    );

    if (indexOf(lastChild!) >= extentIndex.length - 1 &&
        trailingScrollOffset >= scrollExtent - precisionErrorTolerance) {
      childManager.setDidUnderflow(true);
    }
    childManager.didFinishLayout();
  }

  void _measureAndPlaceChild({
    required RenderBox child,
    required int index,
    required IdeLayoutEpoch epoch,
  }) {
    final extentIndex = controller.extentIndex;
    if (index < 0 || index >= extentIndex.length) {
      return;
    }
    final measured = paintExtentOf(child);
    extentIndex.updateMeasuredExtent(
      index: index,
      measuredExtent: measured,
      epoch: epoch,
    );
    final parentData = child.parentData! as SliverMultiBoxAdaptorParentData;
    parentData.layoutOffset = extentIndex.offsetOf(index);
    assert(parentData.index == index);
  }

  void _assignOffsetsFromIndex() {
    final extentIndex = controller.extentIndex;
    var child = firstChild;
    while (child != null) {
      final index = indexOf(child);
      if (index >= 0 && index < extentIndex.length) {
        final parentData = child.parentData! as SliverMultiBoxAdaptorParentData;
        parentData.layoutOffset = extentIndex.offsetOf(index);
      }
      child = childAfter(child);
    }
  }
}
