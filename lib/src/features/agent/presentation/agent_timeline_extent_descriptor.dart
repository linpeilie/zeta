/// 将 Agent timeline viewport item 投影为通用 [IdeVirtualItemDescriptor]。
///
/// 只做冷启动估算与 layoutRevision 指纹；不依赖 BuildContext / Provider raw
/// payload。cohort 均值不得在此批量回写已有未知项。
///
/// block 级的 kind / 估算 / 指纹全部委托 [AgentTimelineRendererRegistry]——
/// 这里只保留不属于任何 block 的 viewport 级两项（live 活动条与 turn footer）。
library;

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_extent_math.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer_registry.dart';
import 'package:zeta_ui/zeta_ui.dart';

/// 布局环境输入（宽度 / 缩放 / locale），用于构造 [IdeLayoutEpoch]。
final class AgentTimelineLayoutContext {
  /// 创建布局上下文。
  const AgentTimelineLayoutContext({
    required this.crossAxisExtent,
    required this.devicePixelRatio,
    required this.textScale,
    required this.localeKey,
    this.typographyEpoch = 0,
  });

  /// 时间线可用交叉轴宽度（logical px）。
  final double crossAxisExtent;

  /// 设备像素比。
  final double devicePixelRatio;

  /// 文本缩放因子。
  final double textScale;

  /// locale 键。
  final String localeKey;

  /// 字体/排版版本。
  final Object typographyEpoch;

  /// 量化后的 layout epoch。
  IdeLayoutEpoch toEpoch() {
    final physical = (crossAxisExtent * devicePixelRatio).round().clamp(
      0,
      1 << 30,
    );
    // textScale 量化到 0.05，降低浮点抖动。
    final scaleKey = (textScale * 20).round() / 20.0;
    return IdeLayoutEpoch(
      crossAxisExtentInPhysicalPixels: physical,
      textScaleKey: scaleKey,
      localeKey: localeKey,
      typographyEpoch: typographyEpoch,
    );
  }
}

/// Agent timeline → [IdeVirtualItemDescriptor] 工厂。
///
/// 可复用实例：连续 [describeAll] 在 id 序列稳定时复用未变项的 descriptor
/// 对象，使尾部变化时前缀布局保持稳定。
final class AgentTimelineExtentDescriptorFactory {
  /// 创建工厂。
  ///
  /// [registry] 显式注入：不设全局单例，测试可以传裁剪版清单。
  AgentTimelineExtentDescriptorFactory({required this.registry});

  /// block 级分发表。
  final AgentTimelineRendererRegistry registry;

  List<IdeVirtualItemDescriptor>? _lastDescriptors;

  /// 诊断：describeAll 复用上一帧 descriptor 实例的次数。
  int debugReusedDescriptorCount = 0;

  /// 诊断：实际新建 descriptor 的次数。
  int debugBuiltDescriptorCount = 0;

  /// 清除复用缓存（会话切换时调用）。
  void clearCache() {
    _lastDescriptors = null;
  }

  /// 将视口 item 列表转为 descriptor 序列。
  ///
  /// 当与上一帧相比仅尾部 revision 变化时，前缀项返回**同一实例**，
  /// 便于 [IdeVirtualListController.setItems] 短路与减少分配。
  List<IdeVirtualItemDescriptor> describeAll(
    List<AgentTimelineViewportItem> items, {
    required AgentTimelineExpansionLookup expansion,
    required AgentTimelineLayoutContext layoutContext,
  }) {
    final previous = _lastDescriptors;
    final next = List<IdeVirtualItemDescriptor>.generate(items.length, (index) {
      final built = describe(
        items[index],
        previousItem: index > 0 ? items[index - 1] : null,
        nextItem: index + 1 < items.length ? items[index + 1] : null,
        expansion: expansion,
        layoutContext: layoutContext,
      );
      if (previous != null &&
          index < previous.length &&
          _descriptorFingerprintEquals(previous[index], built)) {
        debugReusedDescriptorCount += 1;
        return previous[index];
      }
      debugBuiltDescriptorCount += 1;
      return built;
    }, growable: false);
    _lastDescriptors = next;
    return next;
  }

  /// 描述单个 viewport item。
  IdeVirtualItemDescriptor describe(
    AgentTimelineViewportItem item, {
    AgentTimelineViewportItem? previousItem,
    AgentTimelineViewportItem? nextItem,
    required AgentTimelineExpansionLookup expansion,
    required AgentTimelineLayoutContext layoutContext,
  }) {
    final precededByOperationGroup = _isPrecededByOperationGroup(previousItem);
    final followedByOperationGroup = _isPrecededByOperationGroup(nextItem);
    final kind = _kindOf(item);
    final revision = _layoutRevision(
      item,
      expansion,
      precededByOperationGroup: precededByOperationGroup,
      followedByOperationGroup: followedByOperationGroup,
    );
    final estimated = _estimateExtent(
      item,
      crossAxisExtent: layoutContext.crossAxisExtent,
      textScale: layoutContext.textScale,
      expansion: expansion,
      precededByOperationGroup: precededByOperationGroup,
      followedByOperationGroup: followedByOperationGroup,
    );
    return IdeVirtualItemDescriptor(
      id: item.id,
      kind: kind,
      layoutRevision: revision,
      estimatedExtent: estimated,
    );
  }

  String _kindOf(AgentTimelineViewportItem item) {
    return switch (item) {
      AgentLiveActivityViewportItem() => AgentTimelineExtentKinds.liveActivity,
      AgentTurnFooterViewportItem() => AgentTimelineExtentKinds.turnFooter,
      AgentBlockViewportItem(:final block) =>
        registry
            .resolve(block)
            .kindOf(AgentTimelineRendererRegistry.payloadOf(block)),
    };
  }

  /// 布局失效指纹。
  ///
  /// 流式更新只让**变化 entry** 的 revision 改变，
  /// 禁止用整 turn 的 [AgentConversationTurnGroup.contentRevision] 绑死所有 block，
  /// 否则 live turn 内每个字符都会把 sibling tool card 标成 measurement stale。
  Object _layoutRevision(
    AgentTimelineViewportItem item,
    AgentTimelineExpansionLookup expansion, {
    bool precededByOperationGroup = false,
    bool followedByOperationGroup = false,
  }) {
    return switch (item) {
      AgentLiveActivityViewportItem(:final turn) => Object.hash(
        'live-activity',
        turn.id,
        turn.metaRevision,
        turn.status,
      ),
      AgentTurnFooterViewportItem(:final turn) => Object.hash(
        'footer',
        turn.id,
        turn.metaRevision,
        turn.status,
        turn.tokenUsage?.totalTokens,
        turn.duration?.inMilliseconds,
        turn.modelConfig?.modelId,
      ),
      AgentBlockViewportItem(:final turn, :final block) => Object.hash(
        'block',
        turn.id,
        block.id,
        registry
            .resolve(block)
            .layoutRevision(
              AgentTimelineRendererRegistry.payloadOf(block),
              expansion,
            ),
        // 相邻操作组会改变上下外间距（块内 2 / 块外 10），进而影响实测高度，
        // 所以前后两侧都要进指纹，否则邻居变化后旧估算会被复用。
        isAgentTimelineOperationGroupBlock(block)
            ? precededByOperationGroup
            : null,
        isAgentTimelineOperationGroupBlock(block)
            ? followedByOperationGroup
            : null,
      ),
    };
  }

  double _estimateExtent(
    AgentTimelineViewportItem item, {
    required double crossAxisExtent,
    required double textScale,
    required AgentTimelineExpansionLookup expansion,
    bool precededByOperationGroup = false,
    bool followedByOperationGroup = false,
  }) {
    final metrics = AgentTimelineExtentMetrics.from(
      crossAxisExtent: crossAxisExtent,
      textScale: textScale,
    );

    return switch (item) {
      AgentLiveActivityViewportItem() => 36 * metrics.scale,
      AgentTurnFooterViewportItem() => 28 * metrics.scale,
      AgentBlockViewportItem(:final block) =>
        registry
            .resolve(block)
            .estimateExtent(
              AgentTimelineRendererRegistry.payloadOf(block),
              crossAxisExtent: crossAxisExtent,
              textScale: textScale,
              expansion: expansion,
              precededByOperationGroup: precededByOperationGroup,
              followedByOperationGroup: followedByOperationGroup,
            ),
    };
  }

  static bool _descriptorFingerprintEquals(
    IdeVirtualItemDescriptor a,
    IdeVirtualItemDescriptor b,
  ) {
    return a.id == b.id &&
        a.kind == b.kind &&
        a.layoutRevision == b.layoutRevision &&
        a.estimatedExtent == b.estimatedExtent;
  }
}

/// 上一视口项是否为操作组（命令集 / 文件编辑组）。
bool _isPrecededByOperationGroup(AgentTimelineViewportItem? item) {
  return item is AgentBlockViewportItem &&
      isAgentTimelineOperationGroupBlock(item.block);
}
