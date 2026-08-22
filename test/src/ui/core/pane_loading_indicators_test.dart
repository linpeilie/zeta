import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_ui/zeta_ui.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('IdeBusySpinner 默认使用持续动画并隔离重绘', (tester) async {
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
      final repaintBoundaryElement = _singleChildElement(
        _singleChildElement(tester.element(spinnerFinder)),
      );
      final colors = IdeColors.of(tester.element(spinnerFinder));

      expect(spinnerFinder, findsOneWidget);
      expect(indicatorFinder, findsOneWidget);
      expect(repaintBoundaryElement.widget, isA<RepaintBoundary>());
      expect(tester.getSize(spinnerFinder), const Size.square(14));
      expect(indicator.size, 14);
      expect(indicator.strokeWidth, 2);
      expect(indicator.color, colors.accent);
      expect(indicator.backgroundColor, Colors.transparent);
      expect(indicator.value, isNull);
      expect(indicator.animated, isTrue);
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

  testWidgets('IdeBusySpinner 运行时持续调度帧并可随状态移除', (tester) async {
    var running = true;
    late StateSetter rebuild;
    await pumpIdeComponent(
      tester,
      child: StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return Center(
            child: running
                ? const IdeBusySpinner(semanticsLabel: 'Running')
                : const SizedBox.shrink(),
          );
        },
      ),
    );

    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(find.byType(IdeBusySpinner), findsOneWidget);

    rebuild(() {
      running = false;
    });
    await tester.pump();

    expect(find.byType(IdeBusySpinner), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Element _singleChildElement(Element parent) {
  final children = <Element>[];
  parent.visitChildElements(children.add);
  expect(children, hasLength(1));
  return children.single;
}
