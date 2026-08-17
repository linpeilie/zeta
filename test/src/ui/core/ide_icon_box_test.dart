import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/core/constants/app_typography.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/ui/core/ide_icon_box.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';

import 'ide_component_test_harness.dart';

void main() {
  // 这一组断言是「控件改成内容撑高」的前置条件：只要图标盒始终等于文字行盒，
  // 拆掉固定高度后带图标与纯文字的控件就不会分叉。
  for (final uiFontSize in <double>[
    minUiFontSize,
    defaultUiFontSize,
    maxUiFontSize,
  ]) {
    testWidgets('图标盒与文字行盒等高（UI 字号 $uiFontSize）', (tester) async {
      await _pumpLoose(
        tester,
        uiFontSize: uiFontSize,
        child: Builder(
          builder: (context) {
            // 必须显式给 bodySmall：环境里的 DefaultTextStyle 来自 shadcn
            // （14px），拿它当基准量出来的行盒不是控件真正用的那一档。
            final style = IdeTextStyles.of(context).bodySmall;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Refresh 刷新',
                  key: const ValueKey('probe-text'),
                  style: style,
                ),
                const IdeIconBox(
                  Icons.refresh_rounded,
                  key: ValueKey('probe-icon'),
                ),
              ],
            );
          },
        ),
      );

      final textHeight = _height(tester, 'probe-text');
      final iconBoxSize = _size(tester, 'probe-icon');

      expect(iconBoxSize.height, textHeight);
      expect(iconBoxSize.width, textHeight);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('图标盒边长由 controlIconBoxFor 解析', (tester) async {
    late TextStyle bodySmall;
    await _pumpLoose(
      tester,
      child: Builder(
        builder: (context) {
          bodySmall = IdeTextStyles.of(context).bodySmall;
          return const IdeIconBox(
            Icons.refresh_rounded,
            key: ValueKey('probe-icon'),
          );
        },
      ),
    );

    expect(
      _height(tester, 'probe-icon'),
      IdeMetrics.controlIconBoxFor(bodySmall),
    );
  });

  testWidgets('过大的字形被夹回图标盒，不撑高控件', (tester) async {
    await _pumpLoose(
      tester,
      child: const IdeIconBox(
        Icons.refresh_rounded,
        // 远大于行盒：如果没有夹紧，这里会把外框撑到 64。
        size: 64,
        key: ValueKey('probe-icon'),
      ),
    );

    final iconBoxHeight = _height(tester, 'probe-icon');

    expect(iconBoxHeight, lessThan(64));
    expect(tester.getSize(find.byType(Icon)).height, iconBoxHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自定义子组件同样被固定在等高方框内', (tester) async {
    await _pumpLoose(
      tester,
      child: Builder(
        builder: (context) {
          final style = IdeTextStyles.of(context).bodySmall;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Refresh 刷新',
                key: const ValueKey('probe-text'),
                style: style,
              ),
              const IdeIconBox.custom(
                key: ValueKey('probe-icon'),
                child: Icon(Icons.expand_more_rounded, size: 13),
              ),
            ],
          );
        },
      ),
    );

    expect(_height(tester, 'probe-icon'), _height(tester, 'probe-text'));
    expect(tester.takeException(), isNull);
  });
}

/// 用松约束承载被测组件。
///
/// 直接塞进 harness 根节点会拿到 `SizedBox.expand` 的紧约束——`SizedBox` 在
/// 紧约束下只能服从父级，量到的是整块画布而不是图标盒。控件内部（Row / Button
/// 的 leading 位）拿到的都是松约束，这里保持一致。
Future<void> _pumpLoose(
  WidgetTester tester, {
  required Widget child,
  double uiFontSize = defaultUiFontSize,
}) {
  return pumpIdeComponent(
    tester,
    uiFontSize: uiFontSize,
    child: Align(alignment: Alignment.topLeft, child: child),
  );
}

Size _size(WidgetTester tester, String key) {
  return tester.getSize(find.byKey(ValueKey<String>(key)));
}

double _height(WidgetTester tester, String key) => _size(tester, key).height;
