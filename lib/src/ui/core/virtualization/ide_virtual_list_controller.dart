/// 动态高度虚拟列表的通用控制器。
///
/// 持有 [IdeExtentIndex] 与待同步的 descriptor 序列。渲染层在 layout
/// 中应用 pending 序列，以便先捕获锚点再 synchronize。
///
/// 本类型不依赖 Agent feature、Provider 或 domain。layout 期间不得通过
/// ChangeNotifier 同步触发上层 rebuild。
library;

import 'package:flutter/foundation.dart';

import 'ide_extent_index.dart';
import 'ide_virtual_item.dart';

/// 通用层 feature flag：是否使用锚定动态高度 sliver。
///
/// 仅用于开发/回滚与测试对照；关闭时应回退到普通 `SliverList`。
/// 不作为长期用户配置。
const bool kIdeUseAnchoredDynamicSliver = true;

/// 视口锚点：以稳定 item ID 记录用户当前阅读位置。
@immutable
final class IdeScrollAnchor {
  /// 创建锚点快照。
  const IdeScrollAnchor({
    required this.itemId,
    required this.intraItemOffset,
    required this.viewportOffset,
  });

  /// 当前用作视觉基准的稳定 item ID。
  final String itemId;

  /// 视口起点位于 item 内部的距离（logical px）。
  final double intraItemOffset;

  /// 希望该基准保持在 viewport 中的位置；常规为 0。
  final double viewportOffset;
}

/// 布局前捕获的锚点内容坐标，用于 scrollOffsetCorrection。
@immutable
final class IdeAnchorSnapshot {
  /// 创建锚点快照。
  const IdeAnchorSnapshot({
    required this.anchor,
    required this.oldContentOffset,
    required this.oldIndex,
    required this.oldOrderedIds,
  });

  /// 锚点业务身份与 item 内偏移。
  final IdeScrollAnchor anchor;

  /// 捕获时的绝对内容坐标：`offsetOf(id) + intraItemOffset`。
  final double oldContentOffset;

  /// 捕获时的下标；删除 fallback 时使用。
  final int oldIndex;

  /// 捕获时完整 ID 序列（用于删除 fallback）。
  final List<String> oldOrderedIds;
}

/// 通用虚拟列表控制器：descriptor 序列 + extent index。
///
/// 调用方在 setState 前调用 [setItems]；RenderSliver 在 layout 中
/// [applyPendingSequence] 完成 synchronize。
final class IdeVirtualListController {
  /// 创建空控制器。
  IdeVirtualListController();

  final IdeExtentIndex extentIndex = IdeExtentIndex();

  List<IdeVirtualItemDescriptor> _descriptors =
      const <IdeVirtualItemDescriptor>[];
  List<IdeVirtualItemDescriptor>? _pendingDescriptors;
  IdeLayoutEpoch? _pendingEpoch;

  /// 当前（含 pending）item 数量，供 delegate.childCount 使用。
  int get itemCount => _pendingDescriptors?.length ?? extentIndex.length;

  /// 当前生效或 pending 的 descriptor 列表。
  List<IdeVirtualItemDescriptor> get descriptors {
    return _pendingDescriptors ?? _descriptors;
  }

  /// 是否有尚未应用到索引的序列变更。
  bool get hasPendingSequence => _pendingDescriptors != null;

  /// 最近一次已应用的 layout epoch。
  IdeLayoutEpoch? get epoch => extentIndex.epoch;

  /// 按稳定 ID 取下标。
  int? indexOfId(String id) => extentIndex.indexOfId(id);

  /// 内容总高度。
  double get totalExtent => extentIndex.totalExtent;

  /// 提交新的 item 序列；真正 synchronize 推迟到 render layout。
  ///
  /// 不在此处通知监听者，避免 layout 期间同步 rebuild。
  void setItems(
    List<IdeVirtualItemDescriptor> items, {
    required IdeLayoutEpoch epoch,
  }) {
    _pendingDescriptors = List<IdeVirtualItemDescriptor>.of(
      items,
      growable: false,
    );
    _pendingEpoch = epoch;
  }

  /// 立即同步（测试辅助）；生产路径优先让 RenderSliver 在锚点捕获后调用
  /// [applyPendingSequence]。
  void synchronizeNow(
    List<IdeVirtualItemDescriptor> items, {
    required IdeLayoutEpoch epoch,
  }) {
    _pendingDescriptors = null;
    _pendingEpoch = null;
    _descriptors = List<IdeVirtualItemDescriptor>.of(items, growable: false);
    extentIndex.synchronize(_descriptors, epoch: epoch);
  }

  /// 若有 pending 序列则写入 extent index。
  ///
  /// 返回是否实际发生了 synchronize。
  bool applyPendingSequence() {
    final pending = _pendingDescriptors;
    final epoch = _pendingEpoch;
    if (pending == null || epoch == null) {
      return false;
    }
    _descriptors = pending;
    _pendingDescriptors = null;
    _pendingEpoch = null;
    extentIndex.synchronize(_descriptors, epoch: epoch);
    return true;
  }

  /// 在当前索引状态下捕获视口锚点。
  IdeAnchorSnapshot? captureAnchor(double scrollOffset) {
    final index = extentIndex;
    if (index.length == 0) {
      return null;
    }
    final itemIndex = index.indexAtOffset(scrollOffset);
    if (itemIndex < 0) {
      return null;
    }
    final record = index.recordAt(itemIndex);
    final start = index.offsetOf(itemIndex);
    final extent = index.extentAt(itemIndex);
    final intra = extent <= 0 ? 0.0 : (scrollOffset - start).clamp(0.0, extent);
    final orderedIds = List<String>.generate(
      index.length,
      (i) => index.recordAt(i).id,
      growable: false,
    );
    final anchor = IdeScrollAnchor(
      itemId: record.id,
      intraItemOffset: intra,
      viewportOffset: 0,
    );
    return IdeAnchorSnapshot(
      anchor: anchor,
      oldContentOffset: start + intra,
      oldIndex: itemIndex,
      oldOrderedIds: orderedIds,
    );
  }

  /// 根据测量/序列变化后的索引计算 scrollOffsetCorrection。
  ///
  /// 锚点被删除时：优先后方存活项，其次前方，再次列表首项。
  double computeScrollCorrection(IdeAnchorSnapshot? snapshot) {
    if (snapshot == null || extentIndex.length == 0) {
      return 0;
    }
    final resolvedId = _resolveAnchorId(snapshot);
    if (resolvedId == null) {
      return 0;
    }
    final newIndex = extentIndex.indexOfId(resolvedId);
    if (newIndex == null) {
      return 0;
    }
    final intra = resolvedId == snapshot.anchor.itemId
        ? snapshot.anchor.intraItemOffset
        : 0.0;
    final newContent = extentIndex.offsetOf(newIndex) + intra;
    return newContent - snapshot.oldContentOffset;
  }

  String? _resolveAnchorId(IdeAnchorSnapshot snapshot) {
    final preferred = snapshot.anchor.itemId;
    if (extentIndex.indexOfId(preferred) != null) {
      return preferred;
    }
    final oldOrder = snapshot.oldOrderedIds;
    final oldIndex = snapshot.oldIndex;
    for (var i = oldIndex + 1; i < oldOrder.length; i++) {
      if (extentIndex.indexOfId(oldOrder[i]) != null) {
        return oldOrder[i];
      }
    }
    for (var i = oldIndex - 1; i >= 0; i--) {
      if (extentIndex.indexOfId(oldOrder[i]) != null) {
        return oldOrder[i];
      }
    }
    if (extentIndex.length > 0) {
      return extentIndex.recordAt(0).id;
    }
    return null;
  }
}
