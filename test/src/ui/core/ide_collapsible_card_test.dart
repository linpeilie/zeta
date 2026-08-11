import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/ide_collapsible_card.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('折叠卡片的箭头、leading 图标与单行标题垂直居中', (tester) async {
    const toggleKey = ValueKey<String>('toggle');
    const leadingKey = ValueKey<String>('leading');
    const titleKey = ValueKey<String>('title');

    await pumpIdeComponent(
      tester,
      child: Center(
        child: SizedBox(
          width: 240,
          child: IdeCollapsibleCard(
            expanded: false,
            onToggle: _noop,
            toggleKey: toggleKey,
            leading: const Icon(
              Icons.segment_rounded,
              key: leadingKey,
              size: 14,
            ),
            titleWidget: const Text('9 个文件', key: titleKey),
          ),
        ),
      ),
    );

    final toggleCenter = tester.getCenter(find.byKey(toggleKey)).dy;
    final leadingCenter = tester.getCenter(find.byKey(leadingKey)).dy;
    final titleCenter = tester.getCenter(find.byKey(titleKey)).dy;

    expect(leadingCenter, closeTo(toggleCenter, 0.01));
    expect(titleCenter, closeTo(toggleCenter, 0.01));
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
