import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// A desktop popover handler that disables unstable anchor following.
///
/// `shadcn_flutter 0.0.53` may retain an invalid transform when an anchor and
/// overlay are briefly non-invertible during a desktop window transition. This
/// wrapper freezes the opening position and also sanitizes later controller
/// configuration updates.
class IdeStablePopoverOverlayHandler implements sf.OverlayHandler {
  /// Creates a stable wrapper around [delegate].
  const IdeStablePopoverOverlayHandler({
    this.delegate = const sf.PopoverOverlayHandler(),
  });

  /// Underlying shadcn overlay implementation.
  final sf.OverlayHandler delegate;

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
    final completer = delegate.show<T>(
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

/// Shared stateless handler for application roots and component tests.
const ideStablePopoverOverlayHandler = IdeStablePopoverOverlayHandler();

class _StableOverlayCompleter<T> implements sf.OverlayCompleter<T?> {
  const _StableOverlayCompleter(this._delegate);

  final sf.OverlayCompleter<T?> _delegate;

  @override
  sf.OverlayConfiguration<dynamic>? get config => _delegate.config;

  @override
  set config(sf.OverlayConfiguration<dynamic>? value) {
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
  Future<void> closeWithResult<X>([X? value]) {
    return _delegate.closeWithResult(value);
  }

  @override
  void dispose() => _delegate.dispose();

  @override
  void remove() => _delegate.remove();
}

sf.OverlayConfiguration<dynamic>? _withoutAnchorFollowing(
  sf.OverlayConfiguration<dynamic>? configuration,
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
