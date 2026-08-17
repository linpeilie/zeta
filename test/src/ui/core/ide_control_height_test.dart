import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/ui/core/ide_button.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_select.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';

import 'ide_component_test_harness.dart';

void main() {
  // TODO(step3): 控件改成内容撑高后，把这里的「等于 regularControlHeight」
  // 换成「等于 2 × controlPaddingYFor + 内容行盒」，常量断言随
  // IdeMetrics.regularControlHeight 一起删除。
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

  testWidgets('常规控件在最小 UI 字号下仍然等高', (tester) async {
    await pumpIdeComponent(
      tester,
      uiFontSize: minUiFontSize,
      child: const _RegularControls(),
    );

    final selectHeight = _height(tester, 'regular-select');

    expect(_height(tester, 'regular-tabs'), closeTo(selectHeight, 0.01));
    expect(_height(tester, 'regular-button'), closeTo(selectHeight, 0.01));
    expect(tester.takeException(), isNull);
  });

  // 图标一旦比文字行盒高，它就会成为决定控件高度的那个内容——shadcn 官网的
  // Select 比 Button 高 2px 就是这么来的。控件改成内容撑高后，这条断言是唯一
  // 拦得住它的护栏；在固定高度时期它平凡成立，属于提前埋好的回归网。
  testWidgets('带图标的控件与纯文字控件等高', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IdeButton(key: ValueKey('plain-button'), label: '刷新'),
          IdeButton(
            key: ValueKey('icon-button'),
            label: '刷新',
            leadingIcon: Icons.refresh_rounded,
            trailingIcon: Icons.keyboard_arrow_down_rounded,
          ),
          IdeTab(key: ValueKey('plain-tab'), label: '模型', trailingIcon: null),
          IdeTab(
            key: ValueKey('icon-tab'),
            label: '模型',
            leadingIcon: Icons.tune_rounded,
          ),
        ],
      ),
    );

    final plainButton = _height(tester, 'plain-button');
    final plainTab = _height(tester, 'plain-tab');

    expect(_height(tester, 'icon-button'), closeTo(plainButton, 0.01));
    expect(_height(tester, 'icon-tab'), closeTo(plainTab, 0.01));
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
