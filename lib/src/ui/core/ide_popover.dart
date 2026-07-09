import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// IDE 统一 popover 宽高约束语义。
enum IdePopoverConstraint {
  flexible,
  intrinsic,
  anchorFixedSize,
  anchorMinSize,
  anchorMaxSize,
}

/// IDE 统一 popover 句柄。
///
/// 对业务层隐藏第三方 overlay completer 类型；后续若切换 UI 库，
/// 调用方继续依赖本类型即可。
class IdePopoverHandle<T> {
  IdePopoverHandle._(this._delegate);

  final sf.OverlayCompleter<T?> _delegate;

  bool get isCompleted => _delegate.isCompleted;

  bool get isAnimationCompleted => _delegate.isAnimationCompleted;

  Future<T?> get future => _delegate.future;

  Future<void> get animationFuture => _delegate.animationFuture;

  void dismiss() => _delegate.remove();

  void dispose() => _delegate.dispose();
}

/// IDE 统一 popover 入口。
///
/// 当前底层实现委托给 `shadcn_flutter`；调用方不应再直接依赖
/// `sf.showPopover`、`sf.OverlayCompleter` 或 `sf.PopoverConstraint`。
IdePopoverHandle<T> showIdePopover<T>({
  required BuildContext context,
  required AlignmentGeometry alignment,
  required WidgetBuilder builder,
  AlignmentGeometry? anchorAlignment,
  IdePopoverConstraint widthConstraint = IdePopoverConstraint.flexible,
  IdePopoverConstraint heightConstraint = IdePopoverConstraint.flexible,
  Key? key,
  bool rootOverlay = true,
  bool modal = true,
  bool barrierDismissible = true,
  Clip clipBehavior = Clip.none,
  Offset? offset,
  EdgeInsetsGeometry? margin,
  bool follow = true,
  bool consumeOutsideTaps = true,
  bool allowInvertHorizontal = true,
  bool allowInvertVertical = true,
  bool dismissBackdropFocus = true,
  Duration? showDuration,
  Duration? dismissDuration,
}) {
  final delegate = sf.showPopover<T>(
    context: context,
    alignment: alignment,
    builder: builder,
    anchorAlignment: anchorAlignment,
    widthConstraint: _toSfConstraint(widthConstraint),
    heightConstraint: _toSfConstraint(heightConstraint),
    key: key,
    rootOverlay: rootOverlay,
    modal: modal,
    barrierDismissable: barrierDismissible,
    clipBehavior: clipBehavior,
    offset: offset,
    margin: margin,
    follow: follow,
    consumeOutsideTaps: consumeOutsideTaps,
    allowInvertHorizontal: allowInvertHorizontal,
    allowInvertVertical: allowInvertVertical,
    dismissBackdropFocus: dismissBackdropFocus,
    showDuration: showDuration,
    dismissDuration: dismissDuration,
  );
  return IdePopoverHandle<T>._(delegate);
}

sf.PopoverConstraint _toSfConstraint(IdePopoverConstraint constraint) {
  return switch (constraint) {
    IdePopoverConstraint.flexible => sf.PopoverConstraint.flexible,
    IdePopoverConstraint.intrinsic => sf.PopoverConstraint.intrinsic,
    IdePopoverConstraint.anchorFixedSize =>
      sf.PopoverConstraint.anchorFixedSize,
    IdePopoverConstraint.anchorMinSize => sf.PopoverConstraint.anchorMinSize,
    IdePopoverConstraint.anchorMaxSize => sf.PopoverConstraint.anchorMaxSize,
  };
}
