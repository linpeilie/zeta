import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/metrics/compact_metric_bar.dart';

import 'ide_component_test_harness.dart';

void main() {
  const items = <CompactMetricItem>[
    CompactMetricItem(label: 'Requests', value: '128', icon: Icons.send),
    CompactMetricItem(label: 'Tokens', value: '42k', detail: 'This month'),
    CompactMetricItem(label: 'Cost', value: r'$12.40'),
  ];

  testWidgets('宽屏指标按可用宽度均分', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(900, 220),
      child: const Align(
        alignment: Alignment.topCenter,
        child: CompactMetricBar(items: items),
      ),
    );

    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('42k'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('compact-metric-item-0'))).width,
      moreOrLessEquals((900 - 2) / 3),
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('compact-metric-bar-scroll-view')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('中窄屏指标保持 180px 并可横向滚动', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(500, 220),
      child: const Align(
        alignment: Alignment.topCenter,
        child: CompactMetricBar(items: items),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('compact-metric-item-0'))).width,
      180,
    );
    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('compact-metric-bar-scroll-view')),
    );
    expect(scrollView.scrollDirection, Axis.horizontal);
    expect(tester.takeException(), isNull);
  });
}
