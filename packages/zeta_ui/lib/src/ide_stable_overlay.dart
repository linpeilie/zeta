import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Zeta 的桌面弹层稳定性适配层。
///
/// `shadcn_flutter` 的锚点 follow 路径会在极短暂的窗口/Overlay 变换不可逆时把
/// 非法矩阵留给 [sf.PopoverLayoutRender] 命中测试。该异常发生在 Flutter
/// MouseTracker 的 device update 内，会进一步污染调试状态并持续刷出
/// `_debugDuringDeviceUpdate` 断言。
///
/// Zeta 的弹层都是短生命周期桌面交互，用打开瞬间的锚点位置就够了，因此统一
/// 关掉 follow。
///
/// 0.0.54 之前这里是一个插在 `ShadcnApp.popoverHandler` / `tooltipHandler` /
/// `menuHandler` 上的 `OverlayHandler`，能一次性覆盖全应用。0.0.54 删掉了
/// `OverlayHandler` / `OverlayManager` 这一层间接，follow 变成
/// [sf.OverlayConfiguration] 自己的字段，那三个扩展点也随之消失。所以改成在
/// zeta 自己的弹层入口上显式套一层：`showIdePopover`、`IdeSelect` 的弹层配置、
/// 以及 pane tooltip。
///
/// 这也意味着**新增弹层入口时要记得套上**——库层不再有兜底。
sf.OverlayConfiguration ideStableOverlayConfiguration(
  sf.OverlayConfiguration configuration,
) {
  return switch (configuration) {
    final sf.PopoverConfiguration configuration => configuration.copyWith(
      follow: () => false,
      onTickFollow: () => null,
    ),
    // Menu / Tooltip 没有 copyWith，只能逐字段重建。
    final sf.MenuConfiguration configuration => sf.MenuConfiguration(
      alignment: configuration.alignment,
      position: configuration.position,
      anchorAlignment: configuration.anchorAlignment,
      widthConstraint: configuration.widthConstraint,
      heightConstraint: configuration.heightConstraint,
      key: configuration.key,
      rootOverlay: configuration.rootOverlay,
      modal: configuration.modal,
      barrierDismissable: configuration.barrierDismissable,
      clipBehavior: configuration.clipBehavior,
      regionGroupId: configuration.regionGroupId,
      offset: configuration.offset,
      transitionAlignment: configuration.transitionAlignment,
      margin: configuration.margin,
      follow: false,
      consumeOutsideTaps: configuration.consumeOutsideTaps,
      onTickFollow: null,
      allowInvertHorizontal: configuration.allowInvertHorizontal,
      allowInvertVertical: configuration.allowInvertVertical,
      dismissBackdropFocus: configuration.dismissBackdropFocus,
      showDuration: configuration.showDuration,
      dismissDuration: configuration.dismissDuration,
      overlayBarrier: configuration.overlayBarrier,
    ),
    final sf.TooltipConfiguration configuration => sf.TooltipConfiguration(
      anchor: configuration.anchor,
      alignment: configuration.alignment,
      position: configuration.position,
      anchorAlignment: configuration.anchorAlignment,
      offset: configuration.offset,
      follow: false,
      key: configuration.key,
      showDuration: configuration.showDuration,
      dismissDuration: configuration.dismissDuration,
    ),
    _ => configuration,
  };
}
