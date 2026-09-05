import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_motion.dart';
import 'ide_spacing.dart';
import 'ide_stable_overlay.dart';

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
  IdePopoverHandle._(this._delegate) {
    unawaited(_forwardResult());
  }

  final sf.OverlayCompleter<T?> _delegate;
  final Completer<T?> _result = Completer<T?>();
  final Completer<void> _animation = Completer<void>();
  final Completer<void> _stopForwarding = Completer<void>();

  bool get isCompleted => _result.isCompleted;

  bool get isAnimationCompleted => _animation.isCompleted;

  Future<T?> get future => _result.future;

  Future<void> get animationFuture => _animation.future;

  /// 通过底层 completer 关闭弹层，确保结果 Future 与退出动画正常收尾。
  ///
  /// 0.0.53 起 [sf.OverlayCompleter.close] 已负责动画关闭；若弹层尚未挂载
  /// 导致 close 空操作，再退回 `remove()` 并由本句柄补齐完成语义。
  void dismiss() {
    if (_result.isCompleted) {
      return;
    }
    unawaited(() async {
      await _delegate.close();
      if (_result.isCompleted || _delegate.isCompleted) {
        return;
      }
      _delegate.remove();
      _delegate.dispose();
      _stopForwardingIfNeeded();
      _completeAnimation();
      _complete(null);
    }());
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

/// 锚点弹层完成视口裁剪后的布局信息。
@immutable
class IdePopoverLayout {
  const IdePopoverLayout({
    required this.openAbove,
    required this.width,
    required this.maxHeight,
  });

  final bool openAbove;
  final double width;
  final double maxHeight;
}

/// 锚点弹层内容构造器。
typedef IdeAnchoredPopoverBuilder =
    Widget Function(BuildContext context, IdePopoverLayout layout);

/// 管理桌面锚点弹层生命周期、定位与触发器焦点恢复。
///
/// 业务 Widget 只持有本控制器，不需要重复保存 overlay handle、计算上下
/// 空间或在退出动画完成后恢复键盘焦点。
class IdePopoverController {
  IdePopoverController({
    required this.triggerFocusNode,
    required this.onOpenChanged,
    this.onClosed,
  });

  final FocusNode triggerFocusNode;
  final VoidCallback onOpenChanged;
  final VoidCallback? onClosed;

  IdePopoverHandle<void>? _handle;
  bool _disposed = false;

  bool get isOpen => _handle != null;

  IdePopoverHandle<void>? get handle => _handle;

  void toggle({
    required BuildContext context,
    required double preferredWidth,
    required double preferredMaxHeight,
    required IdeAnchoredPopoverBuilder builder,
    double minimumSpaceBelow = 180,
    Key? key,
  }) {
    if (isOpen) {
      dismiss();
      return;
    }
    show(
      context: context,
      preferredWidth: preferredWidth,
      preferredMaxHeight: preferredMaxHeight,
      minimumSpaceBelow: minimumSpaceBelow,
      key: key,
      builder: builder,
    );
  }

  void show({
    required BuildContext context,
    required double preferredWidth,
    required double preferredMaxHeight,
    required IdeAnchoredPopoverBuilder builder,
    double minimumSpaceBelow = 180,
    Key? key,
  }) {
    if (_disposed || isOpen) {
      return;
    }
    final entry = _showIdeAnchoredPopover(
      context: context,
      preferredWidth: preferredWidth,
      preferredMaxHeight: preferredMaxHeight,
      minimumSpaceBelow: minimumSpaceBelow,
      key: key,
      builder: builder,
    );
    _handle = entry;
    onOpenChanged();
    unawaited(
      entry.future.whenComplete(() {
        entry.dispose();
        if (_disposed || !identical(_handle, entry)) {
          return;
        }
        _handle = null;
        onClosed?.call();
        onOpenChanged();
        if (triggerFocusNode.canRequestFocus) {
          triggerFocusNode.requestFocus();
        }
      }),
    );
  }

  void dismiss([IdePopoverHandle<void>? expectedHandle]) {
    final entry = _handle;
    if (entry == null ||
        (expectedHandle != null && !identical(entry, expectedHandle))) {
      return;
    }
    entry.dismiss();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final entry = _handle;
    _handle = null;
    entry?.dismiss();
  }
}

IdePopoverHandle<void> _showIdeAnchoredPopover({
  required BuildContext context,
  required double preferredWidth,
  required double preferredMaxHeight,
  required double minimumSpaceBelow,
  required IdeAnchoredPopoverBuilder builder,
  Key? key,
}) {
  final mediaQuery = MediaQuery.of(context);
  final viewport = mediaQuery.size;
  final renderObject = context.findRenderObject();
  final renderBox = renderObject is RenderBox && renderObject.hasSize
      ? renderObject
      : null;
  final origin = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
  final triggerHeight = renderBox?.size.height ?? 28;
  final viewportTop = mediaQuery.padding.top;
  final viewportBottom = viewport.height - mediaQuery.padding.bottom;
  final spaceAbove = math.max(0.0, origin.dy - viewportTop);
  final spaceBelow = math.max(0.0, viewportBottom - origin.dy - triggerHeight);
  final openAbove = spaceAbove > spaceBelow && spaceBelow < minimumSpaceBelow;
  final availableHeight =
      (openAbove ? spaceAbove : spaceBelow) -
      IdeSpacing.space6 -
      IdeSpacing.space12;
  final layout = IdePopoverLayout(
    openAbove: openAbove,
    width: math.max(
      1,
      math.min(preferredWidth, viewport.width - IdeSpacing.space12 * 2),
    ),
    maxHeight: math.max(1, math.min(preferredMaxHeight, availableHeight)),
  );
  final duration = MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : IdeMotion.durationFast;
  return showIdePopover<void>(
    context: context,
    alignment: openAbove ? Alignment.bottomLeft : Alignment.topLeft,
    anchorAlignment: openAbove ? Alignment.topLeft : Alignment.bottomLeft,
    widthConstraint: IdePopoverConstraint.intrinsic,
    heightConstraint: IdePopoverConstraint.flexible,
    key: key,
    offset: Offset(0, openAbove ? -IdeSpacing.space6 : IdeSpacing.space6),
    transitionAlignment: openAbove ? Alignment.bottomLeft : Alignment.topLeft,
    margin: const EdgeInsets.all(IdeSpacing.space12),
    allowInvertVertical: false,
    showDuration: duration,
    dismissDuration: duration,
    // rootOverlay 的 context 不一定继承锚点所在的 MediaQuery；显式保留字号、
    // 安全区与 reduced-motion，避免弹层内容回退到应用根配置。
    builder: (context) =>
        MediaQuery(data: mediaQuery, child: builder(context, layout)),
  );
}

/// 与选择菜单表面一致的通用弹层容器。
class IdePopoverPanel extends StatelessWidget {
  const IdePopoverPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return sf.Card(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// IDE 统一 popover 入口。
///
/// 当前底层实现委托给 `shadcn_flutter` 的 [sf.showOverlay] /
/// [sf.PopoverConfiguration]；调用方不应再直接依赖这些类型。
///
/// [adaptive] 默认关闭：桌面 IDE 始终使用真实 popover，避免移动端自适应
/// 把 popover 转成 bottom drawer。
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
  bool adaptive = false,
}) {
  final delegate = sf.showOverlay<T>(
    context,
    ideStableOverlayConfiguration(
      sf.PopoverConfiguration(
        alignment: alignment,
        anchorAlignment: anchorAlignment,
        widthConstraint: _toSfConstraint(widthConstraint),
        heightConstraint: _toSfConstraint(heightConstraint),
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
      ),
    ),
    builder: key == null
        ? builder
        : (context) => KeyedSubtree(key: key, child: builder(context)),
    adaptive: adaptive,
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
