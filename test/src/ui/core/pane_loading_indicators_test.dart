import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('IdeBusySpinner 默认使用 shadcn 静态弧与主题强调色', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpIdeComponent(
        tester,
        child: const Center(
          child: IdeBusySpinner(
            key: ValueKey('busy-spinner'),
            semanticsLabel: 'Task running',
          ),
        ),
      );

      final spinnerFinder = find.byKey(const ValueKey('busy-spinner'));
      final indicatorFinder = find.descendant(
        of: spinnerFinder,
        matching: find.byType(sf.CircularProgressIndicator),
      );
      final indicator = tester.widget<sf.CircularProgressIndicator>(
        indicatorFinder,
      );
      final colors = IdeColors.of(tester.element(spinnerFinder));

      expect(spinnerFinder, findsOneWidget);
      expect(indicatorFinder, findsOneWidget);
      expect(tester.getSize(spinnerFinder), const Size.square(14));
      expect(indicator.size, 14);
      expect(indicator.strokeWidth, 2);
      expect(indicator.color, colors.accent);
      expect(indicator.backgroundColor, Colors.transparent);
      expect(indicator.value, 0.72);
      expect(indicator.animated, isFalse);
      expect(find.bySemanticsLabel('Task running'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('IdeBusySpinner 映射自定义尺寸描边与颜色', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Center(
        child: IdeBusySpinner(
          key: ValueKey('custom-busy-spinner'),
          size: 18,
          strokeWidth: 3,
          color: Colors.orange,
        ),
      ),
    );

    final spinnerFinder = find.byKey(const ValueKey('custom-busy-spinner'));
    final indicator = tester.widget<sf.CircularProgressIndicator>(
      find.descendant(
        of: spinnerFinder,
        matching: find.byType(sf.CircularProgressIndicator),
      ),
    );

    expect(tester.getSize(spinnerFinder), const Size.square(18));
    expect(indicator.size, 18);
    expect(indicator.strokeWidth, 3);
    expect(indicator.color, Colors.orange);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IdeBusySpinner 单次旋转后停止调度帧且重建不重启', (tester) async {
    var semanticsLabel = 'Running';
    late StateSetter rebuild;
    await pumpIdeComponent(
      tester,
      child: StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return Center(child: IdeBusySpinner(semanticsLabel: semanticsLabel));
        },
      ),
    );

    expect(tester.binding.hasScheduledFrame, isTrue);

    final pumpCount = await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );

    expect(pumpCount, greaterThan(0));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byType(IdeBusySpinner), findsOneWidget);

    rebuild(() {
      semanticsLabel = 'Still running';
    });
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(
      tester.widget<IdeBusySpinner>(find.byType(IdeBusySpinner)).semanticsLabel,
      'Still running',
    );
    expect(tester.takeException(), isNull);
  });
}
