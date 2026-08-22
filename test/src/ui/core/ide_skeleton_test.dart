import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_ui/zeta_ui.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('IdeSkeletonBone 渲染骨块并隔离重绘', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpIdeComponent(
        tester,
        child: const Center(
          child: IdeSkeletonBone(
            key: ValueKey('skeleton-bone'),
            width: 120,
            height: 16,
            semanticsLabel: 'Loading content',
          ),
        ),
      );

      final bone = find.byKey(const ValueKey('skeleton-bone'));
      expect(bone, findsOneWidget);
      expect(tester.getSize(bone), const Size(120, 16));
      expect(find.byType(RepaintBoundary), findsWidgets);
      expect(find.bySemanticsLabel('Loading content'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('减少动态效果时 Skeleton 保持静态透明度', (tester) async {
    await pumpIdeComponent(
      tester,
      child: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: const Center(
          child: IdeSkeletonBone(
            key: ValueKey('static-bone'),
            width: 80,
            height: 12,
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('static-bone')),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('static-bone')),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, closeTo(0.72, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('IdeSkeletonLine / Block 使用约定高度', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IdeSkeletonLine(key: ValueKey('line'), width: 100),
          IdeSkeletonBlock(key: ValueKey('block'), width: 100, height: 64),
        ],
      ),
    );

    expect(tester.getSize(find.byKey(const ValueKey('line'))).height, 12);
    expect(
      tester.getSize(find.byKey(const ValueKey('block'))),
      const Size(100, 64),
    );
    expect(tester.takeException(), isNull);
  });
}
