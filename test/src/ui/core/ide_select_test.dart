import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_select.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('IdeSelect 展示选中项并使用 bodySmall 字号', (tester) async {
    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.center,
        child: IdeSelect<String>(
          key: const ValueKey('sample-select'),
          width: 180,
          value: 'codex',
          options: const [
            IdeSelectOption('all', '全部 Agent'),
            IdeSelectOption('codex', 'Codex'),
            IdeSelectOption('grok', 'Grok'),
          ],
          onChanged: _noop,
        ),
      ),
    );

    expect(find.byType(sf.Select<String>), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);

    final label = tester.widget<Text>(find.text('Codex'));
    final expectedSize = IdeTextStyles.of(
      tester.element(find.text('Codex')),
    ).bodySmall.fontSize;
    expect(label.style?.fontSize, expectedSize);
    expect(
      tester.getSize(find.byKey(const ValueKey('sample-select'))).height,
      IdeMetrics.toolbarHeight,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('IdeSelect 选择选项后回调 onChanged', (tester) async {
    String? selected;

    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.center,
        child: IdeSelect<String>(
          key: const ValueKey('select-change'),
          width: 180,
          value: 'all',
          options: const [
            IdeSelectOption('all', '全部'),
            IdeSelectOption('codex', 'Codex'),
          ],
          onChanged: (value) => selected = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('select-change')));
    // Select 弹层动画可能不在 finite settle 范围内，显式推进几帧。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Codex').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(selected, 'codex');
    expect(tester.takeException(), isNull);
  });

  testWidgets('IdeSelect 可让弹层宽于紧凑触发器', (tester) async {
    await pumpIdeComponent(
      tester,
      child: Align(
        alignment: Alignment.center,
        child: IdeSelect<String>(
          key: const ValueKey('compact-select'),
          value: 'en',
          popupMinWidth: 180,
          popupWidthPolicy: IdeSelectPopupWidthPolicy.fitContent,
          options: const [
            IdeSelectOption(
              'en',
              'English',
              key: ValueKey('compact-select-english'),
            ),
            IdeSelectOption(
              'zh-Hans',
              '简体中文',
              key: ValueKey('compact-select-zh-hans'),
            ),
          ],
          onChanged: _noop,
        ),
      ),
    );

    final triggerWidth = tester
        .getSize(find.byKey(const ValueKey('compact-select')))
        .width;

    await tester.tap(find.byKey(const ValueKey('compact-select')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final popup = find.byWidgetPredicate((widget) => widget is sf.SelectPopup);
    final popupWidth = tester.getSize(popup).width;
    expect(popupWidth, greaterThanOrEqualTo(180));
    expect(popupWidth, lessThanOrEqualTo(240));
    expect(popupWidth, greaterThan(triggerWidth));
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.descendant(
              of: find.byKey(const ValueKey('compact-select-english')),
              matching: find.text('English'),
            ),
          )
          .didExceedMaxLines,
      isFalse,
    );
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.descendant(
              of: find.byKey(const ValueKey('compact-select-zh-hans')),
              matching: find.text('简体中文'),
            ),
          )
          .didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}

void _noop(String? _) {}
