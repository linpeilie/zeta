import 'package:app_ui/app_ui.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/helpers.dart';

const _epoch = IdeLayoutEpoch(
  crossAxisExtentInPhysicalPixels: 400,
  textScaleKey: 1,
  localeKey: 'en',
  typographyEpoch: 1,
);

IdeVirtualItemDescriptor _item(
  String id, {
  double extent = 40,
  Object revision = 1,
  String kind = 'row',
}) => IdeVirtualItemDescriptor(
  id: id,
  kind: kind,
  layoutRevision: revision,
  estimatedExtent: extent,
);

void main() {
  group('virtualization value and controller contracts', () {
    test('layout epochs expose value equality, hash, and diagnostics', () {
      const same = IdeLayoutEpoch(
        crossAxisExtentInPhysicalPixels: 400,
        textScaleKey: 1,
        localeKey: 'en',
        typographyEpoch: 1,
      );
      const different = IdeLayoutEpoch(
        crossAxisExtentInPhysicalPixels: 401,
        textScaleKey: 1,
        localeKey: 'en',
        typographyEpoch: 1,
      );

      expect(_epoch, same);
      expect(_epoch.hashCode, same.hashCode);
      expect(_epoch, isNot(different));
      expect(_epoch, isNot('epoch'));
      expect(
        _epoch.toString(),
        'IdeLayoutEpoch(crossAxis=400, textScale=1, locale=en, typography=1)',
      );
    });

    test('controller covers pending, measurement, anchor, and diagnostics', () {
      final controller = IdeVirtualListController();
      expect(controller.itemCount, 0);
      expect(controller.descriptors, isEmpty);
      expect(controller.epoch, isNull);
      expect(controller.offsetOfId('missing'), isNull);
      expect(controller.captureAnchor(0), isNull);
      expect(controller.applyPendingSequence(), isFalse);
      expect(controller.computeScrollCorrection(null), 0);

      final initial = <IdeVirtualItemDescriptor>[
        _item('zero', extent: 0),
        _item('a'),
        _item('b'),
      ];
      controller.synchronizeNow(initial, epoch: _epoch);
      expect(controller.extentIndex.synchronizeGeneration, 1);
      expect(controller.indexOfId('a'), 1);
      expect(controller.offsetOfId('a'), 0);
      expect(controller.totalExtent, 80);

      final zeroAnchor = controller.captureAnchor(0)!;
      expect(zeroAnchor.anchor.itemId, 'a');
      expect(zeroAnchor.anchor.intraItemOffset, 0);

      controller
        ..recordAnchorCorrection(0)
        ..recordAnchorCorrection(-12)
        ..recordAnchorCorrection(4)
        ..recordMeasurementUpdate();
      expect(controller.debugAnchorCorrectionCount, 2);
      expect(controller.debugMaxSingleCorrection, 12);
      expect(controller.debugMeasurementUpdateCount, 1);

      controller.extentIndex.updateMeasuredExtent(
        index: 1,
        measuredExtent: 60,
        epoch: _epoch,
      );
      expect(controller.measuredCount, 1);
      expect(controller.freshMeasurementCount, 1);

      controller.setItems(initial, epoch: _epoch);
      expect(controller.debugSetItemsNoOpCount, 1);

      final changed = <IdeVirtualItemDescriptor>[
        _item('a', extent: 60),
        _item('c', extent: 30),
      ];
      controller.setItems(changed, epoch: _epoch);
      expect(controller.hasPendingSequence, isTrue);
      expect(controller.itemCount, 2);
      expect(controller.descriptors, changed);
      expect(controller.applyPendingSequence(), isTrue);
      expect(controller.hasPendingSequence, isFalse);

      controller
        ..debugLaidOutChildCount = 3
        ..resetDebugMetrics();
      expect(controller.debugAnchorCorrectionCount, 0);
      expect(controller.debugMaxSingleCorrection, 0);
      expect(controller.debugMeasurementUpdateCount, 0);
      expect(controller.debugLaidOutChildCount, 0);
    });

    test('anchor fallback searches backward and then the new first item', () {
      final controller = IdeVirtualListController()
        ..synchronizeNow(
          <IdeVirtualItemDescriptor>[_item('a'), _item('b'), _item('c')],
          epoch: _epoch,
        );
      final fromLast = controller.captureAnchor(90)!;
      controller.synchronizeNow(<IdeVirtualItemDescriptor>[
        _item('a'),
      ], epoch: _epoch);
      expect(controller.computeScrollCorrection(fromLast), -90);

      const missingSnapshot = IdeAnchorSnapshot(
        anchor: IdeScrollAnchor(
          itemId: 'old',
          intraItemOffset: 5,
          viewportOffset: 0,
        ),
        oldContentOffset: 25,
        oldIndex: 0,
        oldOrderedIds: <String>['old'],
      );
      controller.synchronizeNow(<IdeVirtualItemDescriptor>[
        _item('new'),
      ], epoch: _epoch);
      expect(controller.computeScrollCorrection(missingSnapshot), -25);
      controller.synchronizeNow(
        const <IdeVirtualItemDescriptor>[],
        epoch: _epoch,
      );
      expect(controller.computeScrollCorrection(missingSnapshot), 0);
    });

    test('Fenwick and extent index expose defensive public contracts', () {
      final tree = IdeFenwickTree(<double>[1, 2]);
      expect(tree.length, 2);
      tree.add(0, 0);
      expect(tree.total, 3);

      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[_item('a')], epoch: _epoch);
      expect(index.recordForId('a')?.id, 'a');
      expect(() => index.extentAt(2), throwsRangeError);
    });
  });

  group('scroll driver and coordinator contracts', () {
    testWidgets(
      'ScrollController driver handles detached and attached states',
      (
        tester,
      ) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final driver = IdeScrollControllerDriver(controller);

        expect(driver.hasClients, isFalse);
        expect(driver.pixels, 0);
        expect(driver.maxScrollExtent, 0);
        driver
          ..jumpTo(20)
          ..cancelAnimation();
        await driver.animateTo(
          20,
          duration: Duration.zero,
          curve: Curves.linear,
        );

        await tester.pumpShadcnApp(
          SizedBox(
            height: 100,
            child: ListView.builder(
              controller: controller,
              itemCount: 20,
              itemExtent: 40,
              itemBuilder: (_, index) => Text('row $index'),
            ),
          ),
          size: const Size(300, 200),
        );
        await tester.pumpAndSettle();

        expect(driver.hasClients, isTrue);
        expect(driver.maxScrollExtent, greaterThan(0));
        driver.jumpTo(100000);
        expect(driver.pixels, driver.maxScrollExtent);
        driver.jumpTo(0);
        final animation = driver.animateTo(
          120,
          duration: const Duration(milliseconds: 50),
          curve: Curves.linear,
        );
        await tester.pumpAndSettle();
        await animation;
        expect(driver.pixels, 120);
        driver.cancelAnimation();
      },
    );

    testWidgets(
      'default scheduling, metrics, and animated offset are covered',
      (
        tester,
      ) async {
        const invalidMetrics = IdeVirtualScrollMetricsSnapshot(
          pixels: double.nan,
          maxScrollExtent: double.infinity,
          viewportDimension: 100,
        );
        expect(invalidMetrics.endDistance, 0);
        expect(invalidMetrics.isWithinEnd(0), isTrue);
        const overscrolled = IdeVirtualScrollMetricsSnapshot(
          pixels: 20,
          maxScrollExtent: 10,
          viewportDimension: 100,
        );
        expect(overscrolled.endDistance, 0);

        await tester.pumpShadcnApp(const SizedBox.shrink());
        final withoutDriver = IdeVirtualScrollCoordinator()
          ..notifyContentChanged(lastItemId: 'last');
        await tester.pump();
        expect(withoutDriver.revealCount, 1);

        final driver = _ContractDriver(maxScrollExtent: 200);
        final coordinator = IdeVirtualScrollCoordinator(driver: driver);
        await coordinator.requestScrollToOffset(offset: 150);
        expect(driver.pixels, 150);
        expect(driver.animateCount, 1);
        expect(coordinator.isExplicitAnimating, isFalse);

        coordinator
          ..onFrameSettled(
            const IdeVirtualScrollMetricsSnapshot(
              pixels: 0,
              maxScrollExtent: 200,
              viewportDimension: 100,
            ),
          )
          ..requestFreeScroll()
          ..onFrameSettled(
            const IdeVirtualScrollMetricsSnapshot(
              pixels: 0,
              maxScrollExtent: 200,
              viewportDimension: 100,
            ),
          );
        expect(coordinator.isFollowEndSettled, isFalse);
      },
    );

    testWidgets('smooth position handles clamped targets and corrections', (
      tester,
    ) async {
      final controller = IdeSmoothScrollController(
        smoothScrollingEnabled: true,
      );
      addTearDown(controller.dispose);
      await tester.pumpShadcnApp(
        SizedBox(
          height: 100,
          child: ListView.builder(
            controller: controller,
            itemCount: 20,
            itemExtent: 40,
            itemBuilder: (_, index) => Text('smooth contract $index'),
          ),
        ),
        size: const Size(300, 200),
      );
      await tester.pumpAndSettle();

      final position = controller.position..pointerScroll(-20);
      expect(position.pixels, 0);

      position
        ..pointerScroll(120)
        ..correctBy(5)
        ..jumpTo(20);
      await tester.pumpAndSettle();
      expect(position.pixels, 20);
    });

    testWidgets('notification bridge accepts only attached user scrolls', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final detachedController = ScrollController();
      addTearDown(detachedController.dispose);
      final coordinator = IdeVirtualScrollCoordinator();

      await tester.pumpShadcnApp(
        SizedBox(
          height: 100,
          child: ListView.builder(
            controller: controller,
            itemCount: 20,
            itemExtent: 40,
            itemBuilder: (_, index) => Text('bridge $index'),
          ),
        ),
        size: const Size(300, 200),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(ListView));
      final metrics = controller.position;

      expect(
        dispatchUserScrollToCoordinator(
          coordinator: coordinator,
          notification: ScrollUpdateNotification(
            metrics: metrics,
            context: context,
            scrollDelta: 1,
          ),
          controller: detachedController,
        ),
        isFalse,
      );

      coordinator.beginProgrammaticScroll();
      expect(
        dispatchUserScrollToCoordinator(
          coordinator: coordinator,
          notification: UserScrollNotification(
            metrics: metrics,
            context: context,
            direction: ScrollDirection.forward,
          ),
          controller: controller,
        ),
        isFalse,
      );
      coordinator.endProgrammaticScroll();

      expect(
        dispatchUserScrollToCoordinator(
          coordinator: coordinator,
          notification: ScrollUpdateNotification(
            metrics: metrics,
            context: context,
            scrollDelta: 1,
            dragDetails: DragUpdateDetails(
              globalPosition: Offset.zero,
              delta: const Offset(0, -1),
            ),
          ),
          controller: controller,
        ),
        isTrue,
      );
      expect(
        dispatchUserScrollToCoordinator(
          coordinator: coordinator,
          notification: UserScrollNotification(
            metrics: metrics,
            context: context,
            direction: ScrollDirection.forward,
          ),
          controller: controller,
        ),
        isTrue,
      );
    });
  });
}

final class _ContractDriver implements IdeVirtualScrollDriver {
  _ContractDriver({required this.maxScrollExtent});

  @override
  bool hasClients = true;

  @override
  double pixels = 0;

  @override
  double maxScrollExtent;

  int animateCount = 0;

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) async {
    animateCount += 1;
    pixels = offset;
  }

  @override
  void cancelAnimation() {}

  @override
  void jumpTo(double offset) {
    pixels = offset;
  }
}
