import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import '../../helpers/helpers.dart';

void main() {
  for (final constraint in IdePopoverConstraint.values) {
    testWidgets('showIdePopover maps and completes $constraint', (
      tester,
    ) async {
      IdePopoverHandle<int>? handle;
      await tester.pumpShadcnApp(
        Builder(
          builder: (context) => IdeButton(
            label: 'Show',
            onPressed: () {
              handle = showIdePopover<int>(
                context: context,
                alignment: Alignment.bottomCenter,
                anchorAlignment: Alignment.topCenter,
                widthConstraint: constraint,
                heightConstraint: constraint,
                key: constraint == IdePopoverConstraint.flexible
                    ? null
                    : ValueKey<IdePopoverConstraint>(constraint),
                rootOverlay: false,
                modal: false,
                barrierDismissible: false,
                clipBehavior: Clip.hardEdge,
                offset: const Offset(1, 2),
                margin: const EdgeInsets.all(4),
                follow: false,
                consumeOutsideTaps: false,
                allowInvertHorizontal: false,
                allowInvertVertical: false,
                dismissBackdropFocus: false,
                transitionAlignment: Alignment.topCenter,
                showDuration: Duration.zero,
                dismissDuration: Duration.zero,
                builder: (popoverContext) => IdeButton(
                  label: 'Close $constraint',
                  onPressed: () => unawaited(
                    sf.closeOverlay<int>(popoverContext, constraint.index),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pump();
      expect(handle, isNotNull);
      expect(handle?.isCompleted, isFalse);
      await tester.tap(find.text('Close $constraint'));
      await tester.pump();
      expect(await handle?.future, constraint.index);
      expect(handle?.isCompleted, isTrue);
      expect(handle?.isAnimationCompleted, isTrue);
      await handle?.animationFuture;
      handle?.dismiss();
    });
  }

  test('IdePopoverHandle falls back when delegate close is a no-op', () async {
    final delegate = _FakePopoverCompleter<int?>();
    final handle = IdePopoverHandle<int>.debugFromDelegate(delegate)..dismiss();
    expect(await handle.future, isNull);
    await handle.animationFuture;
    expect(delegate.removeCalls, 1);
    expect(delegate.disposeCalls, 1);
    handle.dismiss();
  });

  test('IdePopoverHandle forwards delayed animation and value', () async {
    final delegate = _FakePopoverCompleter<int?>();
    final handle = IdePopoverHandle<int>.debugFromDelegate(delegate);

    delegate.result.complete(7);
    await Future<void>.delayed(Duration.zero);
    expect(handle.isCompleted, isFalse);
    delegate.animation.complete();
    expect(await handle.future, 7);
    expect(handle.isAnimationCompleted, isTrue);
  });

  test('IdePopoverHandle forwards errors and supports disposal', () async {
    final errorDelegate = _FakePopoverCompleter<int?>();
    final errorHandle = IdePopoverHandle<int>.debugFromDelegate(errorDelegate);
    errorDelegate.result.completeError(StateError('overlay failed'));
    await expectLater(errorHandle.future, throwsStateError);
    await errorHandle.animationFuture;

    final disposedDelegate = _FakePopoverCompleter<int?>();
    final disposedHandle = IdePopoverHandle<int>.debugFromDelegate(
      disposedDelegate,
    )..dispose();
    await Future<void>.delayed(Duration.zero);
    expect(disposedDelegate.disposeCalls, 1);
    expect(disposedHandle.isCompleted, isFalse);
  });

  test('IdePopoverHandle forwards an already-finished animation', () async {
    final delegate = _FakePopoverCompleter<int?>();
    delegate.animation.complete();
    final handle = IdePopoverHandle<int>.debugFromDelegate(delegate);
    delegate.result.complete(3);
    expect(await handle.future, 3);
    expect(handle.isAnimationCompleted, isTrue);
  });
}

class _FakePopoverCompleter<T> implements sf.OverlayCompleter<T> {
  final Completer<T> result = Completer<T>();
  final Completer<void> animation = Completer<void>();
  int removeCalls = 0;
  int disposeCalls = 0;

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
  Future<void> close([bool immediate = false]) async {}

  @override
  void closeLater() {}

  @override
  Future<void> closeWithResult<X>([X? value]) async {}

  @override
  void dispose() => disposeCalls += 1;

  @override
  void remove() => removeCalls += 1;
}
