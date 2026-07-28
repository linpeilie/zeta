import 'dart:async';

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
  IdePopoverHandle._(this._delegate, this._stateKey) {
    unawaited(_forwardResult());
  }

  final sf.OverlayCompleter<T?> _delegate;
  final GlobalKey<sf.OverlayHandlerStateMixin> _stateKey;
  final Completer<T?> _result = Completer<T?>();
  final Completer<void> _animation = Completer<void>();
  final Completer<void> _stopForwarding = Completer<void>();

  bool get isCompleted => _result.isCompleted;

  bool get isAnimationCompleted => _animation.isCompleted;

  Future<T?> get future => _result.future;

  Future<void> get animationFuture => _animation.future;

  /// 通过底层状态机关闭弹层，确保结果 Future 与退出动画正常收尾。
  ///
  /// 第三方 completer 的 `remove()` 只移除 Overlay，并不会完成 `future`；
  /// 因此仅在弹层尚未挂载时将其作为兜底，并由本句柄补齐完成语义。
  void dismiss() {
    if (_result.isCompleted) {
      return;
    }
    final state = _stateKey.currentState;
    if (state != null) {
      unawaited(state.close());
      return;
    }
    _delegate.remove();
    _delegate.dispose();
    _stopForwardingIfNeeded();
    _completeAnimation();
    _complete(null);
  }

  void dispose() {
    _stopForwardingIfNeeded();
    _delegate.dispose();
  }

  void _complete(T? value) {
    if (!_result.isCompleted) {
      _result.complete(value);
    }
  }

  Future<void> _forwardResult() async {
    try {
      final outcome = await Future.any<(bool, T?)>(<Future<(bool, T?)>>[
        _delegate.future.then((value) => (true, value)),
        _stopForwarding.future.then((_) => (false, null)),
      ]);
      if (!outcome.$1) {
        return;
      }
      // 底层 result 会在退出动画开始时完成；等待 Overlay 真正移除后再让
      // 业务层清理句柄，避免提前 dispose 令弹层停留在树上。
      if (!_delegate.isAnimationCompleted) {
        await _delegate.animationFuture;
      }
      _completeAnimation();
      _complete(outcome.$2);
    } catch (error, stackTrace) {
      _completeAnimation();
      if (!_result.isCompleted) {
        _result.completeError(error, stackTrace);
      }
    }
  }

  void _completeAnimation() {
    if (!_animation.isCompleted) {
      _animation.complete();
    }
  }

  void _stopForwardingIfNeeded() {
    if (!_stopForwarding.isCompleted) {
      _stopForwarding.complete();
    }
  }
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
  AlignmentGeometry? transitionAlignment,
  Duration? showDuration,
  Duration? dismissDuration,
}) {
  final stateKey = GlobalKey<sf.OverlayHandlerStateMixin>(
    debugLabel: 'IdePopoverOverlay',
  );
  final delegate = sf.showPopover<T>(
    context: context,
    alignment: alignment,
    builder: key == null
        ? builder
        : (context) => KeyedSubtree(key: key, child: builder(context)),
    anchorAlignment: anchorAlignment,
    widthConstraint: _toSfConstraint(widthConstraint),
    heightConstraint: _toSfConstraint(heightConstraint),
    key: stateKey,
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
    transitionAlignment: transitionAlignment,
    showDuration: showDuration,
    dismissDuration: dismissDuration,
  );
  return IdePopoverHandle<T>._(delegate, stateKey);
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
