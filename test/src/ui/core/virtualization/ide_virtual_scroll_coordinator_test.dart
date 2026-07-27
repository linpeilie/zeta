import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/virtualization/ide_virtual_scroll_coordinator.dart';

void main() {
  group('19.4 IdeVirtualScrollCoordinator', () {
    late _FakeScrollDriver driver;
    late List<VoidCallback> pendingFrames;
    late IdeVirtualScrollCoordinator coordinator;

    setUp(() {
      driver = _FakeScrollDriver(maxScrollExtent: 1000);
      pendingFrames = <VoidCallback>[];
      coordinator = IdeVirtualScrollCoordinator(
        driver: driver,
        scheduleFrame: pendingFrames.add,
      );
    });

    void flushFrames() {
      final frames = List<VoidCallback>.of(pendingFrames);
      pendingFrames.clear();
      for (final frame in frames) {
        frame();
      }
    }

    IdeVirtualScrollMetricsSnapshot metrics({
      required double pixels,
      double max = 1000,
      double viewport = 600,
    }) {
      return IdeVirtualScrollMetricsSnapshot(
        pixels: pixels,
        maxScrollExtent: max,
        viewportDimension: viewport,
      );
    }

    test('初始 followEnd', () {
      expect(coordinator.mode, IdeVirtualScrollMode.followEnd);
    });

    test('用户上滚超过 48px 进入 free', () {
      coordinator.onUserScroll(metrics(pixels: 1000 - 49));
      expect(coordinator.mode, IdeVirtualScrollMode.free);
    });

    test('用户在 8px 内重新进入 followEnd', () {
      coordinator.onUserScroll(metrics(pixels: 900));
      expect(coordinator.mode, IdeVirtualScrollMode.free);

      coordinator.onUserScroll(metrics(pixels: 1000 - 8));
      expect(coordinator.mode, IdeVirtualScrollMode.followEnd);
    });

    test('correction 不改变模式', () {
      coordinator.onUserScroll(metrics(pixels: 900));
      expect(coordinator.mode, IdeVirtualScrollMode.free);

      coordinator.onAnchorCorrection();
      expect(coordinator.mode, IdeVirtualScrollMode.free);

      coordinator.onUserScroll(metrics(pixels: 995));
      expect(coordinator.mode, IdeVirtualScrollMode.followEnd);
      coordinator.onAnchorCorrection();
      expect(coordinator.mode, IdeVirtualScrollMode.followEnd);
    });

    test('programmatic reveal 不改变模式', () {
      coordinator.onUserScroll(metrics(pixels: 900));
      expect(coordinator.mode, IdeVirtualScrollMode.free);

      coordinator.beginProgrammaticScroll();
      coordinator.onUserScroll(metrics(pixels: 1000));
      coordinator.onProgrammaticReveal();
      coordinator.endProgrammaticScroll();

      expect(coordinator.mode, IdeVirtualScrollMode.free);
    });

    test('free 模式收到 100 次 autoScroll tick 不滚到底', () {
      coordinator.onUserScroll(metrics(pixels: 100));
      expect(coordinator.mode, IdeVirtualScrollMode.free);
      driver.pixels = 100;

      for (var i = 0; i < 100; i++) {
        coordinator.onAutoScrollTick(lastItemId: 'live-$i');
      }
      flushFrames();

      expect(coordinator.mode, IdeVirtualScrollMode.free);
      expect(driver.jumpCount, 0);
      expect(driver.animateCount, 0);
      expect(coordinator.revealCount, 0);
      expect(coordinator.lastItemId, 'live-99');
    });

    test('follow 模式 coalesce 同帧多次 tick 为一次 reveal', () {
      expect(coordinator.mode, IdeVirtualScrollMode.followEnd);

      for (var i = 0; i < 5; i++) {
        coordinator.onAutoScrollTick(lastItemId: 'tail');
      }
      expect(pendingFrames, hasLength(1));
      expect(coordinator.pendingFollowEnd, isTrue);
      expect(coordinator.coalescedTickCount, 5);

      flushFrames();
      expect(driver.jumpCount, 1);
      expect(driver.animateCount, 0);
      expect(coordinator.revealCount, 1);
      expect(driver.pixels, driver.maxScrollExtent);
      expect(coordinator.lastItemId, 'tail');
    });

    test('显式按钮进入 follow 并 reveal last ID', () async {
      coordinator.onUserScroll(metrics(pixels: 200));
      expect(coordinator.mode, IdeVirtualScrollMode.free);
      driver.pixels = 200;

      await coordinator.requestFollowEnd(
        lastItemId: 'item-last',
        animated: true,
      );

      expect(coordinator.mode, IdeVirtualScrollMode.followEnd);
      expect(coordinator.lastItemId, 'item-last');
      expect(driver.animateCount, 1);
      expect(driver.pixels, driver.maxScrollExtent);
      expect(coordinator.revealCount, 1);
    });

    test('用户输入取消按钮触发的动画', () async {
      final slow = _SuspendableScrollDriver(maxScrollExtent: 1000)
        ..pixels = 300;
      final pending = <VoidCallback>[];
      final slowCoordinator = IdeVirtualScrollCoordinator(
        driver: slow,
        scheduleFrame: pending.add,
      );
      slowCoordinator.onUserScroll(
        const IdeVirtualScrollMetricsSnapshot(
          pixels: 300,
          maxScrollExtent: 1000,
          viewportDimension: 600,
        ),
      );

      final anim = slowCoordinator.requestFollowEnd(
        lastItemId: 'end',
        animated: true,
      );
      // 让 microtask 进入 animateTo 挂起。
      await Future<void>.delayed(Duration.zero);
      expect(slowCoordinator.isExplicitAnimating, isTrue);

      slowCoordinator.onUserScroll(
        const IdeVirtualScrollMetricsSnapshot(
          pixels: 280,
          maxScrollExtent: 1000,
          viewportDimension: 600,
        ),
      );
      expect(slow.cancelCount, greaterThanOrEqualTo(1));
      expect(slowCoordinator.isExplicitAnimating, isFalse);

      await anim;
    });

    test('last item 在 mutation 中替换时按新 last ID reveal', () {
      expect(coordinator.mode, IdeVirtualScrollMode.followEnd);

      coordinator.updateLastItemId('old-last');
      flushFrames();
      expect(coordinator.lastItemId, 'old-last');
      expect(coordinator.revealCount, 1);

      coordinator.updateLastItemId('new-last');
      flushFrames();
      expect(coordinator.lastItemId, 'new-last');
      expect(coordinator.revealCount, 2);
    });

    test('shouldShowScrollToEndButton 仅 free 且远离底部', () {
      expect(
        coordinator.shouldShowScrollToEndButton(metrics(pixels: 1000)),
        isFalse,
      );

      coordinator.onUserScroll(metrics(pixels: 500));
      expect(coordinator.mode, IdeVirtualScrollMode.free);
      expect(
        coordinator.shouldShowScrollToEndButton(metrics(pixels: 500)),
        isTrue,
      );
      expect(
        coordinator.shouldShowScrollToEndButton(metrics(pixels: 995)),
        isFalse,
      );
    });

    test('followEnd settled 需要连续两帧贴底', () {
      coordinator.onFrameSettled(metrics(pixels: 1000));
      expect(coordinator.isFollowEndSettled, isFalse);
      coordinator.onFrameSettled(metrics(pixels: 1000));
      expect(coordinator.isFollowEndSettled, isTrue);

      coordinator.onFrameSettled(metrics(pixels: 900));
      expect(coordinator.isFollowEndSettled, isFalse);
    });
  });
}

final class _FakeScrollDriver implements IdeVirtualScrollDriver {
  _FakeScrollDriver({required this.maxScrollExtent});

  @override
  double pixels = 0;

  @override
  double maxScrollExtent;

  int jumpCount = 0;
  int animateCount = 0;
  int cancelCount = 0;

  @override
  bool get hasClients => true;

  @override
  void jumpTo(double offset) {
    pixels = offset.clamp(0.0, maxScrollExtent);
    jumpCount += 1;
  }

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) async {
    pixels = offset.clamp(0.0, maxScrollExtent);
    animateCount += 1;
  }

  @override
  void cancelAnimation() {
    cancelCount += 1;
  }
}

final class _SuspendableScrollDriver implements IdeVirtualScrollDriver {
  _SuspendableScrollDriver({required this.maxScrollExtent});

  @override
  double pixels = 0;

  @override
  double maxScrollExtent;

  int cancelCount = 0;
  Completer<void>? _completer;

  @override
  bool get hasClients => true;

  @override
  void jumpTo(double offset) {
    pixels = offset.clamp(0.0, maxScrollExtent);
  }

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) {
    final completer = Completer<void>();
    _completer = completer;
    return completer.future.then((_) {
      pixels = offset.clamp(0.0, maxScrollExtent);
    });
  }

  @override
  void cancelAnimation() {
    cancelCount += 1;
    final completer = _completer;
    _completer = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}
