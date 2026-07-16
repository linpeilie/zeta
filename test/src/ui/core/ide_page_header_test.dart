import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/workbench/ide_page_header.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('IdePageHeader 呈现标题、说明、前导和动作区', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Align(
        alignment: Alignment.topCenter,
        child: IdePageHeader(
          key: ValueKey('page-header'),
          title: 'Settings',
          subtitle: 'Appearance and behavior',
          leading: Icon(Icons.arrow_back),
          actions: [Text('Reset'), Text('Save')],
        ),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance and behavior'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('page-header'))).height,
      IdeMetrics.pageHeaderHeight,
    );
  });

  testWidgets('窄屏长标题和多个动作不产生横向溢出', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(260, 200),
      child: const Align(
        alignment: Alignment.topCenter,
        child: IdePageHeader(
          title: 'A very long settings page title that must be truncated',
          leading: Icon(Icons.arrow_back),
          actions: [Text('First action'), Text('Second action')],
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('ide-page-header-actions')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
