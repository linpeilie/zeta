import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/core/constants/app_typography.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/ui/core/ide_button.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_select.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';

import 'ide_component_test_harness.dart';

void main() {
  // 控件高度不再是一个常数，而是「2 × 竖向内边距 + 内容行盒，低于点击目标
  // 下限时抬到下限」。断言因此走同一条公式，而不是把 35 抄进测试——公式变了
  // 测试跟着变，数值飘了测试才红。
  for (final uiFontSize in <double>[
    minUiFontSize,
    defaultUiFontSize,
    maxUiFontSize,
  ]) {
    testWidgets('常规 Select、Tabs 与 Button 落在同一条高度公式上（UI 字号 $uiFontSize）', (
      tester,
    ) async {
      await pumpIdeComponent(
        tester,
        uiFontSize: uiFontSize,
        child: const _RegularControls(),
      );

      final expected = IdeMetrics.controlNaturalHeightFor(
        IdeTextStyles.of(
          tester.element(find.byKey(const ValueKey('regular-select'))),
        ).bodySmall,
        size: IdeControlSize.regular,
      );
      final selectHeight = _height(tester, 'regular-select');

      expect(selectHeight, closeTo(expected, 0.01));
      expect(_height(tester, 'regular-tabs'), closeTo(expected, 0.01));
      expect(_height(tester, 'regular-button'), closeTo(expected, 0.01));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('常规控件随 UI 字号连续增长，没有先卡住再突变的台阶', (tester) async {
    // 迁移前的公式在默认字号下永远输给 34 这个下限：12 → 12.9 完全不长，
    // 过了 12.93 才突然开始长。内容撑高之后每一档都必须真的长。
    final heights = <double>[];
    for (final uiFontSize in <double>[12, 13, 14]) {
      await pumpIdeComponent(
        tester,
        uiFontSize: uiFontSize,
        child: const _RegularControls(),
      );
      heights.add(_height(tester, 'regular-select'));
    }

    expect(heights[1], greaterThan(heights[0]));
    expect(heights[2], greaterThan(heights[1]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('UI 字号很小时由点击目标下限兜底', (tester) async {
    await pumpIdeComponent(
      tester,
      uiFontSize: minUiFontSize,
      child: const _RegularControls(),
    );

    expect(
      _height(tester, 'regular-select'),
      greaterThanOrEqualTo(IdeMetrics.controlMinHeightRegular),
    );
    expect(tester.takeException(), isNull);
  });

  // 图标一旦比文字行盒高，它就会成为决定控件高度的那个内容——shadcn 官网的
  // Select 比 Button 高 2px 就是这么来的。控件按内容撑高之后，这条断言是唯一
  // 拦得住它的护栏。
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

    final expected = IdeMetrics.controlNaturalHeightFor(
      IdeTextStyles.of(
        tester.element(find.byKey(const ValueKey('compact-tab'))),
      ).bodySmall,
      size: IdeControlSize.compact,
    );

    expect(_height(tester, 'compact-tab'), closeTo(expected, 0.01));
    expect(_height(tester, 'compact-button'), closeTo(expected, 0.01));
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
