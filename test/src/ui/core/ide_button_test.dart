import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_ui/zeta_ui.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('IdeButton 使用 bodySmall 字号并响应点击', (tester) async {
    var presses = 0;

    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.center,
        child: IdeButton(
          key: const ValueKey('sample-button'),
          label: '刷新',
          leadingIcon: Icons.refresh_rounded,
          onPressed: () => presses += 1,
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('刷新'));
    final expectedSize = IdeTextStyles.of(
      tester.element(find.text('刷新')),
    ).bodySmall.fontSize;
    expect(label.style?.fontSize, expectedSize);
    expect(find.byType(sf.Button), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sample-button')));
    await tester.pump();
    expect(presses, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IdeButton.toolbar 使用常规控件高度', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Align(
        alignment: Alignment.center,
        child: IdeButton.toolbar(
          key: ValueKey('toolbar-button'),
          label: '筛选',
          leadingIcon: Icons.calendar_month_rounded,
          trailingIcon: Icons.keyboard_arrow_down_rounded,
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('toolbar-button'))).height,
      closeTo(
        IdeMetrics.controlNaturalHeightFor(
          IdeTextStyles.of(
            tester.element(find.byKey(const ValueKey('toolbar-button'))),
          ).bodySmall,
          size: IdeControlSize.regular,
        ),
        0.01,
      ),
    );
    expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IdeButton 禁用时不触发 onPressed', (tester) async {
    var presses = 0;

    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.center,
        child: IdeButton(
          key: const ValueKey('disabled-button'),
          label: '不可点',
          enabled: false,
          onPressed: () => presses += 1,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('disabled-button')));
    await tester.pump();
    expect(presses, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary 按钮文字与前置图标都使用 onAccent', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Align(
        alignment: Alignment.center,
        child: IdeButton(
          key: ValueKey('primary-button'),
          label: '允许',
          variant: IdeButtonVariant.primary,
          leadingIcon: Icons.check_rounded,
          onPressed: _noop,
        ),
      ),
    );

    final colors = IdeColors.of(tester.element(find.text('允许')));
    expect(tester.widget<Text>(find.text('允许')).style?.color, colors.onAccent);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.check_rounded)).color,
      colors.onAccent,
    );
  });

  testWidgets('键盘焦点关闭 shadcn FocusOutline，改用内侧 Graphite 描边', (tester) async {
    final focusNode = FocusNode(debugLabel: 'ide-button-focus');
    addTearDown(focusNode.dispose);
    addTearDown(() {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
    });
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;

    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.center,
        child: IdeButton(
          key: const ValueKey('focus-button'),
          label: '筛选',
          focusNode: focusNode,
          onPressed: _noop,
        ),
      ),
    );

    expect(
      tester.widget<sf.Button>(find.byType(sf.Button)).disableFocusOutline,
      isTrue,
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(focusNode.hasFocus, isTrue);
    expect(
      tester.widget<sf.FocusOutline>(find.byType(sf.FocusOutline)).focused,
      isFalse,
    );
    final colors = IdeColors.of(
      tester.element(find.byKey(const ValueKey('focus-button'))),
    );
    expect(
      tester.allWidgets.any(
        (widget) => _decorationHasFocusRing(widget, colors.focusRing),
      ),
      isTrue,
    );
  });
}

bool _decorationHasFocusRing(Widget widget, Color focusRing) {
  Object? decoration;
  if (widget is DecoratedBox) {
    decoration = widget.decoration;
  } else if (widget is Container) {
    decoration = widget.decoration;
  } else {
    try {
      decoration = (widget as dynamic).decoration;
    } catch (_) {
      return false;
    }
  }
  if (decoration is BoxDecoration) {
    return decoration.border?.top.color == focusRing;
  }
  if (decoration is ShapeDecoration) {
    final shape = decoration.shape;
    return shape is RoundedRectangleBorder && shape.side.color == focusRing;
  }
  return false;
}

void _noop() {}
