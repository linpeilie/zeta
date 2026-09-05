import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_ui/zeta_ui.dart';

import 'ide_component_test_harness.dart';

/// 轨道是 IdeSwitch 内最外层的 AnimatedContainer。
BoxDecoration _trackDecoration(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find
        .descendant(
          of: find.byType(IdeSwitch),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return container.decoration! as BoxDecoration;
}

/// 滑块是轨道内的第二个 AnimatedContainer。
BoxDecoration _thumbDecoration(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find
        .descendant(
          of: find.byType(IdeSwitch),
          matching: find.byType(AnimatedContainer),
        )
        .at(1),
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets('点击切换并回传新值', (tester) async {
    bool? received;
    await pumpIdeComponent(
      tester,
      child: Center(
        child: IdeSwitch(
          key: const ValueKey('switch'),
          value: false,
          onChanged: (value) => received = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('switch')));
    await tester.pumpAndSettle();

    expect(received, isTrue);
  });

  testWidgets('禁用时忽略点击', (tester) async {
    var changed = false;
    await pumpIdeComponent(
      tester,
      child: Center(
        child: IdeSwitch(
          key: const ValueKey('switch'),
          value: false,
          enabled: false,
          onChanged: (_) => changed = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('switch')), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(changed, isFalse);
  });

  testWidgets('onChanged 为 null 时同样不可交互', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Center(
        child: IdeSwitch(key: ValueKey('switch'), value: true, onChanged: null),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('switch')), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('键盘空格与回车都能激活', (tester) async {
    var toggles = 0;
    await pumpIdeComponent(
      tester,
      child: Center(
        child: IdeSwitch(
          key: const ValueKey('switch'),
          value: false,
          onChanged: (_) => toggles++,
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(toggles, 2);
  });

  testWidgets('轨道与滑块圆角取自设计系统递减档位', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Center(
        child: IdeSwitch(key: ValueKey('switch'), value: true, onChanged: null),
      ),
    );

    expect(_trackDecoration(tester).borderRadius, IdeRadius.allSmall);
    expect(_thumbDecoration(tester).borderRadius, IdeRadius.allMicro);

    final size = tester.getSize(find.byKey(const ValueKey('switch')));
    expect(size.width, IdeMetrics.switchTrackWidth);
    expect(size.height, IdeMetrics.switchTrackHeight);
  });

  testWidgets('禁用态仍能区分开与关', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const Center(
        child: IdeSwitch(
          key: ValueKey('on'),
          value: true,
          enabled: false,
          onChanged: null,
        ),
      ),
    );
    final disabledOn = _trackDecoration(tester).color;

    await pumpIdeComponent(
      tester,
      child: const Center(
        child: IdeSwitch(
          key: ValueKey('off'),
          value: false,
          enabled: false,
          onChanged: null,
        ),
      ),
    );
    final disabledOff = _trackDecoration(tester).color;

    expect(disabledOn, isNot(disabledOff));
    // 禁用的打开态用 primaryMuted，与启用态的 accent 拉开但仍保留色相。
    expect(disabledOn, IdeColors.dark.primaryMuted);
    expect(disabledOff, IdeColors.dark.controlSurface);
  });

  testWidgets('打开态使用 accent 轨道，关闭态描边把轨道勾出来', (tester) async {
    await pumpIdeComponent(
      tester,
      child: Center(child: IdeSwitch(value: true, onChanged: (_) {})),
    );
    expect(_trackDecoration(tester).color, IdeColors.dark.accent);
    expect(_trackDecoration(tester).border, isNull);

    await pumpIdeComponent(
      tester,
      child: Center(child: IdeSwitch(value: false, onChanged: (_) {})),
    );
    expect(_trackDecoration(tester).color, IdeColors.dark.controlSurface);
    expect(_trackDecoration(tester).border, isNotNull);
  });
}
