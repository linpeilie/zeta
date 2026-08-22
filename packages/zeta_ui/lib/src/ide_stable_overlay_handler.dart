import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Zeta 的桌面 Popover 稳定性适配层。
///
/// `shadcn_flutter 0.0.53` 的锚点 follow 路径会在极短暂的窗口/Overlay
/// 变换不可逆时把非法矩阵留给 [sf.PopoverLayoutRender] 命中测试。该异常发生在
/// Flutter MouseTracker 的 device update 内，会进一步污染调试状态并持续刷出
/// `_debugDuringDeviceUpdate` 断言。
///
/// Zeta 的弹层都是短生命周期桌面交互。这里统一使用打开瞬间的锚点位置，并拦截
/// OverlayController 的后续配置更新，确保第三方 follow 路径不会被重新开启。
class IdeStablePopoverOverlayHandler implements sf.OverlayHandler {
  const IdeStablePopoverOverlayHandler({
    sf.OverlayHandler delegate = const sf.PopoverOverlayHandler(),
  }) : this._(delegate);

  const IdeStablePopoverOverlayHandler._(this._delegate);

  final sf.OverlayHandler _delegate;

  @override
  sf.OverlayCompleter<T?> show<T>({
    required BuildContext context,
    required AlignmentGeometry alignment,
    required WidgetBuilder builder,
    Offset? position,
    AlignmentGeometry? anchorAlignment,
    sf.PopoverConstraint widthConstraint = sf.PopoverConstraint.flexible,
    sf.PopoverConstraint heightConstraint = sf.PopoverConstraint.flexible,
    Key? key,
    bool rootOverlay = true,
    bool modal = true,
    bool barrierDismissable = true,
    Clip clipBehavior = Clip.none,
    Object? regionGroupId,
    Offset? offset,
    AlignmentGeometry? transitionAlignment,
    EdgeInsetsGeometry? margin,
    bool follow = true,
    bool consumeOutsideTaps = true,
    sf.Anchor? anchor,
    ValueChanged<sf.PopoverOverlayWidgetState>? onTickFollow,
    bool allowInvertHorizontal = true,
    bool allowInvertVertical = true,
    bool dismissBackdropFocus = true,
    Duration? showDuration,
    Duration? dismissDuration,
    sf.OverlayBarrier? overlayBarrier,
  }) {
    final completer = _delegate.show<T>(
      context: context,
      alignment: alignment,
      builder: builder,
      position: position,
      anchorAlignment: anchorAlignment,
      widthConstraint: widthConstraint,
      heightConstraint: heightConstraint,
      key: key,
      rootOverlay: rootOverlay,
      modal: modal,
      barrierDismissable: barrierDismissable,
      clipBehavior: clipBehavior,
      regionGroupId: regionGroupId,
      offset: offset,
      transitionAlignment: transitionAlignment,
      margin: margin,
      follow: false,
      consumeOutsideTaps: consumeOutsideTaps,
      anchor: anchor,
      onTickFollow: null,
      allowInvertHorizontal: allowInvertHorizontal,
      allowInvertVertical: allowInvertVertical,
      dismissBackdropFocus: dismissBackdropFocus,
      showDuration: showDuration,
      dismissDuration: dismissDuration,
      overlayBarrier: overlayBarrier,
    );
    return _StableOverlayCompleter<T>(completer);
  }
}

/// 应用根和组件测试共用同一个无状态 handler。
const ideStablePopoverOverlayHandler = IdeStablePopoverOverlayHandler();

class _StableOverlayCompleter<T> implements sf.OverlayCompleter<T?> {
  const _StableOverlayCompleter(this._delegate);

  final sf.OverlayCompleter<T?> _delegate;

  @override
  sf.OverlayConfiguration? get config => _delegate.config;

  @override
  set config(sf.OverlayConfiguration? value) {
    _delegate.config = _withoutAnchorFollowing(value);
  }

  @override
  bool get isCompleted => _delegate.isCompleted;

  @override
  bool get isAnimationCompleted => _delegate.isAnimationCompleted;

  @override
  Future<T?> get future => _delegate.future;

  @override
  Future<void> get animationFuture => _delegate.animationFuture;

  @override
  Future<void> close([bool immediate = false]) => _delegate.close(immediate);

  @override
  void closeLater() => _delegate.closeLater();

  @override
  Future<void> closeWithResult<X>([X? value]) =>
      _delegate.closeWithResult(value);

  @override
  void dispose() => _delegate.dispose();

  @override
  void remove() => _delegate.remove();
}

sf.OverlayConfiguration? _withoutAnchorFollowing(
  sf.OverlayConfiguration? configuration,
) {
  return switch (configuration) {
    sf.PopoverConfiguration<dynamic>() => configuration.copyWith(
      follow: () => false,
      onTickFollow: () => null,
    ),
    sf.MenuConfiguration<dynamic>() => sf.MenuConfiguration<dynamic>(
      builder: configuration.builder,
      alignment: configuration.alignment,
      position: configuration.position,
      anchorAlignment: configuration.anchorAlignment,
      widthConstraint: configuration.widthConstraint,
      heightConstraint: configuration.heightConstraint,
      rootOverlay: configuration.rootOverlay,
      modal: configuration.modal,
      barrierDismissable: configuration.barrierDismissable,
      clipBehavior: configuration.clipBehavior,
      offset: configuration.offset,
      follow: false,
      overlayBarrier: configuration.overlayBarrier,
      key: configuration.key,
    ),
    sf.TooltipConfiguration<dynamic>() => sf.TooltipConfiguration<dynamic>(
      builder: configuration.builder,
      alignment: configuration.alignment,
      position: configuration.position,
      anchorAlignment: configuration.anchorAlignment,
      offset: configuration.offset,
      follow: false,
      key: configuration.key,
    ),
    _ => configuration,
  };
}
