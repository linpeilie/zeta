import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import '../../helpers/helpers.dart';

void main() {
  testWidgets('stable handler freezes following and forwards lifecycle', (
    tester,
  ) async {
    final delegate = _FakeOverlayHandler();
    final handler = IdeStablePopoverOverlayHandler(delegate: delegate);
    late _FakeOverlayCompleter<int?> fake;
    await tester.pumpShadcnApp(
      Builder(
        builder: (context) {
          final completer = handler.show<int>(
            context: context,
            alignment: Alignment.bottomCenter,
            builder: (_) => const Text('Overlay'),
            position: const Offset(1, 2),
            anchorAlignment: Alignment.topCenter,
            widthConstraint: sf.PopoverConstraint.intrinsic,
            heightConstraint: sf.PopoverConstraint.anchorMinSize,
            key: const Key('overlay'),
            rootOverlay: false,
            modal: false,
            barrierDismissable: false,
            clipBehavior: Clip.hardEdge,
            regionGroupId: 'region',
            offset: const Offset(3, 4),
            transitionAlignment: Alignment.center,
            margin: const EdgeInsets.all(8),
            consumeOutsideTaps: false,
            onTickFollow: (_) {},
            allowInvertHorizontal: false,
            allowInvertVertical: false,
            dismissBackdropFocus: false,
            showDuration: Duration.zero,
            dismissDuration: Duration.zero,
            overlayBarrier: const sf.OverlayBarrier(),
          );
          fake = delegate.latestCompleter! as _FakeOverlayCompleter<int?>;

          expect(delegate.follow, isFalse);
          expect(delegate.onTickFollow, isNull);
          expect(completer.isCompleted, isFalse);
          expect(completer.isAnimationCompleted, isFalse);
          expect(completer.future, same(fake.future));
          expect(
            completer.animationFuture,
            same(fake.animationFuture),
          );
          final close = completer.close;
          final closeWithResult = completer.closeWithResult<int>;
          unawaited(close());
          unawaited(close(true));
          unawaited(closeWithResult(7));
          completer
            ..closeLater()
            ..remove()
            ..dispose();
          return const SizedBox.shrink();
        },
      ),
    );

    expect(fake.closeLaterCalls, 1);
    expect(fake.removeCalls, 1);
    expect(fake.disposeCalls, 1);
    expect(fake.closeCalls, <bool>[false, true]);
    expect(fake.closeResults, <Object?>[7]);
  });

  testWidgets('stable handler sanitizes supported live configurations', (
    tester,
  ) async {
    final delegate = _FakeOverlayHandler();
    final handler = IdeStablePopoverOverlayHandler(delegate: delegate);
    late sf.OverlayCompleter<void> completer;
    late _FakeOverlayCompleter<void> fake;
    await tester.pumpShadcnApp(
      Builder(
        builder: (context) {
          completer = handler.show<void>(
            context: context,
            alignment: Alignment.center,
            builder: (_) => const Text('Overlay'),
          );
          fake = delegate.latestCompleter! as _FakeOverlayCompleter<void>;
          return const SizedBox.shrink();
        },
      ),
    );

    completer.config = sf.PopoverConfiguration<void>(
      alignment: Alignment.center,
      onTickFollow: (_) {},
      builder: (_) => const Text('Popover'),
    );
    final popover = fake.config! as sf.PopoverConfiguration<void>;
    expect(popover.follow, isFalse);
    expect(popover.onTickFollow, isNull);
    expect(completer.config, same(fake.config));

    completer.config = sf.MenuConfiguration<void>(
      builder: (_) => const Text('Menu'),
    );
    expect(
      (fake.config! as sf.MenuConfiguration<void>).follow,
      isFalse,
    );

    completer.config = sf.TooltipConfiguration<void>(
      builder: (_) => const Text('Tooltip'),
    );
    expect(
      (fake.config! as sf.TooltipConfiguration<void>).follow,
      isFalse,
    );

    final dialog = sf.DialogConfiguration<void>(
      builder: (_) => const Text('Dialog'),
    );
    completer.config = dialog;
    expect(fake.config, same(dialog));
    completer.config = null;
    expect(fake.config, isNull);
  });
}

class _FakeOverlayHandler implements sf.OverlayHandler {
  Object? latestCompleter;
  bool? follow;
  ValueChanged<sf.PopoverOverlayWidgetState>? onTickFollow;

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
    final completer = _FakeOverlayCompleter<T?>();
    latestCompleter = completer;
    return completer;
  }
}

class _FakeOverlayCompleter<T> implements sf.OverlayCompleter<T> {
  final Completer<T> result = Completer<T>();
  final Completer<void> animation = Completer<void>();
  final List<bool> closeCalls = <bool>[];
  final List<Object?> closeResults = <Object?>[];
  int closeLaterCalls = 0;
  int disposeCalls = 0;
  int removeCalls = 0;

  @override
  sf.OverlayConfiguration<dynamic>? config;

  @override
  Future<void> get animationFuture => animation.future;

  @override
  Future<T> get future => result.future;

  @override
  bool get isAnimationCompleted => animation.isCompleted;

  @override
  bool get isCompleted => result.isCompleted;

  @override
  Future<void> close([bool immediate = false]) async {
    closeCalls.add(immediate);
  }

  @override
  void closeLater() => closeLaterCalls += 1;

  @override
  Future<void> closeWithResult<X>([X? value]) async {
    closeResults.add(value);
  }

  @override
  void dispose() => disposeCalls += 1;

  @override
  void remove() => removeCalls += 1;
}
