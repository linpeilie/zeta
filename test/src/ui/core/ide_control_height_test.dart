import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/ui/core/ide_button.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_select.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('常规 Select、Tabs 与工具栏 Button 使用同一外框高度', (tester) async {
    await pumpIdeComponent(tester, child: const _RegularControls());

    final selectHeight = _height(tester, 'regular-select');
    final tabsHeight = _height(tester, 'regular-tabs');
    final buttonHeight = _height(tester, 'regular-button');

    expect(selectHeight, IdeMetrics.regularControlHeight);
    expect(tabsHeight, selectHeight);
    expect(buttonHeight, selectHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('常规控件在最大 UI 字号下同步增长且不溢出', (tester) async {
    await pumpIdeComponent(
      tester,
      uiFontSize: maxUiFontSize,
      child: const _RegularControls(),
    );

    final selectHeight = _height(tester, 'regular-select');
    final tabsHeight = _height(tester, 'regular-tabs');
    final buttonHeight = _height(tester, 'regular-button');

    expect(selectHeight, greaterThan(IdeMetrics.regularControlHeight));
    expect(tabsHeight, closeTo(selectHeight, 0.01));
    expect(buttonHeight, closeTo(selectHeight, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立 Tab 与普通 Button 使用同一紧凑高度', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IdeTab(key: ValueKey('compact-tab'), label: '模型'),
          IdeButton(key: ValueKey('compact-button'), label: '刷新'),
        ],
      ),
    );

    final tabHeight = _height(tester, 'compact-tab');
    final buttonHeight = _height(tester, 'compact-button');

    expect(tabHeight, IdeMetrics.compactControlHeight);
    expect(buttonHeight, tabHeight);
    expect(tester.takeException(), isNull);
  });
}

class _RegularControls extends StatelessWidget {
  const _RegularControls();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IdeSelect<String>(
          key: const ValueKey('regular-select'),
          width: 120,
          value: 'english',
          options: const [IdeSelectOption('english', 'English')],
          onChanged: _onSelectChanged,
        ),
        IdeTabs<String>(
          key: const ValueKey('regular-tabs'),
          value: 'enter',
          items: const [IdeTabItem(value: 'enter', label: 'Enter to send')],
          onChanged: _onTabChanged,
        ),
        const IdeButton.toolbar(key: ValueKey('regular-button'), label: '刷新'),
      ],
    );
  }
}

double _height(WidgetTester tester, String key) {
  return tester.getSize(find.byKey(ValueKey<String>(key))).height;
}

void _onSelectChanged(String? _) {}

void _onTabChanged(String _) {}
