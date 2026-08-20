/// 动态高度虚拟列表的核心数据模型。
///
/// 本文件仅包含纯 Dart 类型，不依赖 Agent feature、Widget、BuildContext
/// 或 Provider。高度真源由 [IdeExtentRecord.effectiveExtent] 表达，供
/// extent index 做前缀和与 offset 查找。
library;

import 'package:flutter/foundation.dart';

/// 跨 snapshot/rebuild 描述一个虚拟列表项的稳定输入。
///
/// [id] 在当前序列内必须唯一；[estimatedExtent] 必须有限且不小于 0。
/// [layoutRevision] 不要求全局单调，只需能判断本项布局输入是否改变。
@immutable
final class IdeVirtualItemDescriptor {
  /// 创建一项的稳定描述。
  ///
  /// [estimatedExtent] 必须有限且不小于 0；非法值在 debug 下由构造 assert
  /// 捕获，release 下由 extent index 安全 clamp。
  const IdeVirtualItemDescriptor({
    required this.id,
    required this.kind,
    required this.layoutRevision,
    required this.estimatedExtent,
  }) : assert(estimatedExtent >= 0.0, 'estimatedExtent 必须不小于 0。');

  /// 跨 snapshot/rebuild 保持稳定的业务 ID。
  final String id;

  /// 只用于同类项自适应估算，不参与业务逻辑。
  final String kind;

  /// 内容或展开状态发生布局级变化时改变的版本标记。
  final Object layoutRevision;

  /// 当前 layout epoch 下的新项初始估算高度。
  final double estimatedExtent;
}

/// 使已测高度失效的布局环境版本。
///
/// 宽度按 physical pixel 整数量化，避免浮点抖动反复令全部测量失效。
/// 颜色变化不影响 epoch；仅 repaint 的主题变化不得触发重新估高。
@immutable
final class IdeLayoutEpoch {
  /// 创建布局环境指纹。
  const IdeLayoutEpoch({
    required this.crossAxisExtentInPhysicalPixels,
    required this.textScaleKey,
    required this.localeKey,
    required this.typographyEpoch,
  });

  /// 交叉轴可用宽度（物理像素整数）。
  final int crossAxisExtentInPhysicalPixels;

  /// 文本缩放键；实现可使用 scale 的稳定量化值。
  final Object textScaleKey;

  /// 语言/地区键。
  final Object localeKey;

  /// 字体/排版主题版本。
  final Object typographyEpoch;

  @override
  bool operator ==(Object other) {
    return other is IdeLayoutEpoch &&
        other.crossAxisExtentInPhysicalPixels ==
            crossAxisExtentInPhysicalPixels &&
        other.textScaleKey == textScaleKey &&
        other.localeKey == localeKey &&
        other.typographyEpoch == typographyEpoch;
  }

  @override
  int get hashCode => Object.hash(
    crossAxisExtentInPhysicalPixels,
    textScaleKey,
    localeKey,
    typographyEpoch,
  );

  @override
  String toString() {
    return 'IdeLayoutEpoch('
        'crossAxis=$crossAxisExtentInPhysicalPixels, '
        'textScale=$textScaleKey, '
        'locale=$localeKey, '
        'typography=$typographyEpoch)';
  }
}

/// 单项高度在索引中的当前记录。
///
/// [effectiveExtent] 是前缀和使用的唯一高度。revision 或 layout epoch
/// 变化后，旧 measured 不立刻清空，而是降级为 stale estimate。
///
/// 记录由 extent index 拥有；外部调用方应只读，不要绕过索引改写字段。
final class IdeExtentRecord {
  /// 创建由索引管理的高度记录。
  IdeExtentRecord({
    required this.id,
    required this.kind,
    required this.layoutRevision,
    required this.effectiveExtent,
    this.measuredExtent,
    this.measuredEpoch,
    this.isMeasurementFresh = false,
  });

  /// 稳定业务 ID。
  final String id;

  /// 同类项估算用的 kind。
  String kind;

  /// 最近一次同步时的布局版本。
  Object layoutRevision;

  /// 前缀和当前使用的唯一高度。
  double effectiveExtent;

  /// 最近一次实测高度；从未测量时为 null。
  double? measuredExtent;

  /// 实测对应的 layout epoch。
  IdeLayoutEpoch? measuredEpoch;

  /// 当前 epoch/revision 下测量是否仍 fresh。
  bool isMeasurementFresh;

  /// 是否曾经测过高度（含已降级为 stale 的值）。
  bool get hasMeasuredExtent => measuredExtent != null;

  /// 由 extent index 更新 kind 与 revision。
  void applyDescriptor(IdeVirtualItemDescriptor descriptor) {
    kind = descriptor.kind;
    layoutRevision = descriptor.layoutRevision;
  }

  /// 将测量标记为 stale，保留 [measuredExtent] 与 [effectiveExtent]。
  void markMeasurementStale() {
    isMeasurementFresh = false;
  }

  /// 写入实测高度，并立刻成为 effective 与 fresh measurement。
  void setMeasured({
    required double measuredExtent,
    required IdeLayoutEpoch epoch,
  }) {
    this.measuredExtent = measuredExtent;
    measuredEpoch = epoch;
    effectiveExtent = measuredExtent;
    isMeasurementFresh = true;
  }

  /// 记录实测快照并标记 fresh，但不改写 [effectiveExtent]。
  ///
  /// 用于亚像素阈值内的测量噪声：索引树保持稳定，同时保留最新实测。
  void setMeasuredSnapshot({
    required double measuredExtent,
    required IdeLayoutEpoch epoch,
  }) {
    this.measuredExtent = measuredExtent;
    measuredEpoch = epoch;
    isMeasurementFresh = true;
  }
}

/// 单点实测更新的结果。
@immutable
final class IdeExtentDelta {
  /// 创建一次实测更新结果。
  const IdeExtentDelta({
    required this.index,
    required this.id,
    required this.oldEffectiveExtent,
    required this.newEffectiveExtent,
    required this.delta,
    required this.applied,
  });

  /// 未发生有效变更时的空结果。
  const IdeExtentDelta.none({
    required this.index,
    required this.id,
    required double effectiveExtent,
  }) : oldEffectiveExtent = effectiveExtent,
       newEffectiveExtent = effectiveExtent,
       delta = 0,
       applied = false;

  /// 目标下标。
  final int index;

  /// 目标稳定 ID。
  final String id;

  /// 更新前的 effective extent。
  final double oldEffectiveExtent;

  /// 更新后的 effective extent。
  final double newEffectiveExtent;

  /// `newEffectiveExtent - oldEffectiveExtent`。
  final double delta;

  /// 是否因超过测量阈值而实际写入索引。
  final bool applied;
}
