import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Width and height policies for an IDE popover.
enum IdePopoverConstraint {
  /// Flexible within available space.
  flexible,

  /// Fit intrinsic content size.
  intrinsic,

  /// Match the anchor size.
  anchorFixedSize,

  /// Use the anchor as a minimum.
  anchorMinSize,

  /// Use the anchor as a maximum.
  anchorMaxSize,
}

/// UI-library-neutral handle for one IDE popover.
class IdePopoverHandle<T> {
  IdePopoverHandle._(this._delegate) {
    unawaited(_forwardResult());
  }

  /// Creates a handle around a test double without exposing it in app code.
  @visibleForTesting
  factory IdePopoverHandle.debugFromDelegate(Object delegate) {
    return IdePopoverHandle<T>._(delegate as sf.OverlayCompleter<T?>);
  }

  final sf.OverlayCompleter<T?> _delegate;
  final Completer<T?> _result = Completer<T?>();
  final Completer<void> _animation = Completer<void>();
  final Completer<void> _stopForwarding = Completer<void>();

  /// Whether the result future has completed.
  bool get isCompleted => _result.isCompleted;

  /// Whether the exit animation has completed.
  bool get isAnimationCompleted => _animation.isCompleted;

  /// Result completed after the popover has left the widget tree.
  Future<T?> get future => _result.future;

  /// Completes after the popover exit animation.
  Future<void> get animationFuture => _animation.future;

  /// Dismisses the popover and supplies a null result.
  void dismiss() {
    if (_result.isCompleted) return;
    unawaited(() async {
      await _delegate.close();
      if (_result.isCompleted || _delegate.isCompleted) return;
      _delegate
        ..remove()
        ..dispose();
      _stopForwardingIfNeeded();
      _completeAnimation();
      _complete(null);
    }());
  }

  /// Stops forwarding and releases the underlying handle.
  void dispose() {
    _stopForwardingIfNeeded();
    _delegate.dispose();
  }

  void _complete(T? value) {
    if (!_result.isCompleted) _result.complete(value);
  }

  Future<void> _forwardResult() async {
    try {
      final outcome = await Future.any<(bool, T?)>(<Future<(bool, T?)>>[
        _delegate.future.then((value) => (true, value)),
        _stopForwarding.future.then((_) => (false, null)),
      ]);
      if (!outcome.$1) return;
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
    if (!_animation.isCompleted) _animation.complete();
  }

  void _stopForwardingIfNeeded() {
    if (!_stopForwarding.isCompleted) _stopForwarding.complete();
  }
}

/// Shows a non-adaptive desktop popover.
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
    sf.PopoverConfiguration(
      alignment: alignment,
      builder: key == null
          ? builder
          : (context) => KeyedSubtree(key: key, child: builder(context)),
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
