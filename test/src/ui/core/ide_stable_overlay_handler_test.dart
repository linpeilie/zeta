import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/ui/core/ide_stable_overlay_handler.dart';

void main() {
  testWidgets('stable overlay handler disables initial anchor following', (
    tester,
  ) async {
    final delegate = _RecordingOverlayHandler();
    final handler = IdeStablePopoverOverlayHandler(delegate: delegate);
    late BuildContext context;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    handler.show<void>(
      context: context,
      alignment: Alignment.bottomCenter,
      builder: (_) => const SizedBox(),
      follow: true,
      onTickFollow: (_) {},
    );

    expect(delegate.follow, isFalse);
    expect(delegate.onTickFollow, isNull);
  });

  testWidgets('stable overlay completer keeps live configurations static', (
    tester,
  ) async {
    final delegate = _RecordingOverlayHandler();
    final handler = IdeStablePopoverOverlayHandler(delegate: delegate);
    late BuildContext context;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    final completer = handler.show<void>(
      context: context,
      alignment: Alignment.bottomCenter,
      builder: (_) => const SizedBox(),
    );

    completer.config = sf.PopoverConfiguration<void>(
      alignment: Alignment.bottomCenter,
      builder: (_) => const SizedBox(),
      follow: true,
      onTickFollow: (_) {},
    );
    expect(
      (delegate.updatedConfiguration as sf.PopoverConfiguration<dynamic>)
          .follow,
      isFalse,
    );
    expect(
      (delegate.updatedConfiguration as sf.PopoverConfiguration<dynamic>)
          .onTickFollow,
      isNull,
    );

    completer.config = sf.MenuConfiguration<void>(
      builder: (_) => const SizedBox(),
      follow: true,
    );
    expect(
      (delegate.updatedConfiguration as sf.MenuConfiguration<dynamic>).follow,
      isFalse,
    );

    completer.config = sf.TooltipConfiguration<void>(
      builder: (_) => const SizedBox(),
      follow: true,
    );
    expect(
      (delegate.updatedConfiguration as sf.TooltipConfiguration<dynamic>)
          .follow,
      isFalse,
    );
  });
}

class _RecordingOverlayHandler implements sf.OverlayHandler {
  bool? follow;
  ValueChanged<sf.PopoverOverlayWidgetState>? onTickFollow;
  sf.OverlayConfiguration? updatedConfiguration;

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
    this.follow = follow;
    this.onTickFollow = onTickFollow;
    return _RecordingOverlayCompleter<T>(
      onConfigChanged: (value) => updatedConfiguration = value,
    );
  }
}

class _RecordingOverlayCompleter<T> implements sf.OverlayCompleter<T?> {
  _RecordingOverlayCompleter({required this.onConfigChanged});

  final ValueChanged<sf.OverlayConfiguration?> onConfigChanged;
  final Completer<T?> _result = Completer<T?>();

  @override
  sf.OverlayConfiguration? get config => null;

  @override
  set config(sf.OverlayConfiguration? value) => onConfigChanged(value);

  @override
  bool get isCompleted => _result.isCompleted;

  @override
  bool get isAnimationCompleted => true;

  @override
  Future<T?> get future => _result.future;

  @override
  Future<void> get animationFuture => Future<void>.value();

  @override
  Future<void> close([bool immediate = false]) async => remove();

  @override
  void closeLater() => remove();

  @override
  Future<void> closeWithResult<X>([X? value]) async => remove();

  @override
  void dispose() {}

  @override
  void remove() {
    if (!_result.isCompleted) {
      _result.complete();
    }
  }
}
